# ADR-0004: Phased Memory Retrieval Strategy

**Status:** Accepted
**Date:** 2026-06-09

## Context

The memory system stores project facts in `memory/facts.md` using a tagged format: `[domain] fact about the project`. As a project evolves, this file grows. Each agent dispatch needs relevant facts from this file — but loading the entire file into every agent's context has two costs: token cost (proportional to file size) and noise cost (irrelevant facts can confuse agents and dilute their focus).

Vector search (e.g. ChromaDB) solves the noise problem but requires infrastructure: a vector database must be installed, initialised, and kept in sync with `facts.md`. At project bootstrap, this overhead is disproportionate to a file that may contain only a dozen entries.

The decision was how to balance precision and infrastructure cost as the file grows.

## Decision

Three-phase retrieval strategy, with the current phase determined by `facts.md` line count:

**Phase 1 (default, active now):** Tag-based grep
```bash
grep "\[auth\]" memory/facts.md
```
The orchestrator identifies the relevant domain tags for each task (e.g. `[auth]`, `[database]`, `[api]`) and passes only the matching lines to the agent. Zero dependencies. Tags must be consistent — enforced by the Memory agent writing to a fixed format.

**Phase 2 (when `wc -l memory/facts.md` exceeds 100 lines):** ChromaDB vector search
Install ChromaDB, index `facts.md` entries, query by semantic similarity. Retrieves relevant facts even when the exact tag is not known. Migration from Phase 1 is straightforward because the `[domain] fact` format provides natural metadata for the vector store.

**Phase 3 (long-running projects):** Dedicated Memory Agent with embeddings
When the facts corpus becomes large enough that a single query may span multiple domains (e.g. a task touches auth, database, and API simultaneously), a dedicated Memory Agent handles retrieval using full embedding search across all memory files, not just `facts.md`.

The tag format `[domain] fact` is chosen specifically to make Phase 2 migration low-friction: the `[domain]` prefix becomes the metadata field in the vector store entry.

## Alternatives considered

- **Always use vector search:** Requires `pip install chromadb` (or equivalent) at bootstrap, plus initialisation of the vector store before the first task. Rejected because this is a significant setup burden for a project that may never exceed 50 facts. The complexity is not justified until Phase 2 threshold is hit.
- **Always load full `facts.md`:** Simple but grows unbounded. A 500-line facts file injected into every agent context wastes tokens on irrelevant information and can cause agent confusion. Rejected as the long-term strategy.
- **No persistent memory (session-only context):** Loses continuity between sessions. The Orchestrator would need to re-establish project context from scratch each session — expensive and error-prone. Rejected. The memory system is a core architectural assumption.
- **Single-phase: always grep, never evolve:** Too rigid. Grep precision degrades as facts become more nuanced. Commit to the phased approach and re-evaluate at the threshold.

## Consequences

- Phase 1 is zero-dependency and works immediately after bootstrap. The only requirement is consistent tag discipline from the Memory agent.
- If tags are inconsistently written (e.g. `[Auth]` vs `[auth]` vs `[authentication]`), grep misses entries. The Memory agent instructions must enforce lowercase normalised tags.
- Phase 2 migration requires a one-time ChromaDB setup and index build. Because facts are in a structured format, this can be scripted.
- The 100-line threshold is a heuristic. Monitor retrieval quality — if agents regularly receive context that is missing relevant facts, lower the threshold.

## Revisit trigger

When `wc -l memory/facts.md` regularly exceeds 100 lines, initiate Phase 2 migration. Also revisit if agents start producing errors that can be traced to missing context that grep retrieval should have caught (indicating tag inconsistency, not threshold breach).
