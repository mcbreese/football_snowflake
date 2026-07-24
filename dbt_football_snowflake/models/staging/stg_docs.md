# Staging Layer Documentation

This file contains documentation blocks for all models and columns in the Staging layer. This is the **Single Source of Truth** for the meaning and type of every data element created in the Staging layer.

***

## Model Descriptions


{% docs stg_appearances_model_description %}
The core facts table capturing a player's participation in a specific game. Data is cleansed, standardised, and links to the `stg_players` and `stg_games` dimension/fact tables.
{% enddocs %}

{% docs stg_clubs_model_description %}
Standardised master data for all football clubs. Includes club statistics, stadium details, and current value information.
{% enddocs %}

{% docs stg_competitions_model_description %}
Master data for all football competitions (leagues, cups, etc.). Provides standardisation for competition names, country, and type.
{% enddocs %}

{% docs stg_games_model_description %}
The central facts table for game results, including final scores, dates, and foreign keys to the participating clubs and the competition.
{% enddocs %}

{% docs stg_player_valuations_model_description %}
Historical snapshot data capturing a player's estimated market value in Euros on a specific date. Used to track value changes over time.
{% enddocs %}

{% docs stg_players_model_description %}
The core dimension table containing master data for all players. Data is standardised for names, physical attributes, and career details.
{% enddocs %}

{% docs stg_transfers_model_description %}
Event data capturing player transfers between clubs, including the transfer date, fee, and the player's market value at the time of the move.
{% enddocs %}

***

## Key/ID Column Definitions

{% docs appearance_player_sk %}
**Surrogate Primary Key (SK).** A unique key for the appearance event, guaranteeing integrity across the warehouse.
{% enddocs %}

{% docs player_valuation_sk %}
**Surrogate Primary Key (SK).** A unique key for the player valuation record.
{% enddocs %}

{% docs player_transfer_sk %}
**Surrogate Primary Key (SK).** A unique key for the player transfer event record.
{% enddocs %}

{% docs player_sk %}
**Surrogate Primary Key (SK).** The unique, hash-derived key for the player dimension record.
{% enddocs %}

{% docs club_sk %}
**Surrogate Primary Key (SK).** The unique, hash-derived key for the club dimension record.
{% enddocs %}

{% docs game_sk %}
**Surrogate Primary Key (SK).** The unique, hash-derived key for the game record.
{% enddocs %}

{% docs competition_sk %}
**Surrogate Primary Key (SK).** The unique, hash-derived key for the competition record.
{% enddocs %}

{% docs player_id %}
**Natural Key (NK) / Foreign Key (FK).** The unique player identifier sourced directly from the raw system.
{% enddocs %}

{% docs club_id %} **Natural Key (NK) / Foreign Key (FK).** The unique club identifier sourced directly from the raw system. {% enddocs %}

{% docs game_id %}
**Natural Key (NK) / Foreign Key (FK).** The unique game identifier.
{% enddocs %}

{% docs competition_id %}
**Natural Key (NK) / Foreign Key (FK).** The unique competition identifier.
{% enddocs %}

{% docs current_club_id %}
**Foreign Key (FK).** The natural key of the club the player was registered with at the time of the valuation or the current club.
{% enddocs %}

{% docs home_club_id %}
**Foreign Key (FK).** The natural key of the club that hosted the game.
{% enddocs %}

{% docs away_club_id %}
**Foreign Key (FK).** The natural key of the club that played the game away from home.
{% enddocs %}

{% docs from_club_id %}
**Foreign Key (FK).** The natural key of the club the player was transferred *from*.
{% enddocs %}

{% docs to_club_id %}
**Foreign Key (FK).** The natural key of the club the player was transferred *to*.
{% enddocs %}

{% docs player_club_id %}
**Foreign Key (FK).** The natural key of the club the player played for during this specific appearance.
{% enddocs %}

{% docs appearance_id %}
The unique natural identifier for a single player appearance event.
{% enddocs %}

***

## Attribute and Measure Definitions

{% docs player_name %}
The full name of the player.
{% enddocs %}

{% docs nationality %}
The player's official nationality.
{% enddocs %}

{% docs position %}
The player's primary field position (e.g., 'Attack', 'Midfield', 'Defence').
{% enddocs %}

{% docs sub_position %}
The player's specific position (e.g., 'Centre-Forward', 'Centre-Back').
{% enddocs %}

{% docs foot %}
The player's preferred foot (e.g., 'left', 'right', 'both').
{% enddocs %}

{% docs height_in_cm %}
The player's height measured in centimeters.
{% enddocs %}

{% docs date_of_birth %}
The player's date of birth, standardised as a DATE type.
{% enddocs %}

{% docs age_in_years %}
The player's age at the time of the latest data snapshot, calculated in years.
{% enddocs %}

{% docs last_season %}
The year of the most recent football season recorded for the entity (player or club).
{% enddocs %}

{% docs domestic_competition_id %}
The ID of the primary domestic league the club participates in.
{% enddocs %}

{% docs name %}
The plain text name of the club or competition.
{% enddocs %}

{% docs total_market_value %}
The total estimated market value of the club's entire squad (often in raw string format before cleaning).
{% enddocs %}

{% docs squad_size %}
The total number of players registered in the club's squad.
{% enddocs %}

{% docs average_age %}
The mean age of the players in the club's squad, calculated in years.
{% enddocs %}

{% docs foreigners_number %}
The count of foreign players in the club's squad.
{% enddocs %}

{% docs foreigners_percentage %}
The percentage of the squad composed of foreign players.
{% enddocs %}

{% docs national_team_players %}
The count of players in the club's squad who are currently part of a senior national team.
{% enddocs %}

{% docs stadium_name %}
The name of the club's home stadium.
{% enddocs %}

{% docs stadium_seats %}
The official seating capacity of the club's home stadium.
{% enddocs %}

{% docs net_transfer_record %}
The club's financial balance regarding transfers (transfers received minus transfers spent).
{% enddocs %}

{% docs coach_name %}
The name of the club's head coach.
{% enddocs %}

{% docs url %}
The source URL from Transfermarkt or similar site where the raw data was collected.
{% enddocs %}

{% docs country_id %}
The identifier for the country associated with the competition.
{% enddocs %}

{% docs domestic_league_code %}
The standardised three or four-letter code for the domestic league.
{% enddocs %}

{% docs type %}
The classification of the competition (e.g., 'league', 'cup').
{% enddocs %}

{% docs sub_type %}
A secondary classification for the competition (e.g., 'first tier').
{% enddocs %}

{% docs country_name %}
The full name of the country associated with the competition.
{% enddocs %}

{% docs confederation %}
The regional football confederation the competition belongs to (e.g., 'UEFA', 'CONMEBOL').
{% enddocs %}

{% docs is_major_national_league %}
Boolean flag indicating if the competition is considered a major national league.
{% enddocs %}

{% docs season %}
The year of the game's corresponding football season.
{% enddocs %}

{% docs home_club_goals %}
The number of goals scored by the home club.
{% enddocs %}

{% docs away_club_goals %}
The number of goals scored by the away club.
{% enddocs %}

{% docs yellow_cards %}
The count of yellow cards received by the player during the appearance.
{% enddocs %}

{% docs red_cards %}
The count of red cards received by the player during the appearance.
{% enddocs %}

{% docs goals %}
The number of goals scored by the player during the appearance.
{% enddocs %}

{% docs assists %}
The number of assists recorded by the player during the appearance.
{% enddocs %}

{% docs minutes_played %}
The total minutes the player was on the field during the appearance.
{% enddocs %}

{% docs market_value_in_eur %}
The player's market value, standardised and converted into Euros (€).
{% enddocs %}

{% docs transfer_date %}
The date the transfer officially occurred.
{% enddocs %}

{% docs transfer_season %}
The specific transfer window/season (e.g., 'summer 2023') when the transfer occurred.
{% enddocs %}

{% docs transfer_fee %}
The official fee paid for the transfer, standardised in Euros (€).
{% enddocs %}

{% docs valuation_date %}
The date the corresponding market value assessment was made.
{% enddocs %}

{% docs appearance_date %}
The date on which the appearance event occurred.
{% enddocs %}

{% docs game_date %}
The date on which the game was played, standardised as a DATE type.
{% enddocs %}

***

## Audit/Lineage Definitions

{% docs loaded_timestamp %}
The timestamp indicating when the record was loaded into the raw source table (data lineage/audit column).
{% enddocs %}

{% docs source_file %}
The name or path of the raw file from which the record was extracted (data lineage/audit column).
{% enddocs %}