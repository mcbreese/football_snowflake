# dbt Review Exceptions

Known, deliberately-accepted deviations for this pipeline. `/dbt-review` should
not re-flag these on future passes — they're already documented at the source
and represent conscious tradeoffs for a solo, Kaggle-snapshot-scale project,
not oversights. Update or remove an entry here if the underlying decision
changes (e.g. the data quality issue gets fixed upstream).

## Missing FK relationship test: `stg_appearances.game_id` → `stg_games`

**File**: `models/staging/stg_appearances.yml`
**What's missing**: `game_id` has `not_null` but no `relationships` test against
`ref('stg_games')`.
**Why accepted**: Source data has appearances referencing games not present in
`raw_games` ("have missing data not yet overcome" per the inline comment).
Adding the test would fail on every run without fixing the underlying gap.
**Revisit when**: The source data quality issue is investigated/resolved, or a
decision is made to filter orphaned appearances the same way `stg_appearances`
and `stg_games` already filter out unknown clubs via `exists_in_raw_clubs`.

## Missing FK relationship tests: `fct_player_transfers.from_club_id` / `to_club_id` → `dim_clubs`

**File**: `models/marts/facts/fct_player_transfers.yml`
**What's missing**: Neither `from_club_id` nor `to_club_id` has a
`relationships` test against `ref('dim_clubs')`.
**Why accepted**: Removed due to a known data issue causing failures against
the dimension ("removed ref to club_id due to data issue with dim" per the
inline comment). Same root cause as the `stg_games`/`stg_appearances` missing
club filtering — some transfers reference clubs not present in `raw_clubs`.
**Revisit when**: The same underlying raw club data gap above is addressed, or
`stg_transfers` gets its own `exists_in_raw_clubs`-style filter to exclude
transfers involving unknown clubs, consistent with how `stg_appearances` and
`stg_games` already handle this.
