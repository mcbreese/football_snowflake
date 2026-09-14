# extraction/

Automates the first hop of this project's pipeline: **Kaggle → S3**.

```
Kaggle (davidcariboo/player-scores)
  -> extraction/extract_kaggle_to_s3.py   <- you are here
  -> S3 (football_s3_stage)
  -> Snowflake RAW.FOOTBALL (snowflake/ingestion/load_raw_football_procedure.sql)
  -> dbt staging / intermediate / marts
```

Why a separate folder from `snowflake/ingestion/`: that folder is the **Load**
half of the pipeline (landing zone → warehouse). This one is the **Extract**
half (source system → landing zone). Same pipeline, different verb, different
tooling (Python here, Snowflake Scripting there) — worth keeping them visibly
separate rather than one "ingestion" folder doing both jobs.

This script is **run manually**, on demand, from a developer machine. There is
deliberately no scheduler/cron and no automatic trigger of the Snowflake load
procedure that follows it — that's a separate future discussion, not part of
this.

## What it does

1. Downloads the whole `davidcariboo/player-scores` dataset from Kaggle via
   [`kagglehub`](https://github.com/Kaggle/kagglehub) to a local cache
   directory — every CSV currently in the dataset, not a hardcoded file list,
   so it won't quietly go stale if Kaggle adds or renames a file.
2. Uploads every CSV to `s3://<bucket>/<prefix>/<filename>`, overwriting
   whatever key was already there.
3. Deletes any *`.csv`* object already in that S3 prefix that the new
   download didn't just re-upload — i.e. a file removed from the Kaggle
   dataset since your last run won't linger in S3 forever. Only `.csv` keys
   are ever considered, matching exactly what `load_raw_football_procedure.sql`
   itself looks for (`WHERE RELATIVE_PATH LIKE '%.csv'`) — anything else
   sitting under the prefix (e.g. a zero-byte "folder placeholder" object,
   the kind the S3 console creates when you click *New Folder*) is left
   alone. A first dry run against a bucket that predates this script will
   likely show one of these if you ever created the prefix by hand in the
   console — harmless either way, but the script won't touch it.
4. Prints a summary: files uploaded, bytes, stale objects removed.

Steps 2 and 3 happen in that order — **upload first, prune second** — on
purpose. If the upload step fails partway through (network blip, bad
credentials, whatever), the script raises before it ever gets to deleting
anything, so a failed run can't leave the S3 stage half-empty. That's what
"completely overwrites the bucket" means here in practice: the end state is
the same as wiping it first and re-uploading, without the fragile window
where the stage would otherwise sit empty mid-run.

## One-time setup

You need two credentials, both new — neither exists on this machine yet.

### 1. Kaggle API token

Kaggle account → Settings → API → **Create New Token**. This downloads a
`kaggle.json` containing a username and key. You don't need to install that
file anywhere — this project reads the two values from environment
variables instead (see below).

### 2. AWS IAM user for S3 writes

This is **not** the same credential Snowflake uses. `create_s3_stage.sql`
sets up `STORAGE_AWS_ROLE_ARN` — an IAM *role* that Snowflake's storage
integration *assumes* to *read* the bucket. A local Python script can't
assume that role; it needs its own identity with an access key.

In the AWS Console:

1. IAM → Users → Create user (e.g. `football-extraction-writer`). No console
   access needed — programmatic access only.
2. Attach an inline policy scoped to just this bucket/prefix, nothing wider.
   Replace `<your-bucket>` and `<your-prefix>` with the real values (same
   ones `football_s3_stage`'s `URL` in `create_s3_stage.sql` points at):

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["s3:ListBucket"],
         "Resource": "arn:aws:s3:::<your-bucket>",
         "Condition": {
           "StringLike": { "s3:prefix": "<your-prefix>/*" }
         }
       },
       {
         "Effect": "Allow",
         "Action": ["s3:PutObject", "s3:DeleteObject"],
         "Resource": "arn:aws:s3:::<your-bucket>/<your-prefix>/*"
       }
     ]
   }
   ```

3. Create an access key for that user (IAM → Users → \<user\> → Security
   credentials → Create access key). Save the access key ID and secret —
   AWS only shows the secret once.

If `S3_PREFIX` is left empty, the script's list/prune step operates on the
*whole bucket*, not just this project's slice of it — only do that if the
bucket is dedicated to this pipeline and nothing else.

### 3. Local secrets file

Create `secrets/.env.extraction` (repo root, next to the existing
`secrets/.env.readonly` — `secrets/` is already gitignored, so this file is
never committed):

```
KAGGLE_USERNAME=<from kaggle.json>
KAGGLE_KEY=<from kaggle.json>
AWS_ACCESS_KEY_ID=<from the IAM user above>
AWS_SECRET_ACCESS_KEY=<from the IAM user above>
AWS_DEFAULT_REGION=<the bucket's AWS region, e.g. eu-west-2>
S3_BUCKET=<your-bucket>
S3_PREFIX=<your-prefix>
```

No `export` prefix, unlike `secrets/.env.readonly` elsewhere in this
project — `uv run --env-file` accepts plain `KEY=VALUE` just as well, but
VS Code's own debugger `envFile` loading (see "Debugging" below) does
*not* strip a leading `export`, so a line like `export S3_BUCKET=...`
would set a variable literally named `export S3_BUCKET`, not `S3_BUCKET`,
and the script would fail with "S3_BUCKET is not set" even though the
file is otherwise correct. Plain `KEY=VALUE` works in both places.

`kagglehub` and `boto3` both read their credentials straight from these
environment variables — nothing in the script itself references them by
name except `S3_BUCKET`/`S3_PREFIX`, which aren't a standard AWS convention.

## Running it

From the repo root, using the same `uv run --env-file` pattern already used
for Snowflake credentials elsewhere in this project:

```bash
# Preview what would change, without touching S3
uv run --env-file secrets/.env.extraction python extraction/extract_kaggle_to_s3.py --dry-run

# The real run
uv run --env-file secrets/.env.extraction python extraction/extract_kaggle_to_s3.py
```

Always `--dry-run` first on a bucket you haven't run this against before —
it prints exactly what would be uploaded and deleted with no side effects.

### Debugging in VS Code

`.vscode/launch.json` (local-only, gitignored like `.vscode/settings.json`
— not part of this repo) has an **"Extract Kaggle -> S3 (dry run)"**
config: it loads `secrets/.env.extraction` via `envFile` so credentials
are actually present in the debug session, and hardcodes `--dry-run` so
stepping through the code can't trigger a real S3 write by accident. Set a
breakpoint, then launch that config from the Run and Debug panel — don't
use the plain "Run Python File" button, since that won't load the env
file at all and the script will immediately fail on the missing
`S3_BUCKET` check.

After a successful run, the next manual step is loading S3 into Snowflake
(see `snowflake/ingestion/load_raw_football_procedure.sql`):

```sql
USE WAREHOUSE DEV_LOADING_WH;
CALL RAW.FOOTBALL.LOAD_RAW_FOOTBALL();
```

That step is still manual too — chaining the two together (and putting either
on a schedule) is a deliberately separate future discussion.

## Tests

```bash
uv run pytest extraction/tests
```

Worth noting *why* the tests are shaped the way they are: most of this
script is a thin wrapper around two third-party calls
(`kagglehub.dataset_download`, `boto3`'s S3 client) — testing a thin wrapper
mostly just tests the mock, not real behaviour, so that's not where the
tests are focused. The two things in this script that are actually *logic*,
and therefore worth protecting with a test, are:

- `s3_key_for` — joining a prefix and filename into an S3 key. Easy to get
  subtly wrong (double slashes, a leading slash turning a key absolute).
- `stale_keys` — the diff that decides what gets deleted. Getting this
  wrong is the failure mode that actually matters here: it's a set
  difference, but the *boundary* of that set (which prefix counts as "this
  pipeline's files") is exactly the kind of thing worth pinning down in a
  test rather than trusting by eye.

On top of those, one test exercises the full upload → prune sequence against
an in-memory fake S3 bucket (via [`moto`](https://github.com/getmoto/moto)),
and one confirms `--dry-run` really doesn't mutate anything — both run
offline, no AWS credentials needed, safe to run in CI.
