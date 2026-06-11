# Research Agent — Design Spec

**Date:** 2026-06-11
**Status:** Approved

---

## Overview

A CLI tool that takes any topic as input, uses Claude to decompose it into a learning curriculum tree, uses Tavily to find sources for each concept, and saves the result as a structured markdown file. Each leaf concept is scoped to a maximum of 15 minutes of learning material.

---

## Goals

- Given any topic, produce a ready-to-use learning curriculum
- Every leaf concept has real, current web sources attached
- No concept exceeds 15 minutes of learning (ceiling, not floor)
- Output is a single markdown file in a predictable location
- No summaries or AI-generated content in the output — structure and sources only

## Non-Goals

- No web UI (CLI only for now)
- No database or persistence beyond the markdown file
- No scheduling or progress tracking
- No content fetching or summarization of source pages

---

## Architecture

```
research-agent/
├── main.py          — CLI entry point (argparse: topic, --output, --depth)
├── decomposer.py    — Claude API: generates the curriculum tree as JSON
├── searcher.py      — Tavily API: fetches 2-3 sources per leaf concept
├── refiner.py       — Claude API: checks if a concept is too broad; splits it
├── renderer.py      — formats the internal tree to markdown, saves .md file
├── output/          — default folder where all .md curricula are saved
└── .env             — ANTHROPIC_API_KEY, TAVILY_API_KEY (never committed)
```

**Stack:** Python 3.11+, Anthropic SDK, Tavily Python SDK

---

## Data Flow

1. User runs: `python main.py "machine learning"`
2. `decomposer.py` calls Claude with the topic → returns an internal JSON tree: `{ topic, subtopics: [{ name, concepts: [string] }] }`
3. For each leaf concept, `searcher.py` calls Tavily → returns 2–3 source URLs with titles
4. `refiner.py` checks each concept: if Tavily results span clearly different sub-areas (signal: result titles share no common terms), Claude is asked to split that concept into 2 atomic ones; re-search runs on each. Capped at 2 rounds of splitting per concept.
5. `renderer.py` formats the final tree as markdown and writes to `output/<sanitized-topic>.md`

---

## Output Format

File: `output/machine-learning.md`

```markdown
# Machine Learning

## Supervised Learning
### Linear Regression
- [StatQuest: Linear Regression](https://www.youtube.com/...)
- [Khan Academy: Least Squares](https://www.khanacademy.org/...)

### Logistic Regression
- [3Blue1Brown: Neural Networks](https://www.youtube.com/...)

## Unsupervised Learning
### K-Means Clustering
- [Towards Data Science: K-Means Explained](https://towardsdatascience.com/...)
```

Rules:
- H1 = topic
- H2 = subtopic
- H3 = concept (leaf, ≤15 min)
- Bullet list = sources (title + URL), 2–3 per concept
- If no sources found for a concept: `- (no sources found)`

---

## CLI Interface

```bash
python main.py "machine learning"
python main.py "machine learning" --output ~/curricula
python main.py "machine learning" --depth 3
```

| Flag | Default | Description |
|---|---|---|
| `topic` | required | Topic to generate curriculum for |
| `--output` | `./output` | Directory to save the markdown file |
| `--depth` | `3` | Maximum tree depth (topic → subtopic → concept) |

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| Tavily returns no results for a concept | Include concept in tree with `- (no sources found)` note; continue |
| Claude fails to decompose (API error) | Exit with clear error message; nothing written to disk |
| Refinement loop | Cap at 2 splitting rounds per concept to prevent infinite subdivision |
| Output directory does not exist | Create it automatically |

---

## Environment Variables

```
ANTHROPIC_API_KEY=<your key>
TAVILY_API_KEY=<your key>
```

Loaded from `.env` at startup via `python-dotenv`. Never committed.

---

## Testing

- One test file per module (`test_decomposer.py`, `test_searcher.py`, etc.)
- All API calls mocked — no live network calls in tests
- Fixed test topic: `"git branching"` for determinism
- Each test asserts the module's output shape (correct JSON structure, correct markdown format, etc.)

---

## File Naming

Topic string is sanitized for the filename:
- Lowercased
- Spaces → hyphens
- Special characters stripped
- Example: `"Machine Learning (Intro)"` → `machine-learning-intro.md`
