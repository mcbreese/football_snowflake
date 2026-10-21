## House knowledge about this dataset

These are the conventions and known data problems an analyst on this dataset would tell a new colleague. They describe the data, not any particular question.

### Conventions
- `season` is the year a season starts: 2023 means 2023/24.
- `transfer_fee` is in euros. A fee of 0 is a free transfer. A null fee is unknown (often undisclosed), so it is neither free nor paid.
- `market_value_in_eur` on a transfer is the player's estimated value at the time, not what was paid.
- `transfer_season` labels a transfer window, and a few rows are dated outside it. For a date range, filter on `transfer_date`.

### Known data problems
- **Names aren't unique.** Hundreds of player names belong to more than one player. Look up a person by name, check how many `player_id`s match, and never add different players' figures together.
- **`club_id` in the performance fact is the player's current club,** not the club they played for that season. For a past season's club, use the transfer history (`fct_player_transfers`: `from_club_id`, `to_club_id`, `transfer_date`).
- **Competition names aren't unique.** `premier-liga` is both Russia's and Ukraine's league, and the performance fact can't separate them. Joining that fact to `dim_competitions` on name duplicates rows.
- **Some club ids have no row in `dim_clubs`.** One very common id, which never has a fee or a match, appears to mean "without a club" rather than a real club. Treat an id with no name as not a club.

### When something looks wrong
If you notice a problem that could change your answer, check it with another query before answering. If you can't resolve it, refuse rather than answer with a caveat. Writing "this may be unreliable" and answering anyway counts as a wrong answer.
