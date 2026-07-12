# VOX NPC Personality System (behavioral basis)

Physical traits out of scope. Goal: a compact, data-driven psychology that (a) drives the in-engine behavior layer numerically and (b) renders into natural language for the LLM prompt. Becomes `data/traits.json` + `personas/*.yaml`.

---

## 1. Layered model

```
TRAITS (stable, 0–100)  →  VALUES (slow-changing)  →  DRIVES/NEEDS (hourly)  →  MOOD (minutes)  →  behavior & dialogue
                                          ↑ RELATIONSHIPS + MEMORIES modulate everything
```

## 2. Core trait axes (stable personality)

Six HEXACO-based axes — better than Big Five for a social sim because Honesty–Humility directly drives theft, deception, and fairness behavior. Each 0–100; both poles are playable, neither is "good".

| Axis | Low pole (0–30) | High pole (70–100) | Drives in-sim |
|---|---|---|---|
| **H — Honesty/Humility** | schemer: cheats trades, steals, flatters, hoards status | sincere: fair trades, keeps promises, modest | trade fairness, theft chance, promise-keeping, tribute behavior |
| **E — Emotionality** | stoic: risk-blind, low attachment, no help-seeking | sensitive: fearful, anxious, deeply bonded, seeks help | flight threshold, grief intensity, danger assessment |
| **X — Extraversion** | solitary: works alone, quiet at feasts | social: seeks crowds, leads talk, needs company | social-need decay rate, conversation initiation, leadership bids |
| **A — Agreeableness** | irritable: holds grudges, quick to quarrel, punishes | forgiving: patient, defuses conflict, cooperates | grudge decay, conflict escalation, cooperation on shared work |
| **C — Conscientiousness** | impulsive: abandons tasks, sloppy craft, no stores | diligent: plans ahead, finishes work, stockpiles | plan adherence, craft quality bonus, food-storage behavior |
| **O — Openness** | traditionalist: distrusts new tech, keeps customs | curious: experiments, adopts/discovers tech first | **tech discovery & adoption rate**, migration willingness, art |

Plus two sim-specific axes:

| Axis | Low | High | Why separate |
|---|---|---|---|
| **D — Dominance** | submissive, defers | commanding, claims leadership | hierarchy formation shouldn't be welded to extraversion |
| **B — Bravery** | flees early | stands ground, hunts big game | courage ≠ low emotionality; heroes can be sensitive |

**Trait generation**: newborn NPC = weighted parent average + gaussian noise; culture adds small biases (e.g., a raiding-culture village nudges B/D up).

## 3. Values (learned, slow-changing)

Cultural weights 0–100, shifted by upbringing and major memories: **Tradition, Kinship/Loyalty, Prosperity, Prestige, Piety, Community, Freedom, Knowledge**. Values choose *between* goals ("defend shrine" vs "save grain"), traits choose *how* (bravely, carefully, deceitfully).

## 4. Drives / needs (the hourly engine)

Maslow-ish stack, each 0–100, decaying at trait-modulated rates. The GOAP layer always services the most urgent; the LLM is consulted when drives conflict or on how to satisfy one.

Survival: **hunger, thirst, warmth, rest, safety, health**. Social: **belonging** (X-modulated), **status** (D/Prestige-modulated), **family** (protect kin). Higher: **curiosity** (O-modulated → exploration, tech experimentation), **ritual/meaning** (Piety), **craft pride** (C → improve skill, make masterworks).

## 5. Mood & emotion (minutes-scale)

Running mood = valence (−50..+50) + arousal (0..100), plus tagged active emotions from an OCC-style appraisal: event × traits → {joy, fear, anger, grief, pride, shame, gratitude, envy}. Emotions decay (rates trait-modulated: A slows anger decay when low; E deepens grief). Mood tints every LLM call ("You are grieving; you buried your brother yesterday").

## 6. Relationships (per NPC-pair, directional)

| Dim | Range | Moves when |
|---|---|---|
| Affinity | −100..100 | shared meals, gifts, insults, fights |
| Trust | 0..100 | promises kept/broken, trades, secrets |
| Respect | 0..100 | skill displays, bravery, wisdom, status |
| Familiarity | 0..100 | time together (gates memory detail about them) |
| Debt | −100..100 | favors owed either way |

Kinship tags (parent/child/sibling/mate) are structural overlays. Relationship summaries are rendered into dialogue prompts ("Toran: your brother, trusted, you owe him a favor").

## 7. Skills & knowledge (separate from personality)

Per-NPC skill levels (0–100) for practice domains (knapping, hunting, potting, smithing, herblore, oratory…) and a **known-tech set** (node IDs from `01_TECH_TREE.md`). Learning speed = f(O, teacher's skill, diffusion tier). This is the bridge between personality and the tech tree: high-O high-C NPCs are your inventors; high-X high-D NPCs spread and organize.

## 8. Rendering into the LLM prompt

Numbers never go in the prompt raw. Each axis maps to descriptor bands (0–15 / 16–30 / 31–69 / 70–84 / 85–100), e.g. C: "chaotic, never finishes anything" → "somewhat careless" → (omit mid-band) → "methodical" → "obsessively meticulous". A persona block is compiled per call:

```
You are Kara, a potter of Riverbend village (late Neolithic).
Personality: obsessively meticulous, curious about new methods, quiet, slow to trust.
Values: craft pride and knowledge over status.
Now: tired, mildly anxious (a wolf was seen); mourning nobody; well-fed.
Relationships present: Toran (brother, trusted), Suma (rival potter, you envy her kiln).
You know how to: [relevant tech]. You cannot reference things beyond your era.
Respond as Kara: short, plain speech. Output JSON: {say, action, target}.
```

Mid-band traits are omitted — only distinctive traits reach the prompt (token economy + sharper characters).

## 9. Behavioral hooks (traits → engine numbers)

Examples of the mapping table (full table lives in `traits.json`):

| Behavior parameter | Formula sketch |
|---|---|
| flee_threshold | 70 − 0.4·B + 0.3·E |
| theft_probability (starving) | (100−H)·hunger/10⁴ |
| experiment_chance (idle, materials present) | O·curiosity/10⁴ |
| grudge_halflife_days | (100−A)/10 |
| plan_abandon_chance/hr | (100−C)/500 |
| conversation_start_radius | 2 + X/20 voxels |

## 10. Archetype starter deck (12 seeds)

For initial casting, sample near: **Elder-keeper** (O30 C80 Tradition), **Inventor** (O90 C75 Knowledge), **Hunter-hero** (B90 D60 Prestige), **Caregiver** (E75 A85 Kinship), **Schemer** (H15 X70 Prosperity), **Chief-in-waiting** (D90 X75 Prestige), **Hermit-crafter** (X15 C90 Craft), **Storyteller** (X85 O70 Community), **Zealot** (Piety95 A40), **Trader** (H45 X65 Prosperity), **Brawler** (A20 B80), **Dreamer** (O85 C30). Add gaussian noise so no two are identical.

## 11. Open questions (next design pass)

Trait drift over life events (trauma lowers E-stability?); childhood/learning phase length; whether values can conflict enough to model internal dilemmas for the LLM; cultural evolution (village-level trait priors shifting over generations).
