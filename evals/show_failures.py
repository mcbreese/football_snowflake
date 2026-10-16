"""Print every failed trial in an eval run, for reviewing why it failed.

Usage (from the repo root):
    uv run python evals/show_failures.py evals/runs/<run folder>
"""

import argparse
import json
from pathlib import Path

# The fields worth reading when deciding whether a failure is the agent's
# fault or the grader's.
FIELDS = [
    "question_id",
    "trial",
    "parsed_answer",
    "reading",
    "answer_pass",
    "grounded",
    "error",
    "final_answer_raw",
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "run_dir", type=Path, help="The run's folder, e.g. evals/runs/<run folder>"
    )
    parser.add_argument(
        "--all", action="store_true", help="Show every trial, not just failures"
    )
    args = parser.parse_args()

    with (args.run_dir / "results.jsonl").open() as results:
        rows = [json.loads(line) for line in results if line.strip()]

    shown = [r for r in rows if args.all or not r["pass"]]
    for row in shown:
        print("=" * 72)
        for field in FIELDS:
            print(f"{field}: {row.get(field)}")
        # Each SQL the agent ran, with how many rows came back.
        for i, call in enumerate(row.get("sql_calls") or [], start=1):
            print(f"--- sql {i} (rows: {call.get('row_count')}) ---")
            print((call.get("sql") or "").strip())
    print("=" * 72)
    print(f"{len(shown)} of {len(rows)} trials shown")


if __name__ == "__main__":
    main()
