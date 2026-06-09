# Shared Knowledge Pool

The shared knowledge pool is an optional sibling git repository (`ClaudeKnowledge`) that stores facts, conventions, and a taxonomy that apply across multiple projects. Facts with `scope:team` or `scope:org` are candidates for promotion to the pool.

---

## Repository Structure

```
ClaudeKnowledge/
├── facts/
│   ├── team.jsonl       ← scope:team facts (one JSON object per line)
│   └── org.jsonl        ← scope:org facts (one JSON object per line)
├── conventions/
│   └── approved.md      ← conventions promoted from candidates.md
└── taxonomy.md          ← canonical tag list (source of truth for all projects)
```

Each fact in `team.jsonl` / `org.jsonl` is a JSON object:
```json
{"tag": "pipeline", "fact": "...", "date": "2026-06-09", "reviewed_at": "2026-06-09", "source": "memory", "task": "TASK-005"}
```

---

## Workflows

### Bootstrap: pull from shared pool

When starting a new project, `bootstrap.sh` Step 3c optionally pulls from the shared pool:
1. Copies `taxonomy.md` → `memory/taxonomy.md` (canonical tags for this project)
2. Copies `scope:org` facts → appended to `memory/facts.md` with `sourced_from:shared_pool`

```bash
python3 tools/pool_sync.py pull --pool-url https://github.com/org/ClaudeKnowledge
```

### Memory agent: push a fact to the pool

After writing a `scope:team` or `scope:org` fact, the Memory agent can push it:

```bash
python3 tools/pool_sync.py push \
  --pool-url https://github.com/org/ClaudeKnowledge \
  --tag pipeline \
  --fact "orchestrator always validates agent output against contracts before routing" \
  --scope team
```

This runs a conflict check first, then opens a PR against the shared pool. The PR is reviewed and merged manually.

### Conflict detection

Before pushing, check for conflicts:

```bash
python3 tools/pool_sync.py check \
  --pool-url https://github.com/org/ClaudeKnowledge \
  --tag pipeline \
  --fact "orchestrator validates agent output"
```

Exit 0 = no conflict. Exit 1 = conflict found (details printed).

---

## Conflict Resolution

If `pool_sync.py check` finds a conflict:
- `CONFLICT: [tag] fact has N near-match(es) in shared pool` is printed
- The orchestrator surfaces this to the user before any push
- Resolution options:
  1. **Override**: update the shared pool entry with the newer local fact (requires explicit decision)
  2. **Keep local**: don't push; fact stays project-scoped
  3. **Discard local**: remove the local fact, use the shared pool version instead

---

## Sourced facts

Facts pulled from the shared pool are marked `sourced_from:shared_pool` in `memory/facts.md`. The Memory agent treats these as authoritative — do not modify them locally. To propose a change, push a new version via `pool_sync.py push`.

---

## Setting up the shared pool repo

Create a new GitHub repository (e.g. `ClaudeKnowledge`) with this structure:

```bash
mkdir ClaudeKnowledge && cd ClaudeKnowledge
mkdir -p facts conventions
echo '{}' > facts/team.jsonl   # placeholder, delete after first real fact
echo '{}' > facts/org.jsonl
touch conventions/approved.md
cp /path/to/project/memory/taxonomy.md taxonomy.md
git init && git add . && git commit -m "chore: init shared knowledge pool"
gh repo create ClaudeKnowledge --private --source=. --push
```
