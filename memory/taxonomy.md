# Memory Taxonomy

Canonical tag list for `memory/facts.md`. Memory agent validates tags against this list before writing. To add a new tag: append it here with a description, then use it in facts.

## Tags

- **pipeline** — facts about the agent pipeline: order, routing, state machine behaviour
- **memory** — facts about the memory system: formats, retrieval, staleness rules
- **hooks** — facts about shell hooks: pre_task, classify_task, budget_guard, log_tool
- **contracts** — facts about agent envelope contracts and SLO definitions
- **bootstrap** — facts about the bootstrap process and template initialisation
- **agents** — facts about individual agent behaviour, prompts, and model assignments
- **skills** — facts about skill files and when they are loaded
- **conventions** — facts about coding, naming, and process conventions in this project
- **security** — facts about security rules, gates, and known vulnerabilities to avoid
- **testing** — facts about test strategy, coverage targets, and test runner configuration
- **observability** — facts about logging, tracing, and pipeline telemetry
- **architecture** — facts about high-level system design decisions and trade-offs
- **infra** — facts about CI/CD, deployment, and infrastructure configuration
- **api** — facts about HTTP API design, versioning, and response envelope conventions
- **database** — facts about schema, migrations, and data access patterns
- **auth** — facts about authentication, authorisation, and session management

## Adding tags

Add a line in the format `- **tagname** — description`. Tag names: lowercase, letters and hyphens only. After adding, the tag is immediately usable in `memory_write.py`.
