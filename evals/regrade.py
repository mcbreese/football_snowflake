"""Re-score a finished eval run with the current grader and answer key,
using its saved transcripts. No calls to Claude or Snowflake, so it's free
and takes seconds. Use it when only the grading changed.

Usage (from the repo root):
    uv run python evals/regrade.py evals/runs/<run folder>
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml

# Make `evals.*` importable when this file is run as a script.
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from evals.run_evals import (  # noqa: E402
    EVALS_DIR,
    command_output,
    grade_events,
    parse_events,
    sha256_of,
    summarise,
)


def regrade(run_dir: Path, key_path: Path) -> tuple[list[dict], list[str]]:
    """Return (regraded rows, messages about rows that couldn't be)."""
    key = yaml.safe_load(key_path.read_text(encoding="utf-8"))
    questions = {q["id"]: q for q in key["questions"]}  # id -> question
    rows, notes = [], []
    with (run_dir / "results.jsonl").open(encoding="utf-8") as results:
        for line in results:
            if not line.strip():
                continue
            row = json.loads(line)
            label = f"{row['question_id']} t{row['trial']}"
            question = questions.get(row["question_id"])
            # Runs made on Windows record the path with backslashes.
            raw_path = run_dir / row["raw_file"].replace("\\", "/")
            if question is None:
                notes.append(f"{label}: question no longer in {key_path.name}")
                continue
            if not raw_path.is_file():
                notes.append(f"{label}: transcript {row['raw_file']} not found")
                continue
            # The original row, with every grading column replaced.
            new = {
                **row,
                **grade_events(
                    question, parse_events(raw_path.read_text(encoding="utf-8"))
                ),
            }
            if new["pass"] != row.get("pass"):
                change = "fail -> PASS" if new["pass"] else "PASS -> fail"
                notes.append(f"{label}: {change}")
            rows.append(new)
    return rows, notes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "run_dir", type=Path, help="The run's folder, e.g. evals/runs/<run folder>"
    )
    parser.add_argument(
        "--questions",
        type=Path,
        help="Answer key to grade against (default: the file the run used)",
    )
    args = parser.parse_args()

    manifest = json.loads((args.run_dir / "manifest.json").read_text(encoding="utf-8"))
    # Older runs don't record the file name; they all used questions.yaml.
    key_path = args.questions or EVALS_DIR / manifest.get(
        "answer_key_file", "questions.yaml"
    )
    rows, notes = regrade(args.run_dir, key_path)
    for note in notes:
        print(note)
    if not rows:
        print("Nothing could be regraded, so nothing was written.", file=sys.stderr)
        return 1

    # Written next to the originals, never over them.
    out_path = args.run_dir / "results_regraded.jsonl"
    out_path.write_text(
        "".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8"
    )
    trials = manifest["trials_per_question"]
    summary = summarise(rows, trials)
    (args.run_dir / "regrade.json").write_text(
        json.dumps(
            {
                "regraded_at": datetime.now(timezone.utc).isoformat(),
                "git_sha": command_output(["git", "rev-parse", "--short", "HEAD"]),
                "answer_key_file": key_path.name,
                "answer_key_sha256": sha256_of(key_path),
                "original_summary": manifest.get("summary"),
                "summary": summary,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    old = manifest.get("summary") or {}
    print(
        f"\nRegraded {len(rows)} trials: pass@1 {old.get('pass_at_1', 0):.0%} -> "
        f"{summary['pass_at_1']:.0%}, pass@{trials} "
        f"{old.get(f'pass_at_{trials}', 0):.0%} -> {summary[f'pass_at_{trials}']:.0%}, "
        f"pass^{trials} {old.get(f'pass_hat_{trials}', 0):.0%} -> "
        f"{summary[f'pass_hat_{trials}']:.0%}"
    )
    print(f"Written: {out_path} and regrade.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
