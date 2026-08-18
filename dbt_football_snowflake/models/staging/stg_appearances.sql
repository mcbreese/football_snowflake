WITH source
AS (
	select * from {{ source('football_raw', 'raw_appearances') }}
	),

players AS (

	SELECT  *
    FROM {{source('football_raw', 'raw_players')}}

),


appearances
AS (
	SELECT
		-- primary key
		-- we are using a combination of columns to make a unique key, this is a great way to handle source tables without a natural primary key
		{{ dbt_utils.generate_surrogate_key(['appearance_id', 'game_id', 'player_id']) }} as appearance_player_sk,
		-- foreign keys
		appearance_id
		,game_id
		,player_id
		,COALESCE(player_club_id,0) AS player_club_id
		,competition_id
		,
		-- dimensions
		player_name
		,DATE AS appearance_date
		-- facts
		,yellow_cards
		,red_cards
		,goals
		,assists
		,minutes_played
		-- metadata
		,loaded_timestamp
		,source_file
		-- Testing state change by adding comments to the staging model
	FROM source ap
	    -- Got a lot of missing clubs in my fct data - use an exists as skipping dq issue for personal project
	    WHERE {{ exists_in_raw_clubs('COALESCE(ap.player_club_id,0)') }}
		AND EXISTS (SELECT * FROM players pl WHERE ap.player_id = pl.player_id)
	)
SELECT *
FROM appearances