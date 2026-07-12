"""Per-NPC persistent state: memory stream, relationships, known tech. SQLite.

P1 retrieval was importance + keyword overlap + recency. P3 adds an embedding
per memory (BLOB of packed floats) and folds cosine relevance into the score;
when embeddings are unavailable the old keyword scoring still carries it.
"""

import re
import sqlite3
import struct
import threading
import time
from pathlib import Path

_WORD = re.compile(r"[a-zA-Z']+")


def _pack(vec) -> bytes:
    return struct.pack(f"{len(vec)}f", *vec)


def _unpack(blob: bytes):
    return list(struct.unpack(f"{len(blob) // 4}f", blob))


def _cosine(a, b) -> float:
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    na = sum(x * x for x in a) ** 0.5
    nb = sum(y * y for y in b) ** 0.5
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


class Memory:
    def __init__(self, path: str):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._db = sqlite3.connect(path, check_same_thread=False)
        self._db.execute(
            """CREATE TABLE IF NOT EXISTS memories(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts REAL NOT NULL,
                kind TEXT NOT NULL,
                text TEXT NOT NULL,
                importance REAL NOT NULL,
                embedding BLOB)"""
        )
        cols = [r[1] for r in self._db.execute("PRAGMA table_info(memories)")]
        if "embedding" not in cols:  # P1/P2-era database
            self._db.execute("ALTER TABLE memories ADD COLUMN embedding BLOB")
        self._db.execute(
            """CREATE TABLE IF NOT EXISTS relationships(
                other TEXT PRIMARY KEY,
                affinity REAL NOT NULL DEFAULT 0,
                trust REAL NOT NULL DEFAULT 0,
                familiarity REAL NOT NULL DEFAULT 0,
                note TEXT,
                ts REAL NOT NULL)"""
        )
        self._db.execute(
            """CREATE TABLE IF NOT EXISTS techs(
                tech TEXT PRIMARY KEY,
                source TEXT,
                ts REAL NOT NULL)"""
        )
        self._db.execute(
            """CREATE TABLE IF NOT EXISTS state(
                key TEXT PRIMARY KEY,
                value TEXT)"""
        )
        self._db.execute(
            """CREATE TABLE IF NOT EXISTS skills(
                name TEXT PRIMARY KEY,
                description TEXT,
                steps_json TEXT NOT NULL,
                source TEXT,
                uses INTEGER NOT NULL DEFAULT 0,
                ts REAL NOT NULL)"""
        )
        self._db.commit()

    # ------------------------------------------------------------ memories

    def add(self, kind: str, text: str, importance: float = 3.0, embedding=None) -> None:
        text = (text or "").strip()
        if not text:
            return
        blob = _pack(embedding) if embedding else None
        with self._lock:
            self._db.execute(
                "INSERT INTO memories(ts, kind, text, importance, embedding) VALUES(?,?,?,?,?)",
                (time.time(), kind, text, float(importance), blob),
            )
            self._db.commit()

    def recent(self, kinds=None, limit: int = 10) -> list:
        """Newest-last list of (ts, kind, text, importance)."""
        q = "SELECT ts, kind, text, importance FROM memories"
        args: list = []
        if kinds:
            q += " WHERE kind IN (%s)" % ",".join("?" * len(kinds))
            args += list(kinds)
        q += " ORDER BY id DESC LIMIT ?"
        args.append(limit)
        with self._lock:
            rows = self._db.execute(q, args).fetchall()
        return list(reversed(rows))

    def retrieve(self, query: str, k: int = 6, pool: int = 300, query_emb=None) -> list:
        """Top-k (ts, kind, text) scored by importance + relevance + recency.
        Relevance = cosine on embeddings when both sides have one, plus
        keyword overlap as a floor/fallback."""
        toks = set(_WORD.findall((query or "").lower()))
        now = time.time()
        with self._lock:
            rows = self._db.execute(
                "SELECT ts, kind, text, importance, embedding FROM memories "
                "ORDER BY id DESC LIMIT ?",
                (pool,),
            ).fetchall()
        scored = []
        for ts, kind, text, imp, blob in rows:
            overlap = len(toks & set(_WORD.findall(text.lower())))
            recency = 1.0 / (1.0 + (now - ts) / 3600.0)
            sim = 0.0
            if query_emb is not None and blob:
                sim = _cosine(query_emb, _unpack(blob))
            score = imp + 2.0 * overlap + 2.0 * recency + 6.0 * sim
            scored.append((score, ts, kind, text))
        scored.sort(key=lambda s: s[0], reverse=True)
        return [(ts, kind, text) for _, ts, kind, text in scored[:k]]

    # ------------------------------------------------------------ relationships

    def rel_update(self, other: str, d_affinity: float = 0.0, d_trust: float = 0.0,
                   d_familiarity: float = 0.0, note: str = None) -> None:
        with self._lock:
            row = self._db.execute(
                "SELECT affinity, trust, familiarity, note FROM relationships WHERE other=?",
                (other,),
            ).fetchone()
            aff, tru, fam, old_note = row if row else (0.0, 0.0, 0.0, None)
            self._db.execute(
                "INSERT OR REPLACE INTO relationships(other, affinity, trust, familiarity, note, ts) "
                "VALUES(?,?,?,?,?,?)",
                (other,
                 max(-100.0, min(100.0, aff + d_affinity)),
                 max(0.0, min(100.0, tru + d_trust)),
                 max(0.0, min(100.0, fam + d_familiarity)),
                 note if note is not None else old_note,
                 time.time()),
            )
            self._db.commit()

    def rel_all(self) -> list:
        """(other, affinity, trust, familiarity, note), most familiar first."""
        with self._lock:
            return self._db.execute(
                "SELECT other, affinity, trust, familiarity, note FROM relationships "
                "ORDER BY familiarity DESC"
            ).fetchall()

    # ------------------------------------------------------------ misc state

    def state_get(self, key: str, default: str = None) -> str:
        with self._lock:
            row = self._db.execute(
                "SELECT value FROM state WHERE key=?", (key,)).fetchone()
        return row[0] if row else default

    def state_set(self, key: str, value: str) -> None:
        with self._lock:
            self._db.execute(
                "INSERT OR REPLACE INTO state(key, value) VALUES(?,?)", (key, value))
            self._db.commit()

    # ------------------------------------------------------------ known tech

    def techs_all(self) -> list:
        with self._lock:
            return [r[0] for r in self._db.execute("SELECT tech FROM techs")]

    def tech_add(self, tech: str, source: str = None) -> bool:
        """Returns True if this was new knowledge."""
        with self._lock:
            cur = self._db.execute(
                "INSERT OR IGNORE INTO techs(tech, source, ts) VALUES(?,?,?)",
                (tech, source, time.time()),
            )
            self._db.commit()
            return cur.rowcount > 0

    # ------------------------------------------------------------ skill library
    # Voyager-style: named, reusable macro-routines composed from primitive
    # actions. Persistent like techs, teachable like techs.

    def skills_all(self) -> list:
        """[(name, description, steps:list, source, uses)] oldest-first."""
        import json as _json
        with self._lock:
            rows = self._db.execute(
                "SELECT name, description, steps_json, source, uses "
                "FROM skills ORDER BY ts").fetchall()
        return [(r[0], r[1] or "", _json.loads(r[2]), r[3] or "", int(r[4]))
                for r in rows]

    def skill_add(self, name: str, description: str, steps: list,
                  source: str = None) -> bool:
        """Returns True if the routine was new."""
        import json as _json
        with self._lock:
            cur = self._db.execute(
                "INSERT OR IGNORE INTO skills(name, description, steps_json, "
                "source, ts) VALUES(?,?,?,?,?)",
                (name, description, _json.dumps(steps), source, time.time()),
            )
            self._db.commit()
            return cur.rowcount > 0

    def skill_bump_use(self, name: str) -> None:
        with self._lock:
            self._db.execute(
                "UPDATE skills SET uses = uses + 1 WHERE name = ?", (name,))
            self._db.commit()
