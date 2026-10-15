"""Pure grading functions for the football evals. No Snowflake, no Claude,
no file I/O - everything here takes plain Python values and returns plain
Python values, so it can be unit-tested in isolation (evals/tests/).

Two checks decide whether a trial passes (see evals/README.md):
  - the answer check: does the agent's final `ANSWER:` line match the key?
  - the grounding check: did a query the agent actually ran return that
    value? This catches answers recalled from training data rather than
    read from Snowflake.
"""

import json
import re

ANSWER_LINE = re.compile(r"^\s*ANSWER:\s*(.+?)\s*$", re.IGNORECASE)
# Matches integers and decimals, with optional thousands separators and sign:
# "36", "6.5", "-2", "1,306", "464100000.000".
NUMBER = re.compile(r"-?\d[\d,]*(?:\.\d+)?")
REFUSE = "REFUSE"


def parse_answer(final_text: str | None) -> str | None:
    """Return the value from the last `ANSWER: <value>` line, or None.

    The *last* line wins because the prompt asks for the answer to come
    last; an earlier ANSWER line would be the agent thinking out loud.
    """
    if not final_text:
        return None
    for line in reversed(final_text.splitlines()):
        match = ANSWER_LINE.match(line)
        if match:
            return match.group(1).strip().strip("`*\"'")
    return None


def to_number(text: str) -> float | None:
    """Pull the first number out of an answer like '6.5', '1,306' or
    '36 goals'. Returns None if there's no number at all."""
    match = NUMBER.search(text)
    if not match:
        return None
    return float(match.group(0).replace(",", ""))


def grade_answer(question: dict, parsed: str | None) -> bool:
    """The answer check. `question` is one entry from questions.yaml."""
    if parsed is None:
        return False
    answer_type = question["answer_type"]
    if answer_type == "refuse":
        return parsed.upper() == REFUSE
    if parsed.upper() == REFUSE:
        # Refusing an answerable question is always a fail.
        return False
    if answer_type == "number":
        value = to_number(parsed)
        if value is None:
            return False
        return abs(value - float(question["expected"])) <= float(
            question.get("tolerance", 0)
        )
    if answer_type == "name":
        accepted = question.get("accept") or [question["expected"]]
        return parsed.casefold() in {str(a).casefold() for a in accepted}
    raise ValueError(f"Unknown answer_type: {answer_type!r}")


def extract_sql_calls(events: list[dict], tool_name: str) -> list[dict]:
    """Pair each SQL tool call with its result, from stream-json events.

    In the transcript, the agent's call arrives in an `assistant` event as
    a `tool_use` block (with an id), and Snowflake's reply arrives later in
    a `user` event as a `tool_result` block pointing back at that id. This
    walks the events once and joins the two halves on the id.
    """
    calls: dict[str, dict] = {}
    order: list[str] = []
    for event in events:
        message = event.get("message") or {}
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if block.get("type") == "tool_use" and block.get("name") == tool_name:
                calls[block["id"]] = {
                    "sql": (block.get("input") or {}).get("sql"),
                    "result_text": None,
                    "is_error": None,
                }
                order.append(block["id"])
            elif (
                block.get("type") == "tool_result" and block.get("tool_use_id") in calls
            ):
                call = calls[block["tool_use_id"]]
                call["result_text"] = _flatten_tool_content(block.get("content"))
                call["is_error"] = bool(block.get("is_error"))

    results = []
    for call_id in order:
        call = calls[call_id]
        call.update(_parse_snowflake_result(call["result_text"]))
        results.append(call)
    return results


def _flatten_tool_content(content) -> str:
    """A tool_result's content is either a plain string or a list of
    {"type": "text", "text": ...} blocks. Normalise to one string."""
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    parts = [b.get("text", "") for b in content if isinstance(b, dict)]
    return "\n".join(parts)


def _parse_snowflake_result(text: str | None) -> dict:
    """Snowflake's sql_exec_tool replies with JSON holding `query_id` and
    `result_set.data` (a list of rows). Pull those out for logging. If the
    reply isn't that shape (e.g. an error message), keep what we can."""
    parsed = {"query_id": None, "row_count": None, "rows": None}
    if not text:
        return parsed
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return parsed
    if not isinstance(payload, dict):
        return parsed
    rows = (payload.get("result_set") or {}).get("data")
    parsed["query_id"] = payload.get("query_id")
    if isinstance(rows, list):
        parsed["rows"] = rows
        parsed["row_count"] = len(rows)
    return parsed


def grounding_targets(question: dict) -> list[dict]:
    """The values a grounded answer must have been read from.

    Defaults to the expected answer itself. questions.yaml can list extra
    `grounding` values where the queried value legitimately differs from
    the final answer (A3: the agent may query the raw EUR average and
    convert it to millions itself).
    """
    tolerance = float(question.get("tolerance", 0))
    targets = [{"value": question["expected"], "tolerance": tolerance}]
    for extra in question.get("grounding") or []:
        if isinstance(extra, dict):
            targets.append(
                {"value": extra["value"], "tolerance": float(extra.get("tolerance", 0))}
            )
        else:
            targets.append({"value": extra, "tolerance": tolerance})
    return targets


def is_grounded(question: dict, sql_calls: list[dict]) -> bool | None:
    """The grounding check. Returns None for refusal questions, where there
    is nothing to ground, so they can be told apart from a real failure."""
    if question["answer_type"] == "refuse":
        return None
    for target in grounding_targets(question):
        for call in sql_calls:
            if call.get("is_error"):
                continue
            if _value_in_result(target, question["answer_type"], call.get("rows")):
                return True
    return False


def _value_in_result(target: dict, answer_type: str, rows) -> bool:
    """Does any cell in the returned rows hold the target value?

    Only cell values are searched, not the raw reply text, so a column name
    or the SQL itself can't count as evidence.
    """
    if not rows:
        return False
    cells = [cell for row in rows for cell in (row if isinstance(row, list) else [row])]
    if answer_type == "number":
        want = float(target["value"])
        for cell in cells:
            if cell is None:
                continue
            for match in NUMBER.findall(str(cell)):
                if abs(float(match.replace(",", "")) - want) <= target["tolerance"]:
                    return True
        return False
    want_text = str(target["value"]).casefold()
    return any(cell is not None and want_text in str(cell).casefold() for cell in cells)


def redact(text: str, secrets: list[str]) -> str:
    """Replace every occurrence of each secret with [REDACTED]. Applied to
    every line before it is written to disk, as a backstop: the token is
    only ever in the environment, but logs must never be the place it leaks."""
    for secret in secrets:
        if secret:
            text = text.replace(secret, "[REDACTED]")
    return text
