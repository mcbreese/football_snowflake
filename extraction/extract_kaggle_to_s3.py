"""Download the Transfermarkt Kaggle dataset and completely overwrite the
S3 location that football_s3_stage reads from (see
snowflake/ingestion/create_s3_stage.sql). Manual invocation only, no
incremental/dedup logic - matches the full-replace philosophy already used
by load_raw_football_procedure.sql. See extraction/README.md for setup.

Usage (from the repo root):
    uv run --env-file secrets/.env.extraction python extraction/extract_kaggle_to_s3.py [--dry-run]
"""

import argparse
import os
import sys
from pathlib import Path

import boto3
import kagglehub

DATASET = "davidcariboo/player-scores"


def s3_key_for(prefix: str, filename: str) -> str:
    prefix = prefix.strip("/")
    return f"{prefix}/{filename}" if prefix else filename


def stale_keys(existing: set[str], uploaded: set[str]) -> set[str]:
    return existing - uploaded  # everything in existing, minus everything in uploaded


def list_existing_keys(s3_client, bucket: str, prefix: str) -> set[str]:
    # trailing slash so Prefix="raw" doesn't also match "raw_archive/..."
    list_prefix = f"{prefix.strip('/')}/" if prefix.strip("/") else ""
    paginator = s3_client.get_paginator(
        "list_objects_v2"
    )  # handles S3's 1000-per-page cap
    keys: set[str] = set()
    for page in paginator.paginate(Bucket=bucket, Prefix=list_prefix):
        for obj in page.get(
            "Contents", []
        ):  # "Contents" key is absent (not []) when empty
            # .csv only - matches load_raw_football_procedure.sql's own filter, so
            # folder-placeholder objects etc. under this prefix are never touched
            if obj["Key"].endswith(".csv"):
                keys.add(obj["Key"])
    return keys


def upload_files(
    s3_client, bucket: str, prefix: str, local_dir: Path, dry_run: bool
) -> dict[str, int]:
    """Uploads every CSV under local_dir, returns {s3_key: size_bytes}."""
    uploaded: dict[str, int] = {}
    for csv_path in sorted(local_dir.rglob("*.csv")):
        size = csv_path.stat().st_size
        if size == 0:
            # Fail loud before uploading anything - propagates up and skips
            # delete_keys entirely, same safety net as any other error here.
            raise ValueError(
                f"{csv_path.name} downloaded as 0 bytes - refusing to upload it"
            )
        key = s3_key_for(prefix, csv_path.name)
        if dry_run:
            print(
                f"[dry-run] would upload {csv_path.name} -> s3://{bucket}/{key} ({size:,} bytes)"
            )
        else:
            s3_client.upload_file(str(csv_path), bucket, key)
            print(f"uploaded {csv_path.name} -> s3://{bucket}/{key} ({size:,} bytes)")
        uploaded[key] = size
    return uploaded


def delete_keys(s3_client, bucket: str, keys: set[str], dry_run: bool) -> None:
    if not keys:
        return
    if dry_run:
        for key in sorted(keys):
            print(f"[dry-run] would delete stale s3://{bucket}/{key}")
        return
    key_list = sorted(keys)
    for i in range(0, len(key_list), 1000):  # DeleteObjects caps at 1000 keys/call
        chunk = key_list[i : i + 1000]
        s3_client.delete_objects(
            Bucket=bucket,
            Delete={"Objects": [{"Key": key} for key in chunk]},
        )
        for key in chunk:
            print(f"deleted stale s3://{bucket}/{key}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be uploaded/deleted without touching S3.",
    )
    args = parser.parse_args()

    bucket = os.environ.get("S3_BUCKET")
    if not bucket:
        print(
            "S3_BUCKET is not set - see extraction/README.md for secrets/.env.extraction setup.",
            file=sys.stderr,
        )
        return 1
    prefix = os.environ.get("S3_PREFIX", "")

    print(f"Downloading '{DATASET}' from Kaggle...")
    download_dir = Path(kagglehub.dataset_download(DATASET))
    print(f"Downloaded to {download_dir}")

    s3_client = boto3.client("s3")

    existing = list_existing_keys(s3_client, bucket, prefix)
    print(f"{len(existing)} object(s) currently in s3://{bucket}/{prefix}")

    # upload first, prune second: an exception here skips delete_keys entirely, so
    # a failed run never leaves the stage with fewer files than it started with
    uploaded = upload_files(s3_client, bucket, prefix, download_dir, args.dry_run)

    if not uploaded:
        # zero files is never valid for this dataset - without this check,
        # stale_keys below would treat every existing object as stale and wipe them all
        print(
            f"No CSV files found in the Kaggle download ({download_dir}) - "
            "aborting without touching S3.",
            file=sys.stderr,
        )
        return 1

    stale = stale_keys(existing, set(uploaded))  # set(dict) walks its keys
    delete_keys(s3_client, bucket, stale, args.dry_run)

    total_bytes = sum(uploaded.values())
    would = "would be " if args.dry_run else ""
    print(
        f"\nSummary: {len(uploaded)} file(s) uploaded ({total_bytes:,} bytes), "
        f"{len(stale)} stale object(s) {would}removed."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())  # turns main()'s return value into the process exit code
