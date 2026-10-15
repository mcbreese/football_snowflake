"""End-to-end test of one trial with a fake `claude` binary on PATH, so
the whole pipeline (subprocess, raw log, parsing, grading, redaction) runs
without calling Claude or Snowflake."""

import json
import stat
from argparse import Namespace

from evals import run_evals

SECRET = "pat-secret-value"


def fake_claude(tmp_path, final_text: str, rows):
    """Write a script named `claude` that prints a canned stream-json
    transcript, including the secret, to prove it gets redacted."""
    reply = json.dumps({"query_id": "01q", "result_set": {"data": rows}})
    events = [
        {
            "type": "system",
            "subtype": "init",
            "session_id": "s1",
            "mcp_servers": [{"name": "snowflake", "status": "connected"}],
            "debug_header": f"Bearer {SECRET}",
        },
        {
            "type": "assistant",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "id": "t1",
                        "name": run_evals.SQL_TOOL,
                        "input": {"sql": "select total_goals from ..."},
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
        {
            "type": "result",
            "subtype": "success",
            "is_error": False,
            "result": final_text,
            "session_id": "s1",
            "num_turns": 2,
            "total_cost_usd": 0.0123,
            "usage": {"input_tokens": 100, "output_tokens": 20},
        },
    ]
    script = tmp_path / "bin" / "claude"
    script.parent.mkdir()
    lines = "\n".join(json.dumps(e) for e in events)
    script.write_text(f"#!/bin/sh\ncat <<'EOF'\n{lines}\nEOF\n")
    script.chmod(script.stat().st_mode | stat.S_IEXEC)
    return script.parent


def run_one(tmp_path, monkeypatch, final_text, rows):
    bin_dir = fake_claude(tmp_path, final_text, rows)
    monkeypatch.setenv("PATH", f"{bin_dir}:{__import__('os').environ['PATH']}")
    monkeypatch.setenv("SNOWFLAKE_MCP_PAT", SECRET)
    run_dir = tmp_path / "run"
    (run_dir / "raw").mkdir(parents=True)
    question = {
        "id": "L1",
        "question": "How many?",
        "answer_type": "number",
        "expected": 36,
        "tolerance": 0,
    }
    args = Namespace(model="m", max_budget_usd=0.5, timeout=30)
    row = run_evals.run_trial(question, 1, args, run_dir, {"run_id": "r"})
    return row, run_dir


def test_grounded_correct_answer_passes(tmp_path, monkeypatch):
    row, _ = run_one(tmp_path, monkeypatch, "Found it.\nANSWER: 36", [["36"]])
    assert row["pass"] and row["answer_pass"] and row["grounded"]
    assert row["sql_calls"][0]["query_id"] == "01q"
    assert row["total_cost_usd"] == 0.0123
    assert row["error"] is None


def test_correct_but_ungrounded_answer_fails(tmp_path, monkeypatch):
    row, _ = run_one(tmp_path, monkeypatch, "ANSWER: 36", [["27"]])
    assert row["answer_pass"] is True
    assert row["grounded"] is False
    assert row["pass"] is False


def test_secret_never_reaches_disk(tmp_path, monkeypatch):
    row, run_dir = run_one(tmp_path, monkeypatch, "ANSWER: 36", [["36"]])
    for path in run_dir.rglob("*"):
        if path.is_file():
            assert SECRET not in path.read_text()
    assert SECRET not in json.dumps(row)


def test_summary_scores():
    rows = [
        {
            "question_id": "A",
            "pass": True,
            "answer_pass": True,
            "grounded": True,
            "total_cost_usd": 0.01,
            "error": None,
        },
        {
            "question_id": "A",
            "pass": False,
            "answer_pass": True,
            "grounded": False,
            "total_cost_usd": 0.01,
            "error": None,
        },
        {
            "question_id": "B",
            "pass": True,
            "answer_pass": True,
            "grounded": None,
            "total_cost_usd": 0.02,
            "error": None,
        },
        {
            "question_id": "B",
            "pass": True,
            "answer_pass": True,
            "grounded": None,
            "total_cost_usd": 0.02,
            "error": None,
        },
    ]
    summary = run_evals.summarise(rows, trials=2)
    assert summary["pass_at_1"] == 0.75
    assert summary["answer_only_pass_at_1"] == 1.0
    assert summary["pass_at_2"] == 1.0  # both questions passed at least once
    assert summary["pass_hat_2"] == 0.5  # only B passed every trial
    assert summary["total_cost_usd"] == 0.06
