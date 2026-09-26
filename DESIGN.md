# Co-op Arcane Sorting Sim — Design

One page. Every new feature gets checked against the pillars below; if it
fights one, it needs a very good reason.

## Vision

A cozy puzzle game for 1–4 friends: you're a crew of archivists restoring
a magical archive that's been turned upside down. Hundreds of strange
objects lie scattered across the floor; you figure out what each one *is*
and put it where it belongs. There's no villain, no failure, no rush —
just the satisfaction of turning chaos into order, together.

## Decisions (step 1)

| Question | Decision |
|---|---|
| Fantasy | **Cozy puzzle crew** |
| Can you lose? | **No — only a score** |
| What's the puzzle? | **Matching things by their type**, not by color |
| Why co-op? | **Sort in parallel** — shared goal, no forced communication |

## Pillars

1. **Order from chaos feels good.** Every correct placement should feel
   satisfying: a snap, a glow, a sound. Progress is always visible — the
   room gets visibly tidier as you play.
2. **Figure out what it is.** The puzzle is identification. You look at an
   object's shape, read its name and description, and work out its type.
   Color is decoration, never the answer.
3. **Gentle, never punishing.** Mistakes are flagged and fixable, never
   game-ending. There is no timer pressure and no fail state.
4. **Together, at your own pace.** Each player can sort independently, so
   a quiet friend and a chatty friend both have fun. Co-op means a shared
   goal and good company, not required coordination. Solo play is fine too.

## Core loop

Look at an object → work out its type → carry it to that type's shelf →
place it → it locks in place with a satisfying snap → repeat until the
archive is restored → see your crew's results.

## What each decision means for the game

**Cozy.** No countdown and no stress music. Soft lighting, warm sounds,
relaxed pacing. Rounds should be a comfortable length (target: 15–25 min).

**Score only.** The round always ends in a win; the score says how neatly
you did it. **Proposal:** the score rewards accuracy first (e.g. stars:
3★ ≤ 2 mistakes, 2★ ≤ 8, 1★ otherwise). Time is still shown on the results
screen as a personal note, but isn't part of the score — scoring speed
would add the time pressure the cozy pillar rules out.

**Matching by type.** This replaces color-matching, which is currently
the whole puzzle and makes the text clues irrelevant. Concretely:
- Types are *what the object is*: Potions, Tomes, Scrolls, Crystals,
  Keys, Candles, Maps, … (more types than today's 3, so there's more to
  tell apart).
- Item color is randomized within a palette and no longer matches the
  shelf. Shelves are labeled by type (sign + icon), not tinted.
- Clues come from **shape** (each type has its own mesh family),
  **name**, and **description**.
- **Design risk:** if shape alone gives the answer away, we've just
  swapped color-matching for shape-matching. Difficulty should grow
  across archives: early ones where shape is enough, later ones with
  look-alikes that need the description (a vial of ink is Writing
  Supplies, not a Potion; a crystal key is a Key, not a Crystal).

**Sort in parallel.** No asymmetric information, no roles that force
talking. Co-op features are optional conveniences:
- Item count scales with player count (so solo isn't a slog and 4
  players isn't over in minutes).
- Pings ("where does this go?" / "here!") are nice to have, not required.
- Light social touches: waving, handing an item to a friend.
- The zone split from the old roadmap becomes optional, not required.

## Status

**Step 2 (matching by type) — done.**
- Six types: Potions, Tomes, Scrolls, Crystals, Keys, Candles (30 each).
- Eight shapes: Potions come as a round flask *or* a slim vial, Crystals as
  an orb *or* a grown cluster — same type, different shapes, so players
  sort by what a thing *is*.
- Items take a random jewel tone from one palette shared by all types.
  Shelves, slots and the HUD are colour-neutral.
- Each shelf sign shows the type, a one-line rule ("rolled writings,
  sealed or tied") and brass statuettes of every shape that belongs there.
- Names and descriptions are built each round from per-type pools
  (6 nouns × 6 qualifiers = 36 unique per type). Every description carries
  a hint of the type ("bound", "rolled", "a sip").
- Look-alikes across types (e.g. an ink bottle that isn't a Potion) are
  just data now — a pool entry pointing at another type's model — ready
  for later archives.

## Out of scope (for now)

Fail states, timers that end the round, competitive modes, asymmetric
roles, voice chat.

## Open questions

- Final type list and how many types per archive?
- Accuracy-based star thresholds — tune after playtesting.
- Should scaling be by player count only, or also a chosen "archive size"?
