#!/usr/bin/env python3
"""Shared knowledge pool sync tool.

Pushes scope:team and scope:org facts to a shared pool repo, and pulls
org-scoped facts + taxonomy into a new project at bootstrap.

Shared pool repo structure expected:
  ClaudeKnowledge/
  ├── facts/
  │   ├── team.jsonl       # scope:team facts (one JSON object per line)
  │   └── org.jsonl        # scope:org facts (one JSON object per line)
  ├── conventions/
  │   └── approved.md      # promoted conventions
  └── taxonomy.md          # canonical tag list (source of truth)

Usage:
    python3 tools/pool_sync.py pull  --pool-url <git-url> [--memory-dir memory]
    python3 tools/pool_sync.py push  --pool-url <git-url> --fact "<fact>" --tag <tag> --scope team|org [--memory-dir memory]
    python3 tools/pool_sync.py check --pool-url <git-url> --fact "<fact>" --tag <tag>
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _run(cmd: list[str], cwd: str | None = None, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=check)


def _clone_pool(pool_url: str, dest: str) -> None:
    _run(["git", "clone", "--depth=1", pool_url, dest])


def _overlap_score(a: str, b: str) -> int:
    words_a = set(re.findall(r"\b\w{4,}\b", a.lower()))
    words_b = set(re.findall(r"\b\w{4,}\b", b.lower()))
    return len(words_a & words_b)


# ---------------------------------------------------------------------------
# pull: taxonomy.md + org facts → local project
# ---------------------------------------------------------------------------

def cmd_pull(pool_url: str, memory_dir: Path) -> None:
    """Pull taxonomy.md and scope:org facts from the shared pool into this project."""
    with tempfile.TemporaryDirectory() as tmpdir:
        print(f"Cloning shared pool from {pool_url} ...")
        try:
            _clone_pool(pool_url, tmpdir)
        except subprocess.CalledProcessError as e:
            print(f"ERROR: failed to clone pool: {e.stderr.strip()}", file=sys.stderr)
            sys.exit(1)

        pool = Path(tmpdir)

        # 1. Sync taxonomy.md
        pool_taxonomy = pool / "taxonomy.md"
        local_taxonomy = memory_dir / "taxonomy.md"
        if pool_taxonomy.exists():
            shutil.copy(pool_taxonomy, local_taxonomy)
            print(f"  ✓ taxonomy.md pulled from shared pool → {local_taxonomy}")
        else:
            print("  WARN: no taxonomy.md found in shared pool — skipping", file=sys.stderr)

        # 2. Pull scope:org facts into local facts.md
        org_facts_file = pool / "facts" / "org.jsonl"
        if not org_facts_file.exists():
            print("  INFO: no org.jsonl in shared pool — no facts to pull")
            return

        local_facts = memory_dir / "facts.md"
        existing_text = local_facts.read_text() if local_facts.exists() else ""

        pulled = 0
        for line in org_facts_file.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            tag = obj.get("tag", "")
            fact_text = obj.get("fact", "")
            reviewed_at = obj.get("reviewed_at", str(date.today()))
            source = obj.get("source", "shared_pool")
            task = obj.get("task", "shared_pool")

            entry = (
                f"[{tag}] {fact_text} — {date.today()} — "
                f"reviewed_at:{reviewed_at} — source:{source} — "
                f"task:{task} — scope:org — sourced_from:shared_pool\n"
            )

            # Skip if already present (same tag + high overlap)
            if _overlap_score(fact_text, existing_text) >= 3:
                continue

            with local_facts.open("a") as f:
                f.write(entry)
            existing_text += entry
            pulled += 1

        print(f"  ✓ {pulled} org-scoped fact(s) pulled into {local_facts}")


# ---------------------------------------------------------------------------
# check: detect conflicts before pushing
# ---------------------------------------------------------------------------

def cmd_check(pool_url: str, fact: str, tag: str) -> bool:
    """Check if a fact conflicts with an existing shared pool entry. Returns True if conflict."""
    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            _clone_pool(pool_url, tmpdir)
        except subprocess.CalledProcessError as e:
            print(f"ERROR: failed to clone pool: {e.stderr.strip()}", file=sys.stderr)
            sys.exit(1)

        pool = Path(tmpdir)
        conflicts = []

        for scope_file in ["team.jsonl", "org.jsonl"]:
            pool_file = pool / "facts" / scope_file
            if not pool_file.exists():
                continue
            for line in pool_file.read_text().splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if obj.get("tag") != tag:
                    continue
                existing_fact = obj.get("fact", "")
                score = _overlap_score(fact, existing_fact)
                if score >= 2:
                    conflicts.append({
                        "file": scope_file,
                        "existing": existing_fact,
                        "overlap_score": score
                    })

        if conflicts:
            print(f"CONFLICT: [{tag}] fact has {len(conflicts)} near-match(es) in shared pool:")
            for c in conflicts:
                print(f"  [{c['file']}] score={c['overlap_score']}: {c['existing'][:100]}")
            return True
        else:
            print(f"OK: no conflicts found for [{tag}] fact in shared pool")
            return False


# ---------------------------------------------------------------------------
# push: local fact → shared pool PR
# ---------------------------------------------------------------------------

def cmd_push(pool_url: str, fact: str, tag: str, scope: str, memory_dir: Path) -> None:
    """Push a scope:team or scope:org fact to the shared pool as a PR."""
    if scope not in ("team", "org"):
        print(f"ERROR: --scope must be 'team' or 'org', got '{scope}'", file=sys.stderr)
        sys.exit(1)

    # Conflict check first
    has_conflict = cmd_check(pool_url, fact, tag)
    if has_conflict:
        print("\nAborted — resolve conflicts before pushing. Use --force to override (not recommended).")
        sys.exit(1)

    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            # Need full clone (not depth=1) to push a branch
            _run(["git", "clone", pool_url, tmpdir])
        except subprocess.CalledProcessError as e:
            print(f"ERROR: failed to clone pool: {e.stderr.strip()}", file=sys.stderr)
            sys.exit(1)

        pool = Path(tmpdir)

        # Create branch
        branch = f"fact/{tag}-{date.today()}"
        _run(["git", "checkout", "-b", branch], cwd=tmpdir)

        # Append to the right scope file
        facts_dir = pool / "facts"
        facts_dir.mkdir(exist_ok=True)
        scope_file = facts_dir / f"{scope}.jsonl"

        entry = json.dumps({
            "tag": tag,
            "fact": fact,
            "date": str(date.today()),
            "reviewed_at": str(date.today()),
            "source": "pool_sync",
            "task": "manual-push"
        })
        with scope_file.open("a") as f:
            f.write(entry + "\n")

        # Commit and push
        _run(["git", "add", str(scope_file)], cwd=tmpdir)
        _run(["git", "commit", "-m", f"fact({tag}): add {scope}-scoped fact via pool_sync"], cwd=tmpdir)
        try:
            _run(["git", "push", "-u", "origin", branch], cwd=tmpdir)
        except subprocess.CalledProcessError as e:
            print(f"ERROR: git push failed: {e.stderr.strip()}", file=sys.stderr)
            sys.exit(1)

        # Open PR via gh CLI if available
        if shutil.which("gh"):
            try:
                result = _run([
                    "gh", "pr", "create",
                    "--title", f"fact({tag}): add {scope}-scoped fact",
                    "--body", f"**Tag:** `{tag}`\n**Scope:** `{scope}`\n**Fact:** {fact}\n\n_Auto-generated by `pool_sync.py`_",
                    "--head", branch
                ], cwd=tmpdir)
                pr_url = result.stdout.strip().split("\n")[-1]
                print(f"  ✓ PR opened: {pr_url}")
            except subprocess.CalledProcessError as e:
                print(f"  WARN: PR creation failed (push succeeded): {e.stderr.strip()}", file=sys.stderr)
        else:
            print(f"  ✓ Branch '{branch}' pushed. Open a PR manually on the shared pool repo.")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sync facts with the shared knowledge pool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument("command", choices=["pull", "push", "check"])
    parser.add_argument("--pool-url", required=True, help="Git URL of the shared pool repo")
    parser.add_argument("--fact", default="", help="Fact text (push/check only)")
    parser.add_argument("--tag", default="", help="Tag for the fact (push/check only)")
    parser.add_argument("--scope", default="team", choices=["team", "org"], help="Scope for push")
    parser.add_argument("--memory-dir", default="memory", help="Path to memory/ directory")
    args = parser.parse_args()

    memory_dir = Path(args.memory_dir)

    if args.command == "pull":
        cmd_pull(args.pool_url, memory_dir)
    elif args.command == "check":
        if not args.fact or not args.tag:
            print("ERROR: --fact and --tag required for check", file=sys.stderr)
            sys.exit(1)
        has_conflict = cmd_check(args.pool_url, args.fact, args.tag)
        sys.exit(1 if has_conflict else 0)
    elif args.command == "push":
        if not args.fact or not args.tag:
            print("ERROR: --fact and --tag required for push", file=sys.stderr)
            sys.exit(1)
        cmd_push(args.pool_url, args.fact, args.tag, args.scope, memory_dir)


if __name__ == "__main__":
    main()
