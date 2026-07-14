"""Model router: one LLM binding per NPC, plus a shared embedding binding.

Providers:
  - "openai_compatible": works with vLLM, llama.cpp server, Ollama, LM Studio,
    or any hosted OpenAI-compatible endpoint. This is the "bind any LLM" seam.
  - "mock": canned replies, no GPU needed — for wiring tests and offline dev.
    The mock brain follows the agent's embedded scripted suggestion for
    decisions; the mock embedder is a deterministic bag-of-words hash, so
    texts sharing words really do score as similar.
"""

import hashlib
import math
import re

import httpx

_WORD = re.compile(r"[a-zA-Z']+")

_MOCK_CONVERSE_LINES = [
    "The river was kind today.",
    "I have been working the stone. Slow, but it comes.",
    "The cold is coming. We should ready ourselves.",
    "You look well. The hunt was good?",
]

_MOCK_REFLECT = '{"beliefs": ["I have been busy with stone and food.", ' \
    '"The days pass steady; nothing hunts us yet."]}'


class LLM:
    def __init__(self, cfg: dict):
        cfg = cfg or {}
        self.provider = cfg.get("provider", "openai_compatible")
        self.base_url = str(cfg.get("base_url", "http://127.0.0.1:8000/v1")).rstrip("/")
        self.model = cfg.get("model", "")
        self.api_key = str(cfg.get("api_key", "none"))
        self.temperature = float(cfg.get("temperature", 0.8))
        self.max_tokens = int(cfg.get("max_tokens", 220))
        self._mock_turn = 0

    async def chat(self, messages: list, json_mode: bool = False) -> str:
        if self.provider == "mock":
            return self._mock_chat(messages, json_mode)

        payload = {
            "model": self.model,
            "messages": messages,
            "temperature": self.temperature,
            "max_tokens": self.max_tokens,
        }
        if json_mode:
            payload["response_format"] = {"type": "json_object"}
        headers = {"Authorization": f"Bearer {self.api_key}"}
        async with httpx.AsyncClient(timeout=90.0) as client:
            r = await client.post(f"{self.base_url}/chat/completions", json=payload, headers=headers)
            if r.status_code >= 400 and json_mode:
                # endpoint may not support response_format — retry without it
                payload.pop("response_format", None)
                r = await client.post(f"{self.base_url}/chat/completions", json=payload, headers=headers)
            r.raise_for_status()
            return r.json()["choices"][0]["message"]["content"] or ""

    def _mock_chat(self, messages: list, json_mode: bool) -> str:
        text = "\n".join(str(m.get("content", "")) for m in messages)
        if json_mode:
            # TEST-ONLY raid hook: hostility is mind-driven by design and the
            # mock is a scripted mind, so it only ever raids when the test
            # harness explicitly asks for it via VOX_MOCK_RAID=1 (works in
            # both flavors — emergent prompts have no SUGGESTED_ACTION)
            import os as _os
            if _os.environ.get("VOX_MOCK_RAID") == "1":
                m = re.search(r'raid target "([a-z0-9_]+)"', text)
                if m:
                    return ('{"action": "raid", "target": "%s", "say": ""}'
                            % m.group(1))
            i = text.find("SUGGESTED_ACTION: ")
            if i >= 0:
                line = text[i + len("SUGGESTED_ACTION: "):].splitlines()[0]
                # a mock mind with nothing better to do sometimes runs its
                # routines — keeps the skill executor exercised in offline
                # e2e runs without the whole village thrashing one habit
                if '"wander"' in line and len(text) % 4 == 0:
                    m = re.search(r'skill target "([a-z0-9_]+)"', text)
                    if m:
                        return ('{"action": "skill", "target": "%s", "say": ""}'
                                % m.group(1))
                return line
            if "Distill" in text:
                return _MOCK_REFLECT
            if "Compose ONE reusable routine" in text:
                return ('{"name": "berry_run", "description": "gather berries '
                        'and put the surplus in the store", "steps": '
                        '[{"action": "gather", "target": "berry_bush"}, '
                        '{"action": "deposit", "target": "berries"}]}')
            return '{"action": "wander", "target": "", "say": ""}'
        if "Agree the plan" in text:
            return ("Keep the fire fed and the larder full: berries and "
                    "branches in the morning, rest when the light goes.")
        if "dawn council" in text:
            return ("I gathered what I could yesterday. Today we should "
                    "stock the store and mind the fire.")
        if "talking with" in text:
            self._mock_turn += 1
            return _MOCK_CONVERSE_LINES[self._mock_turn % len(_MOCK_CONVERSE_LINES)]
        return "The wind is honest today, stranger. Ask, and I will answer plainly."


class Embedder:
    """Shared embedding binding (memory relevance). Failure-tolerant: returns
    None on any error so retrieval degrades to keyword scoring."""

    DIM = 64  # mock dimension

    def __init__(self, cfg: dict):
        cfg = cfg or {}
        self.provider = cfg.get("provider", "mock")
        self.base_url = str(cfg.get("base_url", "http://127.0.0.1:8000/v1")).rstrip("/")
        self.model = cfg.get("model", "")
        self.api_key = str(cfg.get("api_key", "none"))

    async def embed(self, text: str):
        text = (text or "").strip()
        if not text:
            return None
        if self.provider == "mock":
            return self._hash_embed(text)
        try:
            headers = {"Authorization": f"Bearer {self.api_key}"}
            async with httpx.AsyncClient(timeout=30.0) as client:
                r = await client.post(
                    f"{self.base_url}/embeddings",
                    json={"model": self.model, "input": text},
                    headers=headers,
                )
                r.raise_for_status()
                return r.json()["data"][0]["embedding"]
        except Exception:
            return None

    @classmethod
    def _hash_embed(cls, text: str):
        vec = [0.0] * cls.DIM
        for word in _WORD.findall(text.lower()):
            h = int(hashlib.md5(word.encode()).hexdigest(), 16)
            vec[h % cls.DIM] += 1.0
        norm = math.sqrt(sum(v * v for v in vec))
        return [v / norm for v in vec] if norm > 0 else None


def make_llm(cfg: dict) -> LLM:
    return LLM(cfg)


def make_embedder(cfg: dict) -> Embedder:
    return Embedder(cfg)
