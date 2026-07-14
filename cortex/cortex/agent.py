"""One Agent per NPC: persona + memory + known tech + relationships + bound LLM.

P1: chat and decide (wander/idle/say).
P2: needs/inventory-aware decide with gather/craft/eat gated by known tech.
P3: - memories carry embeddings; retrieval folds in cosine relevance
    - periodic reflection compresses recent memories into beliefs
    - relationships (affinity/trust/familiarity) persist and color prompts
    - known_tech lives in the database (seeded from the persona once) and
      grows by teaching: converse_turn() powers NPC-to-NPC dialogue
    - decide() has a "scripted" tier that skips the LLM entirely — the
      cheap tier for distant NPCs
"""

import json
import random
import re
import time

ACTIONS = ("wander", "idle", "say", "gather", "craft", "eat", "talk", "rest",
           "deposit", "withdraw", "skill", "raid", "read", "bury")

SKILL_STEP_ACTIONS = ("gather", "craft", "eat", "deposit", "withdraw")
SKILL_RATE = 0.15   # chance per idle full-tier decide to reflect on a routine
SKILL_CAP = 8       # routines one head can hold

REFLECT_THRESHOLD = 30.0   # summed importance before a reflection pass
TALK_COOLDOWN = 45.0       # how often the suggestion offers a chat
DISCOVERY_RATE = 0.20      # base insight chance per idle decide, scaled by O trait


class Agent:
    def __init__(self, name: str, persona: dict, llm, memory, world=None,
                 embedder=None, flavor: str = "vanilla"):
        self.name = name
        self.persona = persona or {}
        self.llm = llm
        self.memory = memory
        self.world = world
        self.embedder = embedder
        # "vanilla": guided prompts, scripted suggestion anchor, focused discovery.
        # "emergent": bare facts only — no advice, no anchor, uniform curiosity.
        self.flavor = flavor
        self._imp_since_reflect = 0.0
        self._last_talk_ts = 0.0
        self.discovery_rate = DISCOVERY_RATE
        self.dead = memory.state_get("dead") == "1"
        try:
            self.mood = json.loads(memory.state_get("mood") or "{}")
        except ValueError:
            self.mood = {}

        # knowledge lives in the DB; the persona only seeds a newborn mind
        known = set(memory.techs_all())
        if not known:
            for tech in self.persona.get("known_tech", []):
                memory.tech_add(tech, "upbringing")
            known = set(memory.techs_all())
        self.known_tech = sorted(known)

    # ---------------------------------------------------------- memory

    async def remember(self, kind: str, text: str, importance: float = 3.0) -> None:
        emb = await self.embedder.embed(text) if self.embedder else None
        self.memory.add(kind, text, importance, embedding=emb)
        self._imp_since_reflect += importance
        if self._imp_since_reflect >= REFLECT_THRESHOLD:
            self._imp_since_reflect = 0.0
            await self.reflect()

    async def reflect(self) -> list:
        """Compress recent memories into 2-3 beliefs (stored, high importance)."""
        rows = self.memory.recent(limit=25)
        if len(rows) < 5:
            return []
        stream = "\n".join(f"- ({kind}) {text}" for _, kind, text, _ in rows)
        system = (
            self.persona_block()
            + "\n\nYour recent memories:\n" + stream
            + "\n\nDistill what these mean. Respond ONLY with JSON, exactly:\n"
            '{"beliefs": ["2-3 short first-person conclusions about your life, '
            'the people around you, or what you should do next"]}'
        )
        raw = await self.llm.chat(
            [{"role": "system", "content": system},
             {"role": "user", "content": "Distill now."}],
            json_mode=True,
        )
        data = _extract_json(raw) or {}
        beliefs = [str(b)[:200] for b in data.get("beliefs", [])][:3]
        for b in beliefs:
            emb = await self.embedder.embed(b) if self.embedder else None
            self.memory.add("belief", b, 7, embedding=emb)
        return beliefs

    async def _memories_block(self, query: str) -> str:
        emb = await self.embedder.embed(query) if self.embedder else None
        mems = self.memory.retrieve(query, k=6, query_emb=emb)
        if not mems:
            return "None yet."
        return "\n".join(f"- ({kind}) {text}" for _, kind, text in mems)

    # ---------------------------------------------------------- knowledge

    def learn_tech(self, tech: str, source: str) -> bool:
        new = self.memory.tech_add(tech, source)
        if new:
            self.known_tech = sorted(set(self.known_tech) | {tech})
        return new

    # ---------------------------------------------------------- mood

    def feel(self, delta_valence: float, emotion: str, cause: str) -> None:
        """OCC-lite appraisal: events move valence and tag an emotion.
        The strongest recent feeling wins the mood line."""
        current = self._mood_now()
        valence = max(-50.0, min(50.0, current + delta_valence))
        # small nudges blend into the existing feeling; substantive events
        # (a death, a birth) always take over the emotion tag
        keep_old = abs(delta_valence) < 10.0 and self.mood.get("emotion")
        self.mood = {
            "valence": valence,
            "emotion": self.mood.get("emotion") if keep_old else emotion,
            "cause": self.mood.get("cause") if keep_old else cause,
            "ts": time.time(),
        }
        self.memory.state_set("mood", json.dumps(self.mood))

    def _mood_now(self) -> float:
        """Valence with time decay — grief lingers longer in sensitive souls
        (E trait), per the personality doc's decay modulators."""
        v = float(self.mood.get("valence", 0.0))
        if v == 0.0:
            return 0.0
        halflife = 900.0
        if v < 0 and float(self.persona.get("traits", {}).get("E", 50)) >= 60:
            halflife = 1800.0
        dt = time.time() - float(self.mood.get("ts", 0.0))
        return v * (0.5 ** (dt / halflife))

    def _mood_line(self) -> str:
        v = self._mood_now()
        emotion = str(self.mood.get("emotion", ""))
        cause = str(self.mood.get("cause", ""))
        if abs(v) < 8.0 or not emotion:
            return ""
        strength = "deeply " if abs(v) >= 30 else ""
        return f"\nMood: you are {strength}{emotion}" + (f" — {cause}." if cause else ".")

    def teach_willing(self) -> bool:
        """(A + community-mindedness)/2 >= 50, per the behavior-hook sketch."""
        a_score = float(self.persona.get("traits", {}).get("A", 60))
        values = self.persona.get("values", []) or []
        bonus = 40.0 if ("community" in values or "knowledge" in values) else 20.0
        return (a_score + bonus) / 2.0 >= 40.0

    def discoverable(self) -> list:
        """The knowledge frontier: unknown techs whose prerequisites this NPC
        already knows, capped at one era beyond the settlement's current era."""
        if not self.world:
            return []
        known = set(self.known_tech)
        max_era = min(getattr(self.world, "max_era", 8),
                      getattr(self.world, "settlement_era", 1) + 1)
        out = []
        for tid, node in self.world.nodes.items():
            if tid in known or int(node["era"][1:]) > max_era:
                continue
            pre = node.get("prerequisites", [])
            anyof = node.get("prerequisites_any_of", [])
            if all(p in known for p in pre) \
                    and all(any(x in known for x in g) for g in anyof):
                out.append(tid)
        return sorted(out)

    def _roll_discovery(self, tier: str):
        """The experiment_chance hook: O-modulated insight on an idle moment."""
        o_score = float(self.persona.get("traits", {}).get("O", 50))
        rate = self.discovery_rate * o_score / 100.0
        if tier == "scripted":
            rate *= 0.5
        if random.random() >= rate:
            return None
        frontier = self.discoverable()
        if not frontier:
            return None
        if self.flavor == "emergent":
            # pure undirected experimentation — no narrative pull at all
            return random.choice(frontier)
        # necessity focuses the mind: the settlement's next era gates (and
        # everything on the path to them) draw most of the experimenting
        focus = set()
        for gate in self.world.next_gates():
            if gate not in self.known_tech:
                focus.add(gate)
                focus |= self.world.prereq_closure(gate)
        on_path = [t for t in frontier if t in focus]
        if on_path and random.random() < 0.75:
            return random.choice(on_path)
        # otherwise curiosity pulls toward the newest ideas: usually pick from
        # the highest era available on the frontier
        top_era = max(t[:2] for t in frontier)
        top = [t for t in frontier if t.startswith(top_era)]
        return random.choice(top if random.random() < 0.7 else frontier)

    # ---------------------------------------------------------- prompts

    def persona_block(self) -> str:
        p = self.persona
        traits = ", ".join(p.get("personality", [])) or "plain, steady"
        goals = "; ".join(p.get("goals", [])) or "get through the day"
        values = ""
        if p.get("values_prose"):
            values = "You hold dear: " + "; ".join(p["values_prose"]) + ".\n"
        return (
            f"You are {p.get('name', self.name)} — {p.get('role', 'a villager')}, "
            f"living in the {p.get('era', 'Stone Age')}.\n"
            f"Personality: {traits}.\n"
            + values +
            f"Background: {str(p.get('background', '')).strip()}\n"
            f"Current aims: {goals}.\n"
            f"Speech style: {p.get('speech_style', 'plain, short sentences')}."
            + self._mood_line() + "\n"
            "Hard rules: always stay in character. You know NOTHING beyond your era "
            "(no metal, no writing, no machines, no modern words). "
            "Reply in 1-3 short sentences."
        )

    def _relations_block(self) -> str:
        rows = self.memory.rel_all()[:4]
        if not rows:
            return ""
        lines = []
        for other, aff, _trust, fam, note in rows:
            feel = "a friend" if aff >= 20 else ("someone you avoid" if aff <= -20
                                                 else "an acquaintance")
            depth = "well known to you" if fam >= 40 else (
                "familiar" if fam >= 10 else "barely known")
            entry = f"- {other.capitalize()}: {feel}, {depth}"
            if note:
                entry += f" ({note})"
            lines.append(entry)
        return "\n\nPeople in your life:\n" + "\n".join(lines)

    def _convo_block(self) -> str:
        rows = self.memory.recent(kinds=("chat_visitor", "chat_self"), limit=10)
        if not rows:
            return "This is your first talk with the visitor."
        lines = []
        for _, kind, text, _imp in rows:
            who = "Visitor" if kind == "chat_visitor" else "You"
            lines.append(f"{who}: {text}")
        return "\n".join(lines)

    def _state_block(self, state: dict) -> str:
        needs = state.get("needs", {})
        inv = state.get("inventory", {})
        bare = self.flavor == "emergent"
        lines = []
        if state.get("time_of_day") == "night":
            lines.append("It is night." if bare
                          else "It is NIGHT — dark and cold away from the fire.")
        if state.get("season") == "winter":
            lines.append("It is winter." if bare
                          else "It is WINTER — the bushes are bare and nothing regrows.")
        if state.get("cold"):
            lines.append("You are cold.")
        if needs:
            hunger = needs.get("hunger")
            energy = needs.get("energy")
            health = needs.get("health")
            parts = []
            if hunger is not None:
                parts.append(f"hunger {int(hunger)}/100"
                             + ("" if bare or hunger < 60 else " (you need food soon)"))
            if energy is not None:
                parts.append(f"energy {int(energy)}/100"
                             + ("" if bare or energy > 25 else " (you are tired)"))
            if health is not None and health < 70:
                parts.append(f"health {int(health)}/100"
                             + ("" if bare else " (you are weakening)"))
            lines.append("Your body: " + ", ".join(parts) + ".")
        fire = state.get("fire")
        if fire:
            if not fire.get("lit", True):
                lines.append("The fire is out." if bare
                              else "The band's fire has gone COLD.")
            elif float(fire.get("fuel", 100)) <= 35:
                lines.append(f"The fire is small ({int(fire.get('fuel', 0))}/100)." if bare
                              else "The band's fire is burning low — it needs wood.")
        carried = ", ".join(f"{n} {item}" for item, n in inv.items() if int(n) > 0)
        lines.append("You carry: " + (carried if carried else "nothing") + ".")
        return "\n".join(lines)

    def _catalog_block(self, catalog: dict) -> str:
        lines = []
        if catalog.get("gather"):
            lines.append("GATHER (walk there and collect):")
            for g in catalog["gather"]:
                lines.append(f'- target "{g["target"]}" — {g["label"]}, '
                             f'yields {g["yields"]}, {g["distance"]} steps away')
        if catalog.get("craft"):
            lines.append("CRAFT (skills you know):")
            for c in catalog["craft"]:
                if c["ready"]:
                    status = "you have everything"
                else:
                    status = "still needs " + ", ".join(
                        f"{v} {k}" for k, v in c["missing"].items())
                if c.get("station") == "campfire":
                    status += ", done at the fire"
                elif c.get("station"):
                    status += ", done at the %s" % c["station"]
                lines.append(f'- target "{c["target"]}" — {c["label"]} ({status})')
        if catalog.get("eat"):
            lines.append("EAT (from what you carry):")
            for e in catalog["eat"]:
                lines.append(f'- target "{e["target"]}" — {e["label"]}')
        store = catalog.get("store") or {}
        if store:
            held = ", ".join(f"{n} {self.world.items.get(it, {}).get('label', it)}"
                             for it, n in store.get("holds", {}).items()
                             if int(n) > 0) or "nothing"
            lines.append(f"STORE (the {store.get('kind', 'store')}, "
                         f"{store.get('distance', 0)} steps away, holds {held}, "
                         f"space for {store.get('space', 0)} more):")
            for it in store.get("deposit", []):
                lines.append(f'- deposit target "{it}" — put your '
                             f'{self.world.items.get(it, {}).get("label", it)} in')
            for it in store.get("withdraw", []):
                lines.append(f'- withdraw target "{it}" — take '
                             f'{self.world.items.get(it, {}).get("label", it)} out')
        fields = catalog.get("fields") or {}
        if fields.get("plots"):
            lines.append(
                f"FIELDS ({fields['plots']} plot(s): {fields.get('empty', 0)} bare, "
                f"{fields.get('growing', 0)} growing, {fields.get('ripe', 0)} ripe "
                "— sow_field and harvest_field appear under CRAFT when possible)")
        if catalog.get("books"):
            lines.append("BOOKS you carry but have not read:")
            for b in catalog["books"]:
                lines.append(f'- read target "{b}" — the book of '
                             f"{self.world.tech_name(b[5:]).lower()}")
        foreign = catalog.get("foreign_store") or {}
        if foreign.get("holds"):
            lines.append(
                f"ANOTHER VILLAGE'S {str(foreign.get('kind', 'store'))} stands "
                f"{foreign.get('distance', 0)} steps away — taking from it "
                "would be a RAID: they will fight back, be hurt, and remember "
                "you for it. It holds:")
            for it, n in foreign["holds"].items():
                if int(n) > 0:
                    lines.append(f'- raid target "{it}" — {n} '
                                 f"{self.world.items.get(it, {}).get('label', it)}")
        corpse = catalog.get("corpse") or {}
        if corpse.get("name"):
            who = str(corpse["name"]).capitalize()
            if "E2.24" in self.known_tech:
                lines.append(
                    f"THE DEAD: the body of {who} lies unburied "
                    f"{corpse.get('distance', 0)} steps away — "
                    f'bury (no target) digs a grave and lays them to rest.')
            else:
                lines.append(
                    f"THE DEAD: the body of {who} lies where they fell, "
                    f"{corpse.get('distance', 0)} steps away. You do not know "
                    "any rite for the dead.")
        corral = catalog.get("corral") or {}
        if corral.get("herd") is not None:
            herd = ", ".join(f"{n} {k}(s)" for k, n in corral["herd"].items()
                             if int(n) > 0) or "nothing yet"
            lines.append(f"CORRAL ({corral.get('distance', 0)} steps away, "
                         f"holds {herd}, room for {corral.get('space', 0)} more "
                         "— penning, milking, wool and slaughter appear under "
                         "CRAFT when possible)")
        if catalog.get("talk"):
            lines.append("TALK (walk over and speak with someone):")
            for t in catalog["talk"]:
                lines.append(f'- target "{t["target"]}" — {t["label"]}, '
                             f'{t["distance"]} steps away')
        skills = self.memory.skills_all()
        if skills:
            lines.append("YOUR ROUTINES (practiced habits — one \"skill\" "
                         "action runs every step in order):")
            for name, desc, steps, _src, uses in skills:
                chain = " → ".join(
                    f"{s['action']} {s.get('target', '')}".strip() for s in steps)
                lines.append(f'- skill target "{name}" — {desc} ({chain})')
        return "\n".join(lines) if lines else \
            "Nothing useful nearby; you can wander, idle or speak."

    def _build_catalog(self, state: dict) -> dict:
        catalog = (self.world.action_catalog(
            self.known_tech, state.get("inventory"), state.get("nearby"),
            fire=state.get("fire"), storage=state.get("storage"),
            fields=state.get("fields"), corral=state.get("corral"),
            stations=state.get("stations"), oxen=int(state.get("oxen", 0)))
            if self.world else {"gather": [], "craft": [], "eat": [], "store": {}})
        catalog["fields"] = state.get("fields") or {}
        catalog["corral"] = state.get("corral") or {}
        catalog["foreign_store"] = state.get("foreign_store") or {}
        catalog["corpse"] = state.get("corpse") or {}
        catalog["books"] = [
            it for it, n in (state.get("inventory") or {}).items()
            if int(n) > 0 and it.startswith("book_")
            and it[5:] not in self.known_tech and self.world
            and it[5:] in self.world.nodes]
        talk = []
        for other, dist in sorted((state.get("nearby_npcs") or {}).items(),
                                  key=lambda kv: kv[1]):
            talk.append({"target": other, "label": other.capitalize(),
                         "distance": round(float(dist), 1)})
        catalog["talk"] = talk
        return catalog

    # ---------------------------------------------------------- loops

    async def chat(self, text: str, state: dict = None) -> str:
        convo = self._convo_block()
        await self.remember("chat_visitor", text, 5)
        system = (
            self.persona_block()
            + self._relations_block()
            + ("\n\n" + self._state_block(state) if state else "")
            + "\n\nThings you remember:\n" + await self._memories_block(text)
            + "\n\nConversation so far:\n" + convo
            + "\n\nA visitor from beyond your world is speaking with you."
        )
        reply = await self.llm.chat(
            [
                {"role": "system", "content": system},
                {"role": "user", "content": text},
            ]
        )
        reply = reply.strip()
        await self.remember("chat_self", reply, 4)
        return reply

    async def decide(self, state: dict, tier: str = "full") -> dict:
        catalog = self._build_catalog(state)
        suggestion = self._suggest(state, catalog)
        # an idle mind wanders — and staring into the fire breeds ideas
        if (tier != "scripted"
                and suggestion["action"] in ("wander", "idle", "rest")
                and random.random() < getattr(self, "skill_rate", SKILL_RATE)):
            skill = await self._compose_skill()
            if skill:
                return {"action": "idle", "target": "",
                        "say": f"I keep doing this the same way... I shall call "
                               f"it {skill['name'].replace('_', ' ')}.",
                        "skill_learned": {"npc": self.name, **skill}}
        if suggestion["action"] in ("wander", "idle", "rest"):
            tech = self._roll_discovery(tier)
            if tech and self.learn_tech(tech, "insight"):
                name = self.world.tech_name(tech)
                await self.remember(
                    "discovery", f"worked out {name.lower()} all by myself", 8)
                self.feel(15, "proud and excited", f"discovered {name.lower()}")
                return {"action": "experiment", "target": tech,
                        "say": f"Wait — if I do it this way... {name.lower()}! "
                               "That is how it is done!",
                        "learned": {"npc": self.name, "tech": tech,
                                    "tech_name": name, "from": "insight"}}
        if suggestion["action"] == "read":
            # reading learns regardless of tier — the book does the teaching
            done = self._do_read(str(suggestion.get("target", "")))
            if done:
                await self.remember(
                    "discovery", f"read {done['learned']['tech_name']} out of "
                    "a printed book", 7)
                return done
            suggestion = {"action": "idle", "target": "", "say": ""}
        if tier == "scripted":
            # cheap tier: no LLM call, the scripted suggestion IS the decision
            self.memory.add("decision", f"(scripted) chose to {suggestion['action']} "
                            + str(suggestion.get("target", "")), 0.5)
            return suggestion
        if self.flavor == "emergent":
            # bare facts, no advice, no anchor: the mind is on its own
            guidance = (
                "\n\nChoose your next action.\n"
                'Respond ONLY with JSON, exactly: {"action": "wander" | "idle" | "say" | '
                '"gather" | "craft" | "eat" | "talk" | "rest" | "deposit" | "withdraw" | '
                '"skill" | "raid" | "read" | "bury", "target": "<id from the lists above, or empty>", '
                '"say": "words you speak aloud, or empty"}'
            )
        else:
            guidance = (
                "\n\nChoose your next action. Talking with the others matters as much as "
                "work — stories, news and skills move at the fire and in passing; a band "
                "that does not talk falls apart. Eat when hunger is high; keep the fire "
                "fed; at night, rest by the fire. You may choose a craft that is missing "
                "materials — you will gather what is needed on the way. Add a short "
                "spoken line (\"say\") whenever you have something on your mind.\n"
                'Respond ONLY with JSON, exactly: {"action": "wander" | "idle" | "say" | '
                '"gather" | "craft" | "eat" | "talk" | "rest" | "deposit" | "withdraw" | '
                '"skill" | "raid" | "read" | "bury", "target": "<id from the lists above, or empty>", '
                '"say": "one short in-character line, or empty"}\n'
                "If unsure, choose SUGGESTED_ACTION: " + json.dumps(suggestion)
            )
        plan_block = ("\n\nTHE DAWN COUNCIL AGREED: " + self.plan
                      if getattr(self, "plan", "") else "")
        system = (
            self.persona_block()
            + self._relations_block()
            + "\n\n" + self._state_block(state)
            + plan_block
            + "\n\nThings you remember:\n"
            + await self._memories_block("plan day food tools work friends")
            + "\n\nWhat you can do right now:\n" + self._catalog_block(catalog)
            + guidance
        )
        raw = await self.llm.chat(
            [
                {"role": "system", "content": system},
                {"role": "user", "content": "Decide now."},
            ],
            json_mode=True,
        )
        data = _extract_json(raw) or {}
        fallback = suggestion if self.flavor != "emergent" \
            else {"action": "wander", "target": "", "say": ""}
        result = self._validate(data, catalog, fallback)
        note = f"chose to {result['action']}" \
            + (f" {result['target']}" if result["target"] else "") \
            + (f' and said "{result["say"]}"' if result["say"] else "")
        await self.remember("decision", note, 1)
        return result

    def _do_read(self, target: str):
        """Wave L: books teach whoever reads them — the mind learns here,
        the body just sits down with the pages for a while."""
        tech_id = target[5:] if target.startswith("book_") else ""
        if not self.world or tech_id not in self.world.nodes:
            return None
        self.learn_tech(tech_id, "a printed book")
        name = self.world.tech_name(tech_id)
        return {"action": "read", "target": target,
                "say": f"So THAT is how {name.lower()} is done...",
                "learned": {"npc": self.name, "tech": tech_id,
                            "tech_name": name, "from": "a book"}}

    # ---------------------------------------------------------- skill library
    # Voyager-style: an idle mind notices it keeps doing the same things and
    # names the habit. Routines are validated against what the agent actually
    # knows, stored like techs, executed by the body as one macro-action, and
    # taught to others at the fire.

    async def _compose_skill(self):
        skills = self.memory.skills_all()
        if len(skills) >= SKILL_CAP or not self.world:
            return None
        recent = self.memory.recent(kinds=["event", "decision"], limit=14)
        doings = "\n".join(f"- {r[2]}" for r in recent) or "- (nothing yet)"
        if len(recent) < 4:
            return None   # not enough lived experience to see a pattern
        recipes = ", ".join(sorted(self.world.known_recipes(self.known_tech)))
        known_names = ", ".join(s[0] for s in skills) or "(none yet)"
        system = (
            self.persona_block()
            + "\n\nYour recent doings:\n" + doings
            + "\n\nRecipes you know: " + (recipes or "(none)")
            + "\nRoutines you already have: " + known_names
            + "\n\nYou notice a pattern in your work. Compose ONE reusable "
            "routine that chains 2-5 of your usual steps into a repeatable "
            "habit (e.g. gather something, then craft or store something). "
            "Use only recipes you know and things you can actually do.\n"
            'Respond ONLY with JSON, exactly: {"name": "<short_snake_case>", '
            '"description": "<one line>", "steps": [{"action": "gather" | '
            '"craft" | "eat" | "deposit" | "withdraw", "target": "<id>"}]}'
        )
        raw = await self.llm.chat(
            [{"role": "system", "content": system},
             {"role": "user", "content": "Name the routine."}],
            json_mode=True,
        )
        skill = self._valid_skill(_extract_json(raw) or {})
        if not skill:
            return None
        if not self.memory.skill_add(skill["name"], skill["description"],
                                     skill["steps"], "composed"):
            return None   # already had that one
        await self.remember(
            "skill", f"worked out a routine of my own: {skill['name']} — "
            f"{skill['description']}", 7)
        self.feel(10, "satisfied", f"my own way of doing things: {skill['name']}")
        return skill

    def _valid_skill(self, data: dict):
        """Normalize + verify a proposed routine against real capabilities."""
        name = re.sub(r"[^a-z0-9_]", "", str(data.get("name", "")).lower()
                      .replace(" ", "_").replace("-", "_"))[:32]
        desc = str(data.get("description", ""))[:120]
        steps_in = data.get("steps")
        if len(name) < 3 or not isinstance(steps_in, list):
            return None
        recipes = self.world.known_recipes(self.known_tech)
        steps = []
        for s in steps_in[:5]:
            if not isinstance(s, dict):
                return None
            action = str(s.get("action", ""))
            target = str(s.get("target", ""))
            if action not in SKILL_STEP_ACTIONS:
                return None
            if action == "craft" and target not in recipes:
                return None
            if action == "gather":
                r = self.world.resources.get(target)
                if not r or (r.get("tech") and r["tech"] not in self.known_tech):
                    return None
            if action == "eat" and not self.world.is_food(target):
                return None
            if action in ("deposit", "withdraw") and target not in self.world.items:
                return None
            steps.append({"action": action, "target": target})
        if len(steps) < 2:
            return None
        return {"name": name, "description": desc, "steps": steps}

    # ---------------------------------------------------------- dawn council

    async def council_line(self, report: dict) -> str:
        """One spoken line at the dawn assembly: yesterday, and what should
        happen today."""
        recent = self.memory.recent(kinds=["event", "decision", "social"],
                                    limit=8)
        doings = "\n".join(f"- {r[2]}" for r in recent) or "- (a quiet day)"
        system = (
            self.persona_block()
            + "\n\nYour recent doings:\n" + doings
            + f"\n\nIt is dawn of day {report.get('day', '?')} "
            f"({report.get('season', '?')}). The village stands at the dawn "
            "council: everyone reports their day and speaks for the day ahead. "
            f"The village: {report.get('alive', '?')} present, fire at "
            f"{report.get('fire_pct', '?')}%, {report.get('food_in_stores', 0)} "
            "food in the stores.\n\nSay your piece: 1-2 short sentences — what "
            "you did, and what you think the village should do today."
        )
        line = await self.llm.chat(
            [{"role": "system", "content": system},
             {"role": "user", "content": "Speak at the dawn council."}])
        return line.strip()[:240]

    async def council_plan(self, report: dict, transcript: list) -> str:
        """The eldest voice sums the council into one plan for the day."""
        said = "\n".join(f"{who.capitalize()}: {line}" for who, line in transcript)
        system = (
            self.persona_block()
            + "\n\nThe dawn council has spoken:\n" + said
            + f"\n\nThe village: fire at {report.get('fire_pct', '?')}%, "
            f"{report.get('food_in_stores', 0)} food stored, season "
            f"{report.get('season', '?')}.\n\nAgree the plan: sum the council "
            "into ONE plan for today, 1-2 short sentences, concrete "
            "(what to gather, build, tend or watch for)."
        )
        plan = await self.llm.chat(
            [{"role": "system", "content": system},
             {"role": "user", "content": "Agree the plan."}])
        return plan.strip()[:240]

    async def converse_turn(self, other_name: str, history: list) -> str:
        """One line of NPC-to-NPC dialogue. history = [(speaker_name, line), ...]"""
        self._last_talk_ts = time.time()
        so_far = "\n".join(f"{who.capitalize()}: {line}" for who, line in history) \
            or "(you speak first)"
        system = (
            self.persona_block()
            + self._relations_block()
            + "\n\nThings you remember:\n" + await self._memories_block(other_name)
            + f"\n\nYou are talking with {other_name.capitalize()}, "
            "another person of your band.\nConversation so far:\n" + so_far
            + "\n\nSay your next line: 1-2 short sentences, in character, "
            "about your day, your work, food, the band, or what you know."
        )
        line = await self.llm.chat(
            [{"role": "system", "content": system},
             {"role": "user", "content": "Speak."}]
        )
        return line.strip()[:240]

    # ---------------------------------------------------------- validation

    def _validate(self, data: dict, catalog: dict, suggestion: dict) -> dict:
        action = data.get("action")
        target = str(data.get("target") or "")
        say = str(data.get("say") or "")[:200]
        ok = False
        if action in ("wander", "idle", "rest"):
            ok = True
            target = ""
        elif action == "say":
            ok = bool(say)
        elif action == "gather":
            ok = target in {g["target"] for g in catalog.get("gather", [])}
        elif action == "craft":
            ok = target in {c["target"] for c in catalog.get("craft", [])}
            if ok and target == "write_book":
                # the author sets their most advanced knowledge in print
                best = max(self.known_tech, default="",
                           key=lambda t: (int(t.split(".")[0][1:]),
                                          int(t.split(".")[1])))
                if not best:
                    ok = False
                else:
                    return {"action": "craft", "target": target, "say": say,
                            "book_tech": best}
        elif action == "eat":
            ok = target in {e["target"] for e in catalog.get("eat", [])}
        elif action == "talk":
            ok = target in {t["target"] for t in catalog.get("talk", [])}
        elif action == "deposit":
            ok = target in (catalog.get("store") or {}).get("deposit", [])
        elif action == "withdraw":
            ok = target in (catalog.get("store") or {}).get("withdraw", [])
        elif action == "raid":
            # Wave H: conflict is MIND-driven only — this branch is the sole
            # gate; no suggestion or fallback ever proposes a raid
            ok = target in (catalog.get("foreign_store") or {}).get("holds", {})
        elif action == "bury":
            # a body must be lying out AND the rite must be known (E2.24)
            ok = (bool((catalog.get("corpse") or {}).get("name"))
                  and "E2.24" in self.known_tech)
            target = ""
        elif action == "read":
            if target in (catalog.get("books") or []):
                result = self._do_read(target)
                if result:
                    result["say"] = say or result["say"]
                    return result
        elif action == "skill":
            for name, _desc, steps, _src, _uses in self.memory.skills_all():
                if name == target:
                    self.memory.skill_bump_use(name)
                    # the body executes the whole routine as one macro-action
                    return {"action": "skill", "target": target, "say": say,
                            "steps": steps}
        if not ok:
            return {**suggestion, "say": say or suggestion.get("say", "")}
        return {"action": action, "target": target, "say": say}

    def _suggest(self, state: dict, catalog: dict) -> dict:
        """Scripted-tier fallback: sensible next action without any LLM.
        This is the survival instinct that keeps the village alive unattended."""
        needs = state.get("needs", {})
        inv = state.get("inventory", {}) or {}
        hunger = float(needs.get("hunger", 0))
        energy = float(needs.get("energy", 100))
        night = state.get("time_of_day") == "night"
        fire = state.get("fire") or {}
        gather_targets = {g["target"] for g in catalog.get("gather", [])}
        craft_by_id = {c["target"]: c for c in catalog.get("craft", [])}

        def craft_or_fetch(rid, depth=2):
            c = craft_by_id.get(rid)
            if not c:
                return None
            if c["ready"]:
                return {"action": "craft", "target": rid, "say": ""}
            for item in c["missing"]:
                rtype = self.world.resource_yielding(item) if self.world else None
                if rtype and rtype in gather_targets:
                    return {"action": "gather", "target": rtype, "say": ""}
                if depth > 0 and self.world:
                    # the missing piece is itself craftable (digging stick,
                    # stone flake...) — chase the tool chain
                    for rid2, r2 in self.world.recipes.items():
                        if item in r2.get("outputs", {}) and rid2 in craft_by_id:
                            pick = craft_or_fetch(rid2, depth - 1)
                            if pick:
                                return pick
            return None

        store = catalog.get("store") or {}
        # 0. hurt: a poultice in the pouch is used before anything else
        health = float(needs.get("health", 100))
        if health < 50 and int(inv.get("poultice", 0)) > 0:
            return {"action": "eat", "target": "poultice", "say": ""}
        # 1. starving: eat what you carry, raid the larder, milk or slaughter
        #    from the herd, cook, then find food
        if hunger >= 60:
            if catalog.get("eat"):
                return {"action": "eat", "target": catalog["eat"][0]["target"], "say": ""}
            if store.get("withdraw"):
                return {"action": "withdraw", "target": store["withdraw"][0], "say": ""}
            for rid in ("milk_cattle", "milk_goats",
                        "slaughter_pig", "slaughter_goat", "slaughter_cattle"):
                if rid in craft_by_id:
                    return {"action": "craft", "target": rid, "say": ""}
            for rid in ("cook_meat", "roast_tubers", "dig_tubers"):
                pick = craft_or_fetch(rid)
                if pick and (pick["action"] == "craft"
                             or hunger >= 80):  # only chase ingredients when desperate
                    return pick
            for rtype in ("berry_bush", "small_game"):
                if rtype in gather_targets:
                    return {"action": "gather", "target": rtype, "say": ""}
        # 2. the fire must not die: tenders keep it fed
        if fire and float(fire.get("fuel", 100)) <= 35:
            pick = craft_or_fetch("tend_fire")
            if pick:
                return pick
        # 3. night: rest by the fire
        if night:
            return {"action": "rest", "target": "", "say": ""}
        # 3a00. the dead are seen to before any day-work — if the rite is known
        if (catalog.get("corpse") or {}).get("name") and "E2.24" in self.known_tech:
            return {"action": "bury", "target": "", "say": ""}
        # 3a0. an unread book in the pouch is knowledge waiting: read it
        if catalog.get("books"):
            return {"action": "read", "target": catalog["books"][0], "say": ""}
        # 3a. native copper collecting (E6.01): the green stones are worth
        #     picking up long before anyone knows why — carrying one to a lit
        #     fire is how smelting gets stumbled upon (the opportunity event).
        #     One-shot per pouch, so it never crowds out real work.
        if ("E6.01" in self.known_tech and "copper_vein" in gather_targets
                and int(inv.get("copper_ore", 0)) == 0):
            return {"action": "gather", "target": "copper_vein", "say": ""}
        # 3b. shelter the band: builders raise huts until ~1 per 6 people
        #     (mudbrick houses, once known, beat brush huts)
        huts = int(state.get("huts", 0))
        population = int(state.get("population", 0))
        if population and huts * 6 < population:
            for rid in ("build_mud_house", "build_hut"):
                pick = craft_or_fetch(rid)
                if pick:
                    return pick
        # 3c. the band needs somewhere to keep food: dig a cache, raise a granary
        if not state.get("storage"):
            for rid in ("build_granary", "dig_cache"):
                pick = craft_or_fetch(rid)
                if pick:
                    return pick
        # 4. stock the larder a little before playing
        if hunger >= 35 and not catalog.get("eat"):
            for rtype in ("berry_bush", "small_game"):
                if rtype in gather_targets:
                    return {"action": "gather", "target": rtype, "say": ""}
        # 4b. surplus goes into the store — the village commons
        if hunger < 45 and store.get("deposit"):
            heaviest = max(store["deposit"], key=lambda it: int(inv.get(it, 0)))
            if int(inv.get(heaviest, 0)) >= 3:
                return {"action": "deposit", "target": heaviest, "say": ""}
        # 4c. the farming year: cut what is ripe, sow what is bare, break new
        #     ground while the plots are few (all no-ops for pre-farming minds)
        fields = state.get("fields") or {}
        if int(fields.get("ripe", 0)) > 0:
            pick = craft_or_fetch("harvest_field")
            if pick:
                return pick
        if int(fields.get("empty", 0)) > 0:
            pick = craft_or_fetch("sow_field")
            if pick:
                return pick
        if ("till_plot" in craft_by_id
                and int(fields.get("plots", 0)) < 1 + population // 10):
            pick = craft_or_fetch("till_plot")
            if pick:
                return pick
        # 4d. the herd: pen what you caught, catch when there is room, then
        #     live off the animals (milk, wool) instead of the hunt
        corral = state.get("corral") or {}
        if corral:
            for rid in ("pen_goat", "pen_sheep", "pen_cattle", "pen_pig"):
                c = craft_by_id.get(rid)
                if c and c["ready"]:
                    return {"action": "craft", "target": rid, "say": ""}
            if int(corral.get("space", 0)) > 0:
                for rtype in ("wild_goat", "wild_sheep", "wild_cattle",
                              "wild_pig"):
                    if rtype in gather_targets:
                        return {"action": "gather", "target": rtype, "say": ""}
            for rid in ("milk_cattle", "milk_goats"):
                if (rid in craft_by_id and hunger >= 25
                        and int(inv.get("milk", 0)) == 0):
                    return {"action": "craft", "target": rid, "say": ""}
            if "pluck_wool" in craft_by_id and int(inv.get("wool", 0)) < 2:
                return {"action": "craft", "target": "pluck_wool", "say": ""}
        elif "build_corral" in craft_by_id:
            pick = craft_or_fetch("build_corral")
            if pick:
                return pick
        # 4e. a dog for the village: wolves respect nothing else
        if int(state.get("dogs", 1)) == 0:
            pick = craft_or_fetch("tame_dog")
            if pick:
                return pick
        # 4f. infrastructure the village lacks: whoever knows how, builds it
        built = set(state.get("village") or []) | set(state.get("stations") or [])
        for rid, kind in (("build_smelter", "smelter"),
                          ("build_smoking_rack", "smoking_rack"),
                          ("build_kiln", "kiln"),
                          ("build_school", "school"),
                          ("build_watermill", "watermill"),
                          ("build_windmill", "windmill"),
                          ("build_screw_press", "screw_press"),
                          ("build_trip_hammer", "trip_hammer"),
                          ("build_bathhouse", "bathhouse"),
                          ("build_theater", "theater"),
                          ("build_ice_house", "ice_house"),
                          ("build_fountain", "fountain"),
                          ("build_stone_wall", "stone_wall"),
                          ("build_spinning_wheel", "spinning_wheel"),
                          ("build_blast_furnace", "blast_furnace"),
                          ("build_university", "university"),
                          ("build_hospital", "hospital"),
                          ("build_clock_tower", "clock_tower"),
                          ("build_print_shop", "print_shop"),
                          ("set_snares", "snare_line"),
                          ("set_fish_trap", "fish_trap"),
                          ("build_market_stall", "market_stall")):
            if rid in craft_by_id and kind not in built:
                pick = craft_or_fetch(rid)
                if pick:
                    return pick
        # 4g. a printer with paper sets knowledge down for the ages
        if ("write_book" in craft_by_id
                and sum(1 for it in inv if it.startswith("book_")) < 2):
            pick = craft_or_fetch("write_book")
            if pick:
                return pick
        # 5. keep the band close: chat when someone is near and it's been a while
        if catalog.get("talk") and time.time() - self._last_talk_ts > TALK_COOLDOWN:
            return {"action": "talk", "target": catalog["talk"][0]["target"], "say": ""}
        # 6. craft something new: prefer recipes whose outputs we don't own yet
        for c in catalog.get("craft", []):
            recipe = self.world.recipes.get(c["target"], {}) if self.world else {}
            outputs = recipe.get("outputs", {})
            if not outputs:
                continue  # effect recipes (tend_fire) are driven by rule 2, not novelty
            if all(int(inv.get(o, 0)) > 0 for o in outputs):
                continue
            pick = craft_or_fetch(c["target"])
            if pick:
                return pick
        if energy <= 25:
            return {"action": "rest" if fire else "idle", "target": "", "say": ""}
        return {"action": "wander", "target": "", "say": ""}


def _extract_json(raw: str):
    try:
        return json.loads(raw)
    except (ValueError, TypeError):
        pass
    m = re.search(r"\{.*\}", raw or "", re.S)
    if m:
        try:
            return json.loads(m.group(0))
        except ValueError:
            return None
    return None
