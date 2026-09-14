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
    return existing - uploaded


def list_existing_keys(s3_client, bucket: str, prefix: str) -> set[str]:
    # Trailing slash matters here: without it, Prefix="raw" would also
    # match unrelated keys like "raw_archive/file.csv".
    list_prefix = f"{prefix.strip('/')}/" if prefix.strip("/") else ""
    paginator = s3_client.get_paginator("list_objects_v2")
    keys: set[str] = set()
    for page in paginator.paginate(Bucket=bucket, Prefix=list_prefix):
        for obj in page.get("Contents", []):
            # Scoped to .csv only, matching what upload_files ever produces
            # and what load_raw_football_procedure.sql's own cursor looks
            # for (`WHERE RELATIVE_PATH LIKE '%.csv'`). Without this, a
            # zero-byte "folder placeholder" object (e.g. one the S3
            # console creates when you click New Folder) would get flagged
            # stale and deleted on every run - harmless in practice, but
            # not this script's object to manage.
            if obj["Key"].endswith(".csv"):
                keys.add(obj["Key"])
    return keys


def upload_files(
    s3_client, bucket: str, prefix: str, local_dir: Path, dry_run: bool
) -> dict[str, int]:
    """Uploads every CSV under local_dir, returns {s3_key: size_bytes}."""
    uploaded: dict[str, int] = {}
    for csv_path in sorted(local_dir.rglob("*.csv")):
        key = s3_key_for(prefix, csv_path.name)
        size = csv_path.stat().st_size
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
    # DeleteObjects caps at 1000 keys per call - this dataset only has
    # ~10 files, but chunking costs nothing and avoids a silent limit
    # if that ever changes.
    key_list = sorted(keys)
    for i in range(0, len(key_list), 1000):
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

    # Upload first, prune second: if an upload raises partway through, the
    # exception propagates before delete_keys ever runs, so a failed run
    # never leaves the stage with fewer files than it started with.
    uploaded = upload_files(s3_client, bucket, prefix, download_dir, args.dry_run)

    stale = stale_keys(existing, set(uploaded))
    delete_keys(s3_client, bucket, stale, args.dry_run)

    total_bytes = sum(uploaded.values())
    would = "would be " if args.dry_run else ""
    print(
        f"\nSummary: {len(uploaded)} file(s) uploaded ({total_bytes:,} bytes), "
        f"{len(stale)} stale object(s) {would}removed."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
