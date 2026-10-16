"""Run the football eval questions through headless Claude Code and grade
every trial. See evals/README.md for setup, grading rules and log layout.

Usage (from the repo root):
    uv run --env-file secrets/.env.eval python evals/run_evals.py --only L1 --trials 1   # pilot
    uv run --env-file secrets/.env.eval python evals/run_evals.py                       # full run
    uv run python evals/run_evals.py --dry-run                                          # no calls
    uv run --env-file secrets/.env.eval python evals/run_evals.py --questions evals/questions_hard.yaml --context evals/context.md
"""

import argparse  # reads command-line flags like --only L1 --trials 1
import hashlib  # fingerprints files, to log exactly which version was used
import json
import os  # reads environment variables (the secrets)
import subprocess  # starts other programs, here `claude`
import sys
import time  # a stopwatch for durations
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from datetime import datetime, timezone
from pathlib import Path  # file paths: Path / "folder" / "file"

import yaml  # reads questions.yaml into Python dicts

# Make `evals.grading` importable when this file is run as a script.
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from evals.grading import (  # noqa: E402
    extract_sql_calls,
    grade_answer,
    is_grounded,
    matched_reading,
    parse_answer,
    readings,
    redact,
)

EVALS_DIR = REPO_ROOT / "evals"
DEFAULT_MODEL = "claude-sonnet-5-5"
# "snowflake" is the server name in evals/mcp.json; Claude Code names MCP
# tools mcp__<server>__<tool>.
SQL_TOOL = "mcp__snowflake__sql_exec_tool"
REQUIRED_ENV = ["SNOWFLAKE_MCP_URL", "SNOWFLAKE_MCP_PAT", "ANTHROPIC_API_KEY"]
# Oldest Claude Code with every flag used below and a fully isolated --bare.
MIN_CLAUDE_VERSION = (2, 1, 286)


def claude_version() -> tuple[int, ...] | None:
    # "2.1.234 (Claude Code)" -> (2, 1, 234); None if claude isn't installed.
    output = command_output(["claude", "--version"])
    if not output:
        return None
    return tuple(int(part) for part in output.split()[0].split("."))


def parse_args() -> argparse.Namespace:
    # Each add_argument is one flag you can pass; default = value if you don't.
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--trials", type=int, default=3, help="Times to run each question (default 3)"
    )
    parser.add_argument(
        "--questions",
        type=Path,
        default=EVALS_DIR / "questions.yaml",
        help="Answer key to run (default evals/questions.yaml)",
    )
    parser.add_argument(
        "--context",
        type=Path,
        help="Extra file added to the agent's instructions, after prompt.md "
        "(default: none)",
    )
    parser.add_argument("--only", nargs="*", help="Question ids to run, e.g. L1 A3")
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"Model to test (default {DEFAULT_MODEL})",
    )
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
        "--concurrency",
        type=int,
        default=4,
        help="Trials run at the same time (default 4). Higher is faster but "
        "risks API rate limits and queueing on the Snowflake warehouse",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the commands and exit without calling Claude or Snowflake",
    )
    return parser.parse_args()


def sha256_of(path: Path) -> str:
    # A fingerprint of the file: changes if even one character changes.
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command_output(cmd: list[str]) -> str | None:
    # Run a small command (e.g. git) and return its output, or None if it fails.
    try:
        return subprocess.run(
            cmd, capture_output=True, text=True, check=True
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def system_prompt(context_path: Path | None) -> str:
    """The instructions added to the agent's system prompt: prompt.md, then
    the --context file if one was given."""
    text = (EVALS_DIR / "prompt.md").read_text(encoding="utf-8")
    if context_path:
        text += "\n\n" + context_path.read_text(encoding="utf-8")
    return text


def claude_command(
    question: str, args: argparse.Namespace, prompt_path: Path
) -> list[str]:
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
        str(prompt_path),  # prompt.md, plus the --context file if given
        "--output-format",
        "stream-json",
        "--verbose",  # required by stream-json; gives every event, not just the end
        "--max-budget-usd",
        str(args.max_budget_usd),
    ]


def run_trial(
    question: dict, trial: int, args, run_dir: Path, base: dict, prompt_path: Path
) -> dict:
    """Run one question once, write its raw transcript, and return the
    graded row for results.jsonl."""
    started = datetime.now(timezone.utc)  # wall-clock start time, for the log
    clock = time.monotonic()  # stopwatch start, for duration_ms
    error = None
    try:
        # Start `claude` and wait for it to finish. capture_output keeps what it
        # prints (the transcript) instead of showing it on screen.
        proc = subprocess.run(
            claude_command(question["question"], args, prompt_path),
            capture_output=True,
            # Claude Code writes UTF-8. Without this, Windows decodes it with
            # its own default encoding and names like João arrive mangled.
            encoding="utf-8",
            errors="replace",
            timeout=args.timeout,
            cwd=EVALS_DIR,  # run from evals/, not the repo root
        )
        stdout, stderr, exit_code = proc.stdout, proc.stderr, proc.returncode
    except subprocess.TimeoutExpired as exc:  # ran longer than --timeout
        stdout = (
            exc.stdout.decode("utf-8", errors="replace")
            if isinstance(exc.stdout, bytes)
            else (exc.stdout or "")
        )
        stderr, exit_code, error = "", None, f"timeout after {args.timeout}s"

    # Scrub both secrets from the output before anything is written to disk.
    secrets = [os.environ.get("SNOWFLAKE_MCP_PAT"), os.environ.get("ANTHROPIC_API_KEY")]
    stdout = redact(stdout, secrets)
    stderr = redact(stderr, secrets)

    # Raw layer: every event, untouched apart from redaction.
    raw_path = run_dir / "raw" / f"{question['id']}_t{trial}.jsonl"
    raw_path.write_text(stdout, encoding="utf-8")
    if stderr.strip():
        raw_path.with_suffix(".stderr.txt").write_text(stderr, encoding="utf-8")

    events = parse_events(stdout)

    # next(...) = first event matching the condition, or {} if none.
    # init: the first event (which MCP servers connected).
    # result: the last event (final answer, cost, tokens).
    init = next((e for e in events if e.get("subtype") == "init"), {})
    result = next((e for e in reversed(events) if e.get("type") == "result"), {})
    if not result and error is None:
        error = f"no result event (exit code {exit_code})"
    elif result.get("is_error") and error is None:
        error = result.get("subtype") or "result marked is_error"

    usage = result.get("usage") or {}
    # One row for results.jsonl. **base copies in the run-level columns.
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
        **grade_events(question, events),  # the grading columns, see below
        "num_turns": result.get("num_turns"),
        "input_tokens": usage.get("input_tokens"),
        "output_tokens": usage.get("output_tokens"),
        "cache_read_tokens": usage.get("cache_read_input_tokens"),
        "cache_creation_tokens": usage.get("cache_creation_input_tokens"),
        "total_cost_usd": result.get("total_cost_usd"),
        "permission_denials": result.get("permission_denials"),
        "exit_code": exit_code,
        "error": error,
        "raw_file": raw_path.relative_to(run_dir).as_posix(),  # / on any OS
    }


def parse_events(stdout: str) -> list[dict]:
    """The transcript is one JSON object per line: turn each into a dict."""
    events = []
    for line in stdout.splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue  # stray non-JSON output; it's still in the raw file
    return events


def grade_events(question: dict, events: list[dict]) -> dict:
    """Grade one trial's transcript and return the grading columns of its
    results row. Kept separate from running the trial so that regrade.py
    can re-score saved transcripts with exactly the same code."""
    result = next((e for e in reversed(events) if e.get("type") == "result"), {})
    # Grading: all of these functions live in grading.py.
    final_text = result.get("result")  # the agent's final reply text
    parsed = parse_answer(final_text)
    sql_calls = extract_sql_calls(events, SQL_TOOL)
    answer_pass = grade_answer(question, parsed)
    # Which accepted reading the answer matched (None if it matched none).
    # Grounding then checks that reading's value, not any reading's.
    reading = matched_reading(question, parsed)
    grounded = is_grounded(reading or question, sql_calls)
    # Refusals have nothing to ground (grounded is None), so they pass on
    # the answer alone. Everything else needs both checks.
    passed = answer_pass and (grounded is None or grounded)
    return {
        # One value, or a list when the question has several readings
        "expected": (
            [r["expected"] for r in readings(question)]
            if "readings" in question
            else question["expected"]
        ),
        "reading": reading.get("label") if reading else None,
        "final_answer_raw": final_text,
        "parsed_answer": parsed,
        "answer_pass": answer_pass,
        "grounded": grounded,
        "pass": passed,
        "num_tool_calls": len(sql_calls),
        # Keep rows out of the summary log; they're in the raw transcript.
        "sql_calls": [
            {k: c[k] for k in ("sql", "query_id", "row_count", "is_error")}
            for c in sql_calls
        ],
    }


def summarise(rows: list[dict], trials: int) -> dict:
    """Per-question and overall scores. pass@k and pass^k as defined in
    Anthropic's evals guidance: at least one of k trials passed, and all k
    trials passed (the consistency measure)."""
    # Group rows into a dict: question_id -> list of that question's rows.
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
            # How often each reading was picked, e.g. {"paid only": 2}
            "readings": {
                label: sum(r.get("reading") == label for r in qrows)
                for label in {r.get("reading") for r in qrows}
                if label
            },
        }

    # `or 1` avoids dividing by zero if nothing ran.
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


def run_jobs(jobs, run_one, results_path: Path, concurrency: int, max_total_usd):
    """Run (question, trial) jobs, up to `concurrency` at once, writing each
    row to results.jsonl as it finishes. Returns (rows, stopped_early).

    Trials run in worker threads, but only this function writes the file,
    so rows can never interleave. Rows land in finishing order, not
    question order; each row says which question and trial it is.
    """
    rows: list[dict] = []
    spent = 0.0  # running cost, checked against --max-total-usd
    stopped_early = None
    pending = list(jobs)  # jobs not started yet
    running = {}  # future -> job, for the trials in flight
    with (
        ThreadPoolExecutor(max_workers=concurrency) as pool,
        results_path.open("a", encoding="utf-8") as results_file,
    ):
        while pending or running:
            # Start trials until `concurrency` are in flight. The spend cap is
            # only checked here, so trials already running can overshoot it
            # by up to `concurrency` trials' worth.
            while pending and len(running) < concurrency:
                if spent >= max_total_usd:
                    stopped_early = f"max_total_usd {max_total_usd} reached"
                    pending.clear()
                    break
                question, trial = pending.pop(0)
                running[pool.submit(run_one, question, trial)] = (question, trial)
            if not running:
                break
            # Wait for at least one trial to finish, then record it.
            done, _ = wait(running, return_when=FIRST_COMPLETED)
            for future in done:
                question, trial = running.pop(future)
                row = future.result()
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
                    + (f"  ERROR: {row['error']}" if row["error"] else ""),
                    flush=True,
                )
    return rows, stopped_early


def main() -> int:
    args = parse_args()
    # 1. Load the answer key and pick the questions to run.
    key_path = args.questions
    key = yaml.safe_load(key_path.read_text(encoding="utf-8"))
    questions = [q for q in key["questions"] if not args.only or q["id"] in args.only]
    if not questions:
        print(f"No questions match --only {args.only}", file=sys.stderr)
        return 2

    if args.concurrency < 1:
        print("--concurrency must be at least 1", file=sys.stderr)
        return 2
    if args.context and not args.context.is_file():
        print(f"--context file not found: {args.context}", file=sys.stderr)
        return 2

    # 2. --dry-run: just print the commands and stop.
    if args.dry_run:
        # The real prompt file is written into the run folder, which a dry
        # run doesn't create, so show a placeholder path.
        placeholder = Path("<run folder>/system_prompt.md")
        for q in questions:
            print(
                " ".join(
                    repr(part) if " " in part or not part else part
                    for part in claude_command(q["question"], args, placeholder)
                )
            )
        return 0

    # 3. Stop early with a clear message if a secret is missing.
    missing = [name for name in REQUIRED_ENV if not os.environ.get(name)]
    if missing:
        print(
            f"Missing environment variables: {', '.join(missing)}. "
            "Run via `uv run --env-file secrets/.env.eval ...` (see evals/README.md).",
            file=sys.stderr,
        )
        return 2

    # Stop early if Claude Code is missing or too old for the flags we use.
    version = claude_version()
    if version is None or version < MIN_CLAUDE_VERSION:
        found = ".".join(map(str, version)) if version else "not found"
        needed = ".".join(map(str, MIN_CLAUDE_VERSION))
        print(
            f"Claude Code {needed} or later is required (found: {found}). "
            "Run `claude update`.",
            file=sys.stderr,
        )
        return 2

    # 4. Create this run's folder: evals/runs/<UTC time>_<git sha>/raw/
    git_sha = command_output(["git", "rev-parse", "--short", "HEAD"]) or "nogit"
    started = datetime.now(timezone.utc)
    run_id = f"{started.strftime('%Y%m%dT%H%M%SZ')}_{git_sha}"
    run_dir = EVALS_DIR / "runs" / run_id
    (run_dir / "raw").mkdir(parents=True)
    # The exact instructions every trial gets, kept with the run's logs.
    prompt_path = run_dir / "system_prompt.md"
    prompt_path.write_text(system_prompt(args.context), encoding="utf-8")

    # Columns repeated on every row, so each row stands alone once the
    # logs are loaded somewhere else (e.g. Snowflake) without the manifest.
    base = {
        "run_id": run_id,
        "model": args.model,
        "claude_code_version": command_output(["claude", "--version"]),
        "git_sha": git_sha,
        "answer_key_file": key_path.name,
        "answer_key_sha256": sha256_of(key_path),
        "answer_key_snapshot": key.get("data_snapshot"),
        "prompt_sha256": sha256_of(EVALS_DIR / "prompt.md"),
        "context_file": args.context.name if args.context else None,
        "context_sha256": sha256_of(args.context) if args.context else None,
    }
    manifest = {
        **base,
        "started_at": started.isoformat(),
        "trials_per_question": args.trials,
        "question_ids": [q["id"] for q in questions],
        "max_budget_usd_per_trial": args.max_budget_usd,
        "max_total_usd": args.max_total_usd,
        "concurrency": args.concurrency,
        "mcp_server_url_host": os.environ["SNOWFLAKE_MCP_URL"].split("/")[2],
    }
    manifest_path = run_dir / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )  # written now, completed at the end

    # 5. The main loop: every question x every trial.
    jobs = [(q, t) for q in questions for t in range(1, args.trials + 1)]
    rows, stopped_early = run_jobs(
        jobs,
        lambda q, t: run_trial(q, t, args, run_dir, base, prompt_path),
        run_dir / "results.jsonl",
        args.concurrency,
        args.max_total_usd,
    )

    # 6. Add the summary scores to the manifest and print them.
    manifest.update(
        {
            "ended_at": datetime.now(timezone.utc).isoformat(),
            "stopped_early": stopped_early,
            "summary": summarise(rows, args.trials),
        }
    )
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
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


# Only runs main() when you run this file directly, not when tests import it.
if __name__ == "__main__":
    sys.exit(main())
