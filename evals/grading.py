"""Pure grading functions for the football evals. No Snowflake, no Claude,
no file I/O - everything here takes plain Python values and returns plain
Python values, so it can be unit-tested in isolation (evals/tests/).

Two checks decide whether a trial passes (see evals/README.md):
  - the answer check: does the agent's final `ANSWER:` line match the key?
  - the grounding check: did a query the agent actually ran return that
    value? This catches answers recalled from training data rather than
    read from Snowflake.
"""

import json  # turns JSON text into Python dicts/lists
import re  # regular expressions: pattern matching on text

# A line that starts with "ANSWER:" (any case); (.+?) captures what follows.
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
    if not final_text:  # no reply at all (None or empty string)
        return None
    for line in reversed(final_text.splitlines()):  # split into lines, read bottom-up
        match = ANSWER_LINE.match(line)  # does this line start with ANSWER:?
        if match:
            # group(1) = the captured value; strip spaces, then ` * " ' formatting
            return match.group(1).strip().strip("`*\"'")
    return None  # looped through every line, no ANSWER: found


def to_number(text: str) -> float | None:
    """Pull the first number out of an answer like '6.5', '1,306' or
    '36 goals'. Returns None if there's no number at all."""
    match = NUMBER.search(text)  # search = anywhere in the text, not just the start
    if not match:
        return None
    return float(match.group(0).replace(",", ""))  # "1,306" -> 1306.0


def readings(question: dict) -> list[dict]:
    """Every accepted reading of a question, each shaped like a question.

    Most questions have one answer, so they are their own only reading.
    A question with a `readings:` list (an ambiguous question with more
    than one defensible answer) gets one entry per reading, each combined
    with the question's shared fields like `answer_type`.
    """
    if "readings" not in question:
        return [question]
    shared = {k: v for k, v in question.items() if k != "readings"}
    # {**a, **b} merges two dicts; b's values win where both have a key
    return [{**shared, **reading} for reading in question["readings"]]


def matched_reading(question: dict, parsed: str | None) -> dict | None:
    """The first reading the answer matches, or None if it matches none."""
    for reading in readings(question):
        if _grade_one(reading, parsed):
            return reading
    return None


def accepted_refusal(question: dict, parsed: str | None) -> bool:
    """Is this a refusal the question allows? `accept_refuse: true` marks
    questions where refusing is as fair as answering, such as a name shared
    by several players, where picking one would need outside knowledge."""
    return (
        bool(question.get("accept_refuse"))
        and parsed is not None
        and parsed.upper() == REFUSE
    )


def grade_answer(question: dict, parsed: str | None) -> bool:
    """The answer check: does the answer match any accepted reading (or is
    it an allowed refusal)? `question` is one entry from a questions file."""
    if accepted_refusal(question, parsed):
        return True
    return matched_reading(question, parsed) is not None


def _grade_one(question: dict, parsed: str | None) -> bool:
    """Check the answer against a single reading."""
    if parsed is None:  # agent gave no ANSWER: line -> fail
        return False
    answer_type = question["answer_type"]  # "number", "name" or "refuse"
    if answer_type == "refuse":
        return parsed.upper() == REFUSE  # pass only if it refused
    if parsed.upper() == REFUSE:
        # Refusing an answerable question is always a fail.
        return False
    if answer_type == "number":
        value = to_number(parsed)
        if value is None:  # e.g. "Harry Kane" given for a number question
            return False
        # pass if |agent - expected| <= tolerance (0 means exact)
        return abs(value - float(question["expected"])) <= float(
            question.get("tolerance", 0)  # .get(key, default): 0 if not in the YAML
        )
    if answer_type == "name":
        # list of accepted spellings; fall back to the expected value alone
        accepted = question.get("accept") or [question["expected"]]
        # casefold = lowercase for comparison; {...} builds a set to check membership
        return parsed.casefold() in {str(a).casefold() for a in accepted}
    raise ValueError(f"Unknown answer_type: {answer_type!r}")  # typo in the YAML


def extract_sql_calls(events: list[dict], tool_name: str) -> list[dict]:
    """Pair each SQL tool call with its result, from stream-json events.

    In the transcript, the agent's call arrives in an `assistant` event as
    a `tool_use` block (with an id), and Snowflake's reply arrives later in
    a `user` event as a `tool_result` block pointing back at that id. This
    walks the events once and joins the two halves on the id.
    """
    calls: dict[str, dict] = {}  # tool call id -> details (like a lookup table)
    order: list[str] = []  # ids in the order the agent made the calls
    for event in events:  # each event = one line of the transcript
        message = event.get("message") or {}  # {} if the event has no message
        content = message.get("content")
        if not isinstance(content, list):  # only list-shaped content holds tool blocks
            continue  # skip to the next event
        for block in content:
            # The agent asking to run SQL: remember the SQL against its id
            if block.get("type") == "tool_use" and block.get("name") == tool_name:
                calls[block["id"]] = {
                    "sql": (block.get("input") or {}).get("sql"),
                    "result_text": None,  # filled in when the reply arrives
                    "is_error": None,
                }
                order.append(block["id"])
            # Snowflake's reply: attach it to the matching call (the "join")
            elif (
                block.get("type") == "tool_result" and block.get("tool_use_id") in calls
            ):
                call = calls[block["tool_use_id"]]
                call["result_text"] = _flatten_tool_content(block.get("content"))
                call["is_error"] = bool(block.get("is_error"))

    results = []
    for call_id in order:
        call = calls[call_id]
        call.update(_parse_snowflake_result(call["result_text"]))  # add query_id, rows
        results.append(call)
    return results


def _flatten_tool_content(content) -> str:
    """A tool_result's content is either a plain string or a list of
    {"type": "text", "text": ...} blocks. Normalise to one string."""
    if content is None:
        return ""
    if isinstance(content, str):  # already a string: use as is
        return content
    # list comprehension: take the "text" from each block that is a dict
    parts = [b.get("text", "") for b in content if isinstance(b, dict)]
    return "\n".join(parts)  # glue them together with newlines


def _parse_snowflake_result(text: str | None) -> dict:
    """Snowflake's sql_exec_tool replies with JSON holding `query_id` and
    `result_set.data` (a list of rows). Pull those out for logging. If the
    reply isn't that shape (e.g. an error message), keep what we can."""
    parsed = {"query_id": None, "row_count": None, "rows": None}  # defaults
    if not text:
        return parsed
    try:
        payload = json.loads(text)  # text -> dict
    except json.JSONDecodeError:  # not JSON (e.g. "SQL compilation error")
        return parsed  # keep the defaults rather than crash
    if not isinstance(payload, dict):
        return parsed
    rows = (payload.get("result_set") or {}).get(
        "data"
    )  # payload["result_set"]["data"], or None if missing
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

    A `grounding` entry written as `{all_of: [36, 12, 3]}` is for an answer
    the agent adds up itself (51 = 36 + 12 + 3): it counts only if every
    one of those values was returned.

    For a question with several readings, this covers every reading. Pass
    a single reading instead to ground only that one.
    """
    targets = []
    for reading in readings(question):
        tolerance = float(reading.get("tolerance", 0))
        targets.append({"value": reading["expected"], "tolerance": tolerance})
        for extra in reading.get("grounding") or []:  # [] if there are none
            if isinstance(extra, dict) and "all_of" in extra:  # {all_of: [...]}
                targets.append(
                    {
                        "all_of": extra["all_of"],
                        "tolerance": float(extra.get("tolerance", tolerance)),
                    }
                )
            elif isinstance(extra, dict):  # written as {value: ..., tolerance: ...}
                targets.append(
                    {
                        "value": extra["value"],
                        "tolerance": float(extra.get("tolerance", 0)),
                    }
                )
            else:  # written as a bare value
                targets.append({"value": extra, "tolerance": tolerance})
    return targets


def is_grounded(question: dict, sql_calls: list[dict]) -> bool | None:
    """The grounding check. Returns None for refusal questions, where there
    is nothing to ground, so they can be told apart from a real failure."""
    if question["answer_type"] == "refuse":
        return None
    evidence = [call for call in sql_calls if _is_evidence(call)]
    answer_type = question["answer_type"]
    for target in grounding_targets(question):  # each acceptable value
        if "all_of" in target:
            # Every part must appear somewhere in what came back.
            parts = [
                {"value": v, "tolerance": target["tolerance"]} for v in target["all_of"]
            ]
            if all(
                any(
                    _value_in_result(part, answer_type, c.get("rows")) for c in evidence
                )
                for part in parts
            ):
                return True
        elif any(
            _value_in_result(target, answer_type, c.get("rows")) for c in evidence
        ):
            return True  # found it: stop looking
    return False  # checked everything, value never appeared in any result


def _is_evidence(call: dict) -> bool:
    """Can this query's rows count as evidence for an answer?"""
    if call.get("is_error"):  # failed queries don't count as evidence
        return False
    sql = (call.get("sql") or "").lower().strip()
    if sql.startswith(("show", "desc")) or "information_schema" in sql:
        return False  # metadata queries don't count as evidence
    return True


def _value_in_result(target: dict, answer_type: str, rows) -> bool:
    """Does any cell in the returned rows hold the target value?

    Only cell values are searched, not the raw reply text, so a column name
    or the SQL itself can't count as evidence.
    """
    if not rows:  # query returned nothing
        return False
    # Flatten rows into one list of cells: [[a, b], [c]] -> [a, b, c]
    cells = [cell for row in rows for cell in (row if isinstance(row, list) else [row])]
    if answer_type == "number":
        want = float(target["value"])
        for cell in cells:
            if cell is None:  # empty cell
                continue
            for match in NUMBER.findall(str(cell)):  # every number in the cell
                if abs(float(match.replace(",", "")) - want) <= target["tolerance"]:
                    return True
        return False
    # Names: case-insensitive "contains" check
    want_text = str(target["value"]).casefold()
    # any(...) = True if at least one cell matches
    return any(cell is not None and want_text in str(cell).casefold() for cell in cells)


def redact(text: str, secrets: list[str]) -> str:
    """Replace every occurrence of each secret with [REDACTED]. Applied to
    every line before it is written to disk, as a backstop: the token is
    only ever in the environment, but logs must never be the place it leaks."""
    for secret in secrets:
        if secret:  # skip None / empty, e.g. a variable that isn't set
            text = text.replace(secret, "[REDACTED]")
    return text
