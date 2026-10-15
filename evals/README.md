# Football evals

A small, versioned answer key for testing an LLM agent that answers
natural-language questions against the Snowflake gold layer through the
`Football_Snowflake` MCP connector.

## `questions.yaml`

Each entry has the question, an `expected` answer, the `sql` that produced
it, and a `cross_check_sql` written a different way that must agree. Every
query was run through the connector as `CLAUDE_MCP_USER` /
`CLAUDE_MCP_ROLE`, the same read-only grants the agent under test has, so
every answer is reachable within its scope.

The questions are pinned to closed periods (seasons up to 2023/24,
explicit transfer date ranges) so the weekly prod rebuild doesn't quietly
change the expected answers. `data_snapshot` records the data's
`loaded_timestamp` at verification time; if prod has moved past it, re-run
the SQL before trusting a score.

## Grading

The agent's reply must end with `ANSWER: <value>` (or `ANSWER: REFUSE`).

| `answer_type` | Pass when |
|---|---|
| `number` | the absolute difference from `expected` is within `tolerance` |
| `name` | it matches any value in `accept`, case-insensitive |
| `refuse` | the answer is exactly `REFUSE` |

## Authorship

The questions were chosen and reviewed by Tom. The SQL was drafted by
Claude, cross-checked, then reviewed line by line. The agent under test is
the same model family, so the answer key could share its blind spots;
independent cross-checks and human review are the mitigation.

## Data note

The data includes player names (personal data). It's public Transfermarkt
data about public figures, so the risk is low, but it's flagged here per
the repo's review standard.

## Known data defect

`competition_name` isn't unique: `premier-liga` is both Russia's and
Ukraine's league, so `fct_player_performance_per_season_competition`
merges the two, and joining it to `dim_competitions` on name doubles
the rows. No question here depends on it; fixing it changes the fact's
grain and is tracked separately.
