"""Persona compilation: trait scores -> natural-language personality lines.

Implements the prompt-rendering rules from 03_NPC_PERSONALITY.md / traits.json:
numbers never reach the prompt raw; each axis maps to descriptor bands,
mid-band traits are omitted, at most 4 distinctive traits are rendered
(most extreme first).
"""

BAND_EDGES = (15, 30, 69, 84)  # 0-15 | 16-30 | 31-69 (omitted) | 70-84 | 85-100
MAX_TRAITS = 4


def _band_key(score: int) -> str:
    if score <= 15:
        return "0-15"
    if score <= 30:
        return "16-30"
    if score <= 69:
        return "31-69"
    if score <= 84:
        return "70-84"
    return "85-100"


def render_traits(scores: dict, traits_data: dict) -> list:
    """{"O": 90, "C": 75, ...} -> up to MAX_TRAITS descriptor strings,
    most distinctive (furthest from 50) first. Mid-band scores are omitted."""
    axes = {a["key"]: a for a in traits_data.get("axes", [])}
    picked = []
    for key, score in scores.items():
        axis = axes.get(key)
        if not axis:
            continue
        desc = axis.get("descriptor_bands", {}).get(_band_key(int(score)))
        if desc:
            picked.append((abs(int(score) - 50), desc))
    picked.sort(key=lambda p: p[0], reverse=True)
    return [desc for _, desc in picked[:MAX_TRAITS]]


def render_values(value_keys: list, traits_data: dict) -> list:
    """["knowledge", "community"] -> human descriptions of what they hold dear."""
    catalog = {v["key"]: v for v in traits_data.get("values", [])}
    out = []
    for key in (value_keys or [])[:2]:
        v = catalog.get(key)
        if v:
            out.append(f"{v['name'].lower()} ({v['description']})")
    return out


NAME_POOL = [
    "arok", "besh", "chala", "dren", "eshu", "fenna", "gorm", "hela", "iwar",
    "jona", "kesh", "luma", "moss", "nera", "orin", "pyra", "quil", "rasha",
    "senn", "tavi", "ulma", "varn", "wena", "xolo", "yiri", "zek", "aldra",
    "borin", "cima", "durn",
    # generations to come
    "kaida", "lorn", "mira", "nuno", "osha", "pell", "qora", "ruven", "sifa",
    "tero", "una", "veda", "wyn", "xanti", "yara", "zoril", "amsel", "brona",
    "cai", "delu", "enda", "ferun", "gilda", "harn", "ilo", "jesra", "kovan",
    "leska", "mahel", "nial", "ondra", "peira", "quenn", "rolo", "sarn",
    "tilda", "ulf", "vanya", "wera", "yotam", "zana", "abren", "belka",
    "corin", "dashi", "elun", "farel", "goro", "hinta", "ivo", "jarel",
    "kama", "lundo", "meshi", "norun", "olba", "petra", "quim", "renna",
    "solin", "tamo", "urda", "velo", "wirt", "yeva", "zorn", "aiko", "bram",
    "cessa", "doran", "elin", "fost", "gwena", "holt", "isra", "jute",
    "kell", "lomi", "marek", "nessa", "ovin", "palo", "runa", "sedge",
    "torv", "ulla", "vint", "wren", "yorik", "zilla",
]

_SYL_A = ["ka", "ra", "mi", "to", "ne", "sha", "lu", "or", "an", "be",
          "dro", "fe", "gri", "ha", "is", "jo", "kel", "ma", "no", "pa"]
_SYL_B = ["ric", "wen", "dan", "mor", "lis", "ton", "var", "nia", "rek",
          "sel", "din", "lo", "ven", "tas", "rin", "gar", "nis", "bel",
          "run", "dal"]


def fresh_name(used) -> str:
    """A pronounceable name nobody alive or dead has carried — the pool
    first, then composed syllables. Never 'born49'."""
    for n in NAME_POOL:
        if n not in used:
            return n
    i = len(used)
    while True:
        cand = _SYL_A[i % len(_SYL_A)] + _SYL_B[(i // len(_SYL_A)) % len(_SYL_B)]
        if cand not in used:
            return cand
        i += 1

BASIC_TECH = ["E1.01", "E1.02", "E1.07"]
EXTRA_TECH_POOL = ["E1.04", "E1.05", "E1.08", "E1.09", "E1.10",
                   "E1.11", "E1.20", "E1.21"]


def generate_village(count: int, seed: int, traits_data: dict,
                     taken_names=None) -> dict:
    """Deterministically cast `count` extra villagers from the archetype deck:
    archetype traits + gaussian noise, a couple of random known techs on top of
    the basics. Returns {npc_id: persona_dict}. Personality prose is compiled
    later by compile_persona, like any hand-written persona."""
    import random
    rng = random.Random(seed)
    archetypes = traits_data.get("archetypes", []) or [{}]
    taken = set(taken_names or [])
    out = {}
    names = [n for n in NAME_POOL if n not in taken]
    for i in range(min(count, len(names))):
        name = names[i]
        arch = archetypes[i % len(archetypes)]
        traits = {}
        for key, base in (arch.get("traits", {}) or {"C": 50}).items():
            traits[key] = int(max(5, min(95, rng.gauss(base, 12))))
        # noise on one extra random axis so no two casts are identical
        extra_axis = rng.choice("HEXACODB")
        traits.setdefault(extra_axis, int(max(5, min(95, rng.gauss(50, 18)))))
        known = list(BASIC_TECH)
        known += rng.sample(EXTRA_TECH_POOL, k=rng.randint(1, 3))
        out[name] = {
            "name": name.capitalize(),
            "role": "a %s of the band" % arch.get("name", "villager").lower(),
            "era": "early Stone Age (Upper Paleolithic)",
            "traits": traits,
            "values": [arch.get("primary_value", "community")],
            "speech_style": "plain, short sentences",
            "background": "Born to the band; knows the valley and its seasons.",
            "goals": ["get through each day", "have a place at the fire"],
            "known_tech": sorted(set(known)),
        }
    return out


def generate_emergent_village(villages_cfg: dict, seed: int) -> dict:
    """The EMERGENT flavor's cast: two small villages of two families each.
    Personas are deliberately bare — random traits, no goals, no backstory,
    NO starting knowledge. Everything must be discovered or taught.
    Returns {npc_id: persona_dict with village/family fields}."""
    import random
    rng = random.Random(seed)
    out = {}
    for village, families in villages_cfg.items():
        for fam_idx, members in enumerate(families):
            for name in members:
                traits = {}
                for axis in rng.sample("HEXACODB", k=5):
                    traits[axis] = int(max(5, min(95, rng.gauss(50, 18))))
                out[name] = {
                    "name": name.capitalize(),
                    "role": "one of the band",
                    "era": "the dawn of people",
                    "traits": traits,
                    "background": "Knows only what they have seen with their own eyes.",
                    # the one seed of intent — everything else must be invented
                    "goals": ["build a civilisation"],
                    "known_tech": [],
                    "village": village,
                    "family": fam_idx,
                }
    return out


def generate_child(name: str, parent_a: dict, parent_b: dict,
                   traits_data: dict, seed: int) -> dict:
    """A newborn mind, per the traits.json generation spec: traits are the
    parents' weighted average plus gaussian noise. Values come from the
    parents; knowledge starts at almost nothing — it must be TAUGHT."""
    import random
    rng = random.Random(seed)
    gen = (traits_data.get("meta", {}) or {}).get("generation", {})
    noise = float(gen.get("noise_stddev", 12))
    ta = parent_a.get("traits", {}) or {}
    tb = parent_b.get("traits", {}) or {}
    traits = {}
    for axis in sorted(set(ta) | set(tb)):
        base = (float(ta.get(axis, 50)) + float(tb.get(axis, 50))) / 2.0
        traits[axis] = int(max(5, min(95, rng.gauss(base, noise))))
    values = list(dict.fromkeys(
        (parent_a.get("values", []) or []) + (parent_b.get("values", []) or [])))[:2]
    a_name = parent_a.get("name", "?")
    b_name = parent_b.get("name", "?")
    return {
        "name": name.capitalize(),
        "role": "a child of the band",
        "era": parent_a.get("era", "early Stone Age (Upper Paleolithic)"),
        "traits": traits,
        "values": values or ["kinship"],
        "speech_style": "simple, direct, full of questions",
        "background": f"Child of {a_name} and {b_name}; born at the fire, "
                      "knows only what the band has shown them.",
        "goals": ["learn everything", "make the parents proud"],
        "known_tech": list(BASIC_TECH),
        "parents": [a_name, b_name],
    }


def compile_persona(raw: dict, traits_data: dict) -> dict:
    """Fill in personality/values prose from trait scores when not hand-written.
    Explicit persona fields always win — hand-tuned characters stay hand-tuned."""
    persona = dict(raw or {})
    if traits_data:
        if not persona.get("personality") and persona.get("traits"):
            persona["personality"] = render_traits(persona["traits"], traits_data)
        if persona.get("values") and not persona.get("values_prose"):
            persona["values_prose"] = render_values(persona["values"], traits_data)
    return persona
