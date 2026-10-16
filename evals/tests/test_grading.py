import json

import pytest

from evals.grading import (
    extract_sql_calls,
    grade_answer,
    is_grounded,
    matched_reading,
    parse_answer,
    redact,
)

TOOL = "mcp__snowflake__sql_exec_tool"

NUMBER_Q = {"answer_type": "number", "expected": 36, "tolerance": 0}
DECIMAL_Q = {
    "answer_type": "number",
    "expected": 6.5,
    "tolerance": 0.05,
    "grounding": [{"value": 6526704, "tolerance": 1}],
}
NAME_Q = {
    "answer_type": "name",
    "expected": "Chelsea Football Club",
    "accept": ["Chelsea", "Chelsea FC", "Chelsea Football Club"],
}
REFUSE_Q = {"answer_type": "refuse", "expected": "REFUSE"}
READINGS_Q = {
    "answer_type": "number",
    "tolerance": 0.05,
    "readings": [
        {"label": "paid only", "expected": 6.5},
        {"label": "free included", "expected": 1.3},
    ],
}


def transcript(sql: str, rows, is_error: bool = False) -> list[dict]:
    """A minimal stream-json transcript: one tool call and its result."""
    reply = json.dumps({"query_id": "01abc", "result_set": {"data": rows}})
    return [
        {"type": "system", "subtype": "init"},
        {
            "type": "assistant",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "id": "t1",
                        "name": TOOL,
                        "input": {"sql": sql},
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
                        "is_error": is_error,
                        "content": [{"type": "text", "text": reply}],
                    }
                ]
            },
        },
    ]


# parse_answer ----------------------------------------------------------


def test_parse_answer_takes_last_answer_line():
    text = "Thinking... ANSWER: 27 maybe?\nChecked again.\nANSWER: 36"
    assert parse_answer(text) == "36"


def test_parse_answer_is_case_insensitive_and_strips_formatting():
    assert parse_answer("answer: **Harry Kane**") == "Harry Kane"


def test_parse_answer_returns_none_without_answer_line():
    assert parse_answer("Haaland scored 36 goals.") is None
    assert parse_answer(None) is None


# grade_answer ----------------------------------------------------------


def test_number_exact_and_with_separators():
    assert grade_answer(NUMBER_Q, "36")
    assert grade_answer({**NUMBER_Q, "expected": 1306}, "1,306")
    assert not grade_answer(NUMBER_Q, "27")


def test_number_tolerance():
    assert grade_answer(DECIMAL_Q, "6.5")
    assert grade_answer(DECIMAL_Q, "6.53 million")
    assert not grade_answer(DECIMAL_Q, "1.3")


def test_name_matches_accepted_variants_case_insensitively():
    assert grade_answer(NAME_Q, "chelsea")
    assert grade_answer(NAME_Q, "Chelsea FC")
    assert not grade_answer(NAME_Q, "Paris Saint-Germain Football Club")


def test_refuse_question_passes_only_on_refuse():
    assert grade_answer(REFUSE_Q, "REFUSE")
    assert grade_answer(REFUSE_Q, "refuse")
    assert not grade_answer(REFUSE_Q, "Bukayo Saka")


def test_refusing_an_answerable_question_fails():
    assert not grade_answer(NUMBER_Q, "REFUSE")


def test_missing_answer_fails():
    assert not grade_answer(NUMBER_Q, None)


def test_any_reading_passes_and_is_identified():
    assert grade_answer(READINGS_Q, "6.5")
    assert grade_answer(READINGS_Q, "1.3")
    assert not grade_answer(READINGS_Q, "1.0")
    assert matched_reading(READINGS_Q, "1.3")["label"] == "free included"
    assert matched_reading(READINGS_Q, "1.0") is None


def test_reading_keeps_shared_fields():
    reading = matched_reading(READINGS_Q, "6.5")
    assert reading["answer_type"] == "number"
    assert reading["tolerance"] == 0.05
    assert "readings" not in reading


# extract_sql_calls -----------------------------------------------------


def test_extract_pairs_call_with_result():
    calls = extract_sql_calls(transcript("select 36", [["36"]]), TOOL)
    assert len(calls) == 1
    assert calls[0]["sql"] == "select 36"
    assert calls[0]["query_id"] == "01abc"
    assert calls[0]["row_count"] == 1


def test_extract_ignores_other_tools():
    events = transcript("select 1", [["1"]])
    events[1]["message"]["content"][0]["name"] = "some_other_tool"
    assert extract_sql_calls(events, TOOL) == []


def test_extract_survives_non_json_result():
    events = transcript("select bad", [])
    events[2]["message"]["content"][0]["content"] = "SQL compilation error"
    calls = extract_sql_calls(events, TOOL)
    assert calls[0]["query_id"] is None
    assert calls[0]["result_text"] == "SQL compilation error"


# is_grounded -----------------------------------------------------------


def test_grounded_when_value_in_returned_rows():
    calls = extract_sql_calls(
        transcript("select ...", [["Erling Haaland", "36"]]), TOOL
    )
    assert is_grounded(NUMBER_Q, calls)


def test_not_grounded_when_no_query_ran():
    assert is_grounded(NUMBER_Q, []) is False


def test_not_grounded_when_value_only_in_sql_text():
    calls = extract_sql_calls(transcript("select 36 as goals", [["27"]]), TOOL)
    assert not is_grounded(NUMBER_Q, calls)


def test_metadata_query_is_not_grounding():
    # Ordinal position 36 is in the rows, but describes structure, not data.
    sql = "select column_name, ordinal_position from information_schema.columns"
    calls = extract_sql_calls(transcript(sql, [["TOTAL_GOALS", "36"]]), TOOL)
    assert not is_grounded(NUMBER_Q, calls)


def test_show_query_is_not_grounding():
    calls = extract_sql_calls(transcript("\n  SHOW TABLES", [["36"]]), TOOL)
    assert not is_grounded(NUMBER_Q, calls)


def test_grounded_via_alternative_value():
    calls = extract_sql_calls(transcript("select avg(fee)", [["6526704.08"]]), TOOL)
    assert is_grounded(DECIMAL_Q, calls)


def test_name_grounding_is_substring_case_insensitive():
    calls = extract_sql_calls(
        transcript("select ...", [["CHELSEA FOOTBALL CLUB", "1"]]), TOOL
    )
    assert is_grounded(NAME_Q, calls)


def test_errored_calls_do_not_count_as_grounding():
    calls = extract_sql_calls(transcript("select 36", [["36"]], is_error=True), TOOL)
    assert not is_grounded(NUMBER_Q, calls)


def test_refusal_questions_have_no_grounding():
    assert is_grounded(REFUSE_Q, []) is None


def test_question_with_readings_grounds_on_any_reading():
    calls = extract_sql_calls(transcript("select avg(fee)", [["1.3"]]), TOOL)
    assert is_grounded(READINGS_Q, calls)


# redact ----------------------------------------------------------------


def test_redact_removes_secret_everywhere():
    line = '{"header": "Bearer abc123", "echo": "abc123"}'
    assert "abc123" not in redact(line, ["abc123"])


@pytest.mark.parametrize("secrets", [[], [""], [None]])
def test_redact_with_no_secret_is_a_no_op(secrets):
    assert redact("unchanged", secrets) == "unchanged"
