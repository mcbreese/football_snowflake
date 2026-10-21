"""Tests for running trials in parallel (run_jobs) and re-scoring saved
transcripts (regrade.py). No Claude or Snowflake calls."""

import json
import threading
import time

from evals import regrade, run_evals


def fake_row(question, trial, cost=0.01):
    return {
        "question_id": question["id"],
        "trial": trial,
        "pass": True,
        "parsed_answer": "1",
        "grounded": True,
        "total_cost_usd": cost,
        "error": None,
    }


def test_run_jobs_runs_in_parallel_and_writes_every_row(tmp_path):
    in_flight, peak = 0, 0
    lock = threading.Lock()

    def run_one(question, trial):
        nonlocal in_flight, peak
        with lock:
            in_flight += 1
            peak = max(peak, in_flight)
        time.sleep(0.05)  # stands in for a slow Claude session
        with lock:
            in_flight -= 1
        return fake_row(question, trial)

    jobs = [({"id": f"Q{i}"}, t) for i in range(4) for t in (1, 2, 3)]
    results = tmp_path / "results.jsonl"
    rows, stopped = run_evals.run_jobs(jobs, run_one, results, 4, 10.0)

    assert stopped is None
    assert peak == 4  # four trials really ran at once
    lines = [json.loads(line) for line in results.read_text().splitlines()]
    assert len(rows) == len(lines) == 12
    assert {(r["question_id"], r["trial"]) for r in lines} == {
        (q["id"], t) for q, t in jobs
    }


def test_run_jobs_stops_starting_trials_at_the_spend_cap(tmp_path):
    jobs = [({"id": "Q"}, t) for t in range(1, 11)]
    rows, stopped = run_evals.run_jobs(
        jobs,
        lambda q, t: fake_row(q, t, cost=1.0),
        tmp_path / "results.jsonl",
        1,
        3.0,
    )
    assert len(rows) == 3
    assert stopped == "max_total_usd 3.0 reached"


def transcript(answer: str, rows) -> str:
    """A saved stream-json transcript: one SQL call, its rows, the answer."""
    reply = json.dumps({"query_id": "01q", "result_set": {"data": rows}})
    events = [
        {
            "type": "assistant",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "id": "t1",
                        "name": run_evals.SQL_TOOL,
                        "input": {"sql": "select competition, goals from ..."},
                    }
                ]
            },
        },
        {
            "type": "user",
            "message": {
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "t1",
                        "content": [{"type": "text", "text": reply}],
                    }
                ]
            },
        },
        {"type": "result", "result": f"ANSWER: {answer}", "total_cost_usd": 0.02},
    ]
    return "\n".join(json.dumps(e) for e in events)


def test_regrade_rescores_saved_transcripts_with_the_current_key(tmp_path):
    run_dir = tmp_path / "run"
    (run_dir / "raw").mkdir(parents=True)
    rows = [["premier-league", 36], ["uefa-champions-league", 12], ["fa-cup", 3]]
    (run_dir / "raw" / "HL1_t1.jsonl").write_text(transcript("51", rows))
    original = {
        "question_id": "HL1",
        "trial": 1,
        "raw_file": "raw/HL1_t1.jsonl",
        "pass": False,  # graded before the all_of fix
        "grounded": False,
        "duration_ms": 1234,  # not a grading column: must survive
    }
    (run_dir / "results.jsonl").write_text(json.dumps(original) + "\n")
    key = tmp_path / "key.yaml"
    key.write_text("""
questions:
  - id: HL1
    answer_type: number
    tolerance: 0
    readings:
      - label: all competitions
        expected: 51
        grounding:
          - all_of: [36, 12, 3]
""")

    regraded, notes = regrade.regrade(run_dir, key)

    assert regraded[0]["pass"] is True
    assert regraded[0]["reading"] == "all competitions"
    assert regraded[0]["duration_ms"] == 1234
    assert notes == ["HL1 t1: fail -> PASS"]


def test_regrade_reports_missing_transcripts(tmp_path):
    run_dir = tmp_path / "run"
    run_dir.mkdir()
    row = {"question_id": "L1", "trial": 1, "raw_file": "raw/L1_t1.jsonl"}
    (run_dir / "results.jsonl").write_text(json.dumps(row) + "\n")
    key = tmp_path / "key.yaml"
    key.write_text("questions:\n  - {id: L1, answer_type: number, expected: 36}\n")

    regraded, notes = regrade.regrade(run_dir, key)

    assert regraded == []
    assert notes == ["L1 t1: transcript raw/L1_t1.jsonl not found"]


def test_regrade_accepts_windows_paths(tmp_path):
    run_dir = tmp_path / "run"
    (run_dir / "raw").mkdir(parents=True)
    (run_dir / "raw" / "L1_t1.jsonl").write_text(transcript("36", [["36"]]))
    row = {"question_id": "L1", "trial": 1, "raw_file": "raw\\L1_t1.jsonl"}
    (run_dir / "results.jsonl").write_text(json.dumps(row) + "\n")
    key = tmp_path / "key.yaml"
    key.write_text("questions:\n  - {id: L1, answer_type: number, expected: 36}\n")

    regraded, _ = regrade.regrade(run_dir, key)

    assert regraded[0]["pass"] is True
