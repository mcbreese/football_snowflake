"""Run the football eval questions through headless Claude Code and grade
every trial. See evals/README.md for setup, grading rules and log layout.

Usage (from the repo root):
    uv run --env-file secrets/.env.eval python evals/run_evals.py --only L1 --trials 1   # pilot
    uv run --env-file secrets/.env.eval python evals/run_evals.py                       # full run
    uv run python evals/run_evals.py --dry-run                                          # no calls
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import yaml

# Make `evals.grading` importable when this file is run as a script.
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from evals.grading import (  # noqa: E402
    extract_sql_calls,
    grade_answer,
    is_grounded,
    parse_answer,
    redact,
)

EVALS_DIR = REPO_ROOT / "evals"
DEFAULT_MODEL = "claude-sonnet-5-5"
# "snowflake" is the server name in evals/mcp.json; Claude Code names MCP
# tools mcp__<server>__<tool>.
SQL_TOOL = "mcp__snowflake__sql_exec_tool"
REQUIRED_ENV = ["SNOWFLAKE_MCP_URL", "SNOWFLAKE_MCP_PAT", "ANTHROPIC_API_KEY"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--trials", type=int, default=3)
    parser.add_argument("--only", nargs="*", help="Question ids to run, e.g. L1 A3")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument(
        "--max-budget-usd",
        type=float,
        default=0.50,
        help="Per-trial spend cap, enforced by Claude Code",
    )
    parser.add_argument(
        "--max-total-usd",
        type=float,
        default=10.0,
        help="Whole-run spend cap; the run stops once this is reached",
    )
    parser.add_argument(
        "--timeout", type=int, default=300, help="Seconds before a trial is killed"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the commands and exit without calling Claude or Snowflake",
    )
    return parser.parse_args()


def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command_output(cmd: list[str]) -> str | None:
    try:
        return subprocess.run(
            cmd, capture_output=True, text=True, check=True
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def claude_command(question: str, args: argparse.Namespace) -> list[str]:
    """The exact headless invocation for one trial. Each flag is there for
    a reason - see the comments, and evals/README.md."""
    return [
        "claude",
        "--bare",  # ignore local hooks, CLAUDE.md, plugins: same run on any machine
        "-p",
        question,
        "--model",
        args.model,
        "--mcp-config",
        str(EVALS_DIR / "mcp.json"),
        "--strict-mcp-config",  # only the Snowflake server, nothing else
        "--tools",
        "",  # no built-in tools: no Bash, no file reads (so no peeking at the key)
        "--allowedTools",
        SQL_TOOL,
        "--permission-mode",
        "dontAsk",  # anything not allowed above is denied, never prompted
        "--permission-prompts",
        "none",
        "--append-system-prompt-file",
        str(EVALS_DIR / "prompt.md"),
        "--output-format",
        "stream-json",
        "--verbose",  # required by stream-json; gives every event, not just the end
        "--max-budget-usd",
        str(args.max_budget_usd),
    ]


def run_trial(question: dict, trial: int, args, run_dir: Path, base: dict) -> dict:
    """Run one question once, write its raw transcript, and return the
    graded row for results.jsonl."""
    started = datetime.now(timezone.utc)
    clock = time.monotonic()
    error = None
    try:
        proc = subprocess.run(
            claude_command(question["question"], args),
            capture_output=True,
            text=True,
            timeout=args.timeout,
            cwd=EVALS_DIR,
        )
        stdout, stderr, exit_code = proc.stdout, proc.stderr, proc.returncode
    except subprocess.TimeoutExpired as exc:
        stdout = (
            exc.stdout.decode() if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        )
        stderr, exit_code, error = "", None, f"timeout after {args.timeout}s"

    secrets = [os.environ.get("SNOWFLAKE_MCP_PAT"), os.environ.get("ANTHROPIC_API_KEY")]
    stdout = redact(stdout, secrets)
    stderr = redact(stderr, secrets)

    # Raw layer: every event, untouched apart from redaction.
    raw_path = run_dir / "raw" / f"{question['id']}_t{trial}.jsonl"
    raw_path.write_text(stdout)
    if stderr.strip():
        raw_path.with_suffix(".stderr.txt").write_text(stderr)

    events = []
    for line in stdout.splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue  # stray non-JSON output; it's still in the raw file

    init = next((e for e in events if e.get("subtype") == "init"), {})
    result = next((e for e in reversed(events) if e.get("type") == "result"), {})
    if not result and error is None:
        error = f"no result event (exit code {exit_code})"
    elif result.get("is_error") and error is None:
        error = result.get("subtype") or "result marked is_error"

    final_text = result.get("result")
    parsed = parse_answer(final_text)
    sql_calls = extract_sql_calls(events, SQL_TOOL)
    answer_pass = grade_answer(question, parsed)
    grounded = is_grounded(question, sql_calls)
    # Refusals have nothing to ground (grounded is None), so they pass on
    # the answer alone. Everything else needs both checks.
    passed = answer_pass and (grounded is None or grounded)

    usage = result.get("usage") or {}
    return {
        **base,
        "question_id": question["id"],
        "category": question.get("category"),
        "trial": trial,
        "started_at": started.isoformat(),
        "ended_at": datetime.now(timezone.utc).isoformat(),
        "duration_ms": round((time.monotonic() - clock) * 1000),
        "session_id": result.get("session_id") or init.get("session_id"),
        "mcp_servers": init.get("mcp_servers"),
        "expected": question["expected"],
        "final_answer_raw": final_text,
        "parsed_answer": parsed,
        "answer_pass": answer_pass,
        "grounded": grounded,
        "pass": passed,
        "num_turns": result.get("num_turns"),
        "num_tool_calls": len(sql_calls),
        # Keep rows out of the summary log; they're in the raw transcript.
        "sql_calls": [
            {k: c[k] for k in ("sql", "query_id", "row_count", "is_error")}
            for c in sql_calls
        ],
        "input_tokens": usage.get("input_tokens"),
        "output_tokens": usage.get("output_tokens"),
        "cache_read_tokens": usage.get("cache_read_input_tokens"),
        "cache_creation_tokens": usage.get("cache_creation_input_tokens"),
        "total_cost_usd": result.get("total_cost_usd"),
        "permission_denials": result.get("permission_denials"),
        "exit_code": exit_code,
        "error": error,
        "raw_file": str(raw_path.relative_to(run_dir)),
    }


def summarise(rows: list[dict], trials: int) -> dict:
    """Per-question and overall scores. pass@k and pass^k as defined in
    Anthropic's evals guidance: at least one of k trials passed, and all k
    trials passed (the consistency measure)."""
    by_question: dict[str, list[dict]] = {}
    for row in rows:
        by_question.setdefault(row["question_id"], []).append(row)

    per_question = {}
    for qid, qrows in by_question.items():
        passes = [r["pass"] for r in qrows]
        per_question[qid] = {
            "trials": len(qrows),
            "passes": sum(passes),
            "answer_passes": sum(r["answer_pass"] for r in qrows),
            "grounded": sum(bool(r["grounded"]) for r in qrows),
            "pass_at_k": any(passes),
            "pass_hat_k": all(passes) and len(qrows) == trials,
        }

    n = len(rows) or 1
    q = len(per_question) or 1
    costs = [r["total_cost_usd"] or 0 for r in rows]
    return {
        "trials_run": len(rows),
        "pass_at_1": round(sum(r["pass"] for r in rows) / n, 3),
        "answer_only_pass_at_1": round(sum(r["answer_pass"] for r in rows) / n, 3),
        f"pass_at_{trials}": round(
            sum(v["pass_at_k"] for v in per_question.values()) / q, 3
        ),
        f"pass_hat_{trials}": round(
            sum(v["pass_hat_k"] for v in per_question.values()) / q, 3
        ),
        "errors": sum(1 for r in rows if r["error"]),
        "total_cost_usd": round(sum(costs), 4),
        "mean_cost_per_trial_usd": round(sum(costs) / n, 4),
        "per_question": per_question,
    }


def main() -> int:
    args = parse_args()
    key_path = EVALS_DIR / "questions.yaml"
    prompt_path = EVALS_DIR / "prompt.md"
    key = yaml.safe_load(key_path.read_text())
    questions = [q for q in key["questions"] if not args.only or q["id"] in args.only]
    if not questions:
        print(f"No questions match --only {args.only}", file=sys.stderr)
        return 2

    if args.dry_run:
        for q in questions:
            print(
                " ".join(
                    repr(part) if " " in part or not part else part
                    for part in claude_command(q["question"], args)
                )
            )
        return 0

    missing = [name for name in REQUIRED_ENV if not os.environ.get(name)]
    if missing:
        print(
            f"Missing environment variables: {', '.join(missing)}. "
            "Run via `uv run --env-file secrets/.env.eval ...` (see evals/README.md).",
            file=sys.stderr,
        )
        return 2

    git_sha = command_output(["git", "rev-parse", "--short", "HEAD"]) or "nogit"
    started = datetime.now(timezone.utc)
    run_id = f"{started.strftime('%Y%m%dT%H%M%SZ')}_{git_sha}"
    run_dir = EVALS_DIR / "runs" / run_id
    (run_dir / "raw").mkdir(parents=True)

    # Columns repeated on every row, so each row stands alone once the
    # logs are loaded somewhere else (e.g. Snowflake) without the manifest.
    base = {
        "run_id": run_id,
        "model": args.model,
        "claude_code_version": command_output(["claude", "--version"]),
        "git_sha": git_sha,
        "answer_key_sha256": sha256_of(key_path),
        "answer_key_snapshot": key.get("data_snapshot"),
        "prompt_sha256": sha256_of(prompt_path),
    }
    manifest = {
        **base,
        "started_at": started.isoformat(),
        "trials_per_question": args.trials,
        "question_ids": [q["id"] for q in questions],
        "max_budget_usd_per_trial": args.max_budget_usd,
        "max_total_usd": args.max_total_usd,
        "mcp_server_url_host": os.environ["SNOWFLAKE_MCP_URL"].split("/")[2],
    }
    manifest_path = run_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))

    rows: list[dict] = []
    spent = 0.0
    stopped_early = None
    with (run_dir / "results.jsonl").open("a") as results_file:
        for question in questions:
            for trial in range(1, args.trials + 1):
                if spent >= args.max_total_usd:
                    stopped_early = f"max_total_usd {args.max_total_usd} reached"
                    break
                row = run_trial(question, trial, args, run_dir, base)
                rows.append(row)
                # Written and flushed per trial, so a crash keeps every
                # finished row.
                results_file.write(json.dumps(row) + "\n")
                results_file.flush()
                spent += row["total_cost_usd"] or 0
                status = "PASS" if row["pass"] else "fail"
                print(
                    f"{question['id']} t{trial}: {status:4}  answer={row['parsed_answer']!r} "
                    f"grounded={row['grounded']}  ${row['total_cost_usd'] or 0:.4f}"
                    + (f"  ERROR: {row['error']}" if row["error"] else "")
                )
            if stopped_early:
                break

    manifest.update(
        {
            "ended_at": datetime.now(timezone.utc).isoformat(),
            "stopped_early": stopped_early,
            "summary": summarise(rows, args.trials),
        }
    )
    manifest_path.write_text(json.dumps(manifest, indent=2))
    summary = manifest["summary"]
    print(
        f"\nRun {run_id}: pass@1 {summary['pass_at_1']:.0%} "
        f"(answer-only {summary['answer_only_pass_at_1']:.0%}), "
        f"pass@{args.trials} {summary[f'pass_at_{args.trials}']:.0%}, "
        f"pass^{args.trials} {summary[f'pass_hat_{args.trials}']:.0%}, "
        f"cost ${summary['total_cost_usd']:.4f}, errors {summary['errors']}"
    )
    print(f"Logs: {run_dir.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
