import boto3
from moto import mock_aws

from extraction.extract_kaggle_to_s3 import (
    delete_keys,
    list_existing_keys,
    s3_key_for,
    stale_keys,
    upload_files,
)


def test_s3_key_for_joins_prefix_and_filename():
    assert s3_key_for("raw/football", "clubs.csv") == "raw/football/clubs.csv"


def test_s3_key_for_handles_prefix_with_slashes():
    assert s3_key_for("/raw/football/", "clubs.csv") == "raw/football/clubs.csv"


def test_s3_key_for_handles_empty_prefix():
    assert s3_key_for("", "clubs.csv") == "clubs.csv"


def test_stale_keys_is_existing_minus_uploaded():
    existing = {"raw/clubs.csv", "raw/players.csv", "raw/old_file.csv"}
    uploaded = {"raw/clubs.csv", "raw/players.csv"}
    assert stale_keys(existing, uploaded) == {"raw/old_file.csv"}


def test_stale_keys_empty_when_sets_match():
    keys = {"raw/clubs.csv", "raw/players.csv"}
    assert stale_keys(keys, keys) == set()


@mock_aws
def test_upload_then_prune_leaves_only_new_files(tmp_path):
    bucket = "test-football-bucket"
    prefix = "raw/football"
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket=bucket)

    # Seed the bucket like a previous run had left it: one file the new
    # download no longer produces (stale, should be pruned), one file it
    # produces again with different contents (should just be overwritten).
    s3.put_object(
        Bucket=bucket, Key=f"{prefix}/old_dataset_file.csv", Body=b"stale data"
    )
    s3.put_object(Bucket=bucket, Key=f"{prefix}/clubs.csv", Body=b"old clubs data")

    # newline="" avoids Python's platform-default \n -> \r\n translation on
    # Windows, so the uploaded bytes match exactly what was written here.
    local_dir = tmp_path / "download"
    local_dir.mkdir()
    (local_dir / "clubs.csv").write_text("club_id,name\n1,Test FC\n", newline="")
    (local_dir / "players.csv").write_text(
        "player_id,name\n1,Test Player\n", newline=""
    )

    existing = list_existing_keys(s3, bucket, prefix)
    uploaded = upload_files(s3, bucket, prefix, local_dir, dry_run=False)
    stale = stale_keys(existing, set(uploaded))
    delete_keys(s3, bucket, stale, dry_run=False)

    remaining = list_existing_keys(s3, bucket, prefix)
    assert remaining == {f"{prefix}/clubs.csv", f"{prefix}/players.csv"}

    clubs_body = s3.get_object(Bucket=bucket, Key=f"{prefix}/clubs.csv")["Body"].read()
    assert clubs_body == b"club_id,name\n1,Test FC\n"


@mock_aws
def test_dry_run_does_not_modify_s3(tmp_path):
    bucket = "test-football-bucket"
    prefix = "raw/football"
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket=bucket)
    s3.put_object(
        Bucket=bucket, Key=f"{prefix}/old_dataset_file.csv", Body=b"stale data"
    )

    local_dir = tmp_path / "download"
    local_dir.mkdir()
    (local_dir / "clubs.csv").write_text("club_id,name\n1,Test FC\n")

    existing = list_existing_keys(s3, bucket, prefix)
    uploaded = upload_files(s3, bucket, prefix, local_dir, dry_run=True)
    stale = stale_keys(existing, set(uploaded))
    delete_keys(s3, bucket, stale, dry_run=True)

    assert list_existing_keys(s3, bucket, prefix) == {f"{prefix}/old_dataset_file.csv"}


@mock_aws
def test_non_csv_objects_are_never_listed_or_pruned(tmp_path):
    # Regression test for a real dry-run finding: S3 "folder placeholder"
    # objects (a zero-byte object with a trailing-slash key, e.g. one the
    # console creates via New Folder) aren't CSVs, aren't produced by
    # upload_files, and shouldn't be treated as stale just because they
    # sit under the same prefix.
    bucket = "test-football-bucket"
    prefix = "raw/football"
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket=bucket)
    s3.put_object(Bucket=bucket, Key=f"{prefix}/", Body=b"")
    s3.put_object(Bucket=bucket, Key=f"{prefix}/notes.txt", Body=b"not a csv")

    local_dir = tmp_path / "download"
    local_dir.mkdir()
    (local_dir / "clubs.csv").write_text("club_id,name\n1,Test FC\n", newline="")

    existing = list_existing_keys(s3, bucket, prefix)
    assert existing == set()

    uploaded = upload_files(s3, bucket, prefix, local_dir, dry_run=False)
    stale = stale_keys(existing, set(uploaded))
    delete_keys(s3, bucket, stale, dry_run=False)

    remaining = {
        obj["Key"]
        for obj in s3.list_objects_v2(Bucket=bucket, Prefix=f"{prefix}/")["Contents"]
    }
    assert remaining == {f"{prefix}/", f"{prefix}/notes.txt", f"{prefix}/clubs.csv"}
