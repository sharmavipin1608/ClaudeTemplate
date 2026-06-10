# ADR-0009: Fact Provenance, Staleness Enforcement, and Controlled Tag Taxonomy

**Status:** Accepted
**Date:** 2026-06-09

## Context

`memory/facts.md` is the project's persistent knowledge store. Before PRs #48 and #49, facts were plain strings with a tag and date — no record of which agent wrote them, no record of which task produced them, and no enforcement that tags were meaningful. Three problems followed:

1. **No accountability:** If a fact turned out to be wrong, there was no way to trace it back to the task or agent that produced it.
2. **Silent staleness:** Facts written months ago were used in new agent prompts without any signal that they might be outdated. The Memory agent had no mechanism to distinguish a fact verified last week from one written at project inception.
3. **Tag entropy:** Any agent could invent any tag string. After a few sprints, tags drifted (`[auth]`, `[authentication]`, `[jwt]`) and grep-based retrieval became unreliable.

## Decision

**Provenance fields** — every fact written via `tools/memory_write.py` must include:
- `source`: the agent name that produced the fact
- `task`: the task ID that was active when the fact was written
- `reviewed_at`: date of last review (set to write date initially; updated when a fact is re-confirmed)

`memory_write.py` rejects writes missing any of these fields with a clear error. Existing facts without provenance are valid (`[LEGACY]` surfacing by the Memory agent) but no new facts are written without them.

**Staleness rule** — the Memory agent checks `reviewed_at` before surfacing a fact older than 30 days. Stale facts are flagged as `[STALE FACT]` in the agent's output rather than silently used. The threshold is configurable in `settings.json` (`memory.stale_facts_after_days`).

**Deduplication** — `memory_write.py` deduplicates by matching `[tag]` + overlapping keywords before appending. A near-duplicate updates the existing entry in place rather than creating a second line. This prevents facts.md from accumulating multiple slightly-different versions of the same claim.

**Controlled taxonomy** — `memory/taxonomy.md` defines 16 canonical tags. `memory_write.py` validates the tag against the taxonomy and rejects unknown tags. New tags require an explicit taxonomy update — this is a deliberate friction point to prevent drift.

**Scope hierarchy** — facts carry `scope:project|team|org`:
- `project` — specific to this codebase
- `team` — applicable across the team's projects; candidate for shared pool
- `org` — universal convention; should be in the shared pool

The scope field drives the shared pool promotion workflow (see ADR-0010).

**`memory/candidates.md`** — patterns seen 3+ times that are not yet formal conventions. The orchestrator reviews candidates at end of sprint or when 5+ entries accumulate. Candidates are either promoted to `CONVENTIONS.md` (with `scope:team` or `scope:org`) or discarded with a note in the episodic log.

## Alternatives considered

- **Free-form tags with no validation:** Low friction but breaks retrieval reliability within a few sprints. Rejected.
- **Numeric tag IDs:** Stable and unambiguous but require a lookup table to read. Hurts human readability of facts.md. Rejected.
- **Separate SQLite for facts:** Enables rich queries but adds a dependency and complicates session recovery. Rejected; revisit when facts exceed ~500 entries.
- **Auto-expire stale facts (delete):** More aggressive than flagging but risks losing context that is still correct. Memory agent marks outdated facts `[stale]` and appends a replacement — never deletes. Rejected for hard deletion.

## Consequences

- `memory_write.py` is now required for all fact writes; direct text editing of `facts.md` bypasses validation and will produce `[LEGACY]` entries on next audit.
- Adding a new domain requires a taxonomy update before any facts can be written for it — a one-minute change but a required step.
- The 30-day staleness threshold is arbitrary; projects with slow-changing domains should increase it; fast-moving projects should decrease it.

## Revisit trigger

When `facts.md` exceeds ~100 entries or when tag-based grep produces too many false positives, move to Phase 2 retrieval (ChromaDB or shared pool index).
