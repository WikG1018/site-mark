"""Seed a disposable SiteMark Native database copy for emulator list-load tests."""

import argparse
import json
import os
import sqlite3
import stat
import sys
from pathlib import Path


EXPECTED_DATABASE_NAME = "sitemark_native.db"
EXPECTED_SCHEMA_VERSION = 14
FIXTURE_PROJECT_ID = "sitemark-performance-fixture-v1"
FIXTURE_PROJECT_NAME = "[PERF FIXTURE] SiteMark Native"
FIXTURE_PROJECT_NAME_KEY = "perf fixture sitemark native"
FIXTURE_PROJECT_SAFE_NAME_KEY = "perf-fixture-sitemark-native"
FIXTURE_TIMESTAMP = 1_700_000_000_000

PROJECT_COLUMNS = {
    "id", "name", "name_key", "safe_name_key", "description", "lifecycle_status",
    "is_pinned", "watermark_position", "watermark_opacity", "watermark_accent_color_argb",
    "watermark_font_scale", "created_at", "updated_at",
}
CAPTURE_COLUMNS = {
    "id", "project_id", "photo_number", "work_location", "work_content", "photographer",
    "notes", "original_path", "rendered_path", "published_uri", "original_sha256", "status",
    "failure_reason", "created_at", "captured_at", "latitude", "longitude", "accuracy_meters",
    "address", "location_outcome", "processing_attempts", "watermark_locale_code",
    "location_resolution", "original_deleted_at",
}


class DatabaseSafetyError(ValueError):
    """Raised when a supplied database is not a safe, compatible fixture target."""


def require_positive(value: str) -> int:
    try:
        captures = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("--captures must be a positive integer") from error
    if captures < 1:
        raise argparse.ArgumentTypeError("--captures must be a positive integer")
    return captures


def validate_database_path(database: Path) -> Path:
    if database.name != EXPECTED_DATABASE_NAME:
        raise DatabaseSafetyError(
            f"database basename must be exactly {EXPECTED_DATABASE_NAME!r}"
        )
    try:
        details = os.lstat(database)
    except FileNotFoundError as error:
        raise DatabaseSafetyError("database must already exist") from error
    if getattr(details, "st_file_attributes", 0) & 0x0400:
        raise DatabaseSafetyError("database must not be a symbolic link or reparse point")
    if not stat.S_ISREG(details.st_mode):
        raise DatabaseSafetyError("database must be an existing regular file")
    return database.resolve()


def database_connection(database: Path) -> sqlite3.Connection:
    return sqlite3.connect(f"{database.as_uri()}?mode=rw", uri=True)


def table_columns(connection: sqlite3.Connection, table_name: str) -> set[str]:
    row = connection.execute(
        "SELECT type FROM sqlite_master WHERE name=?", (table_name,)
    ).fetchone()
    if row is None or row[0] != "table":
        raise DatabaseSafetyError(f"required table {table_name!r} is missing")
    return {row[1] for row in connection.execute(f"PRAGMA table_info({table_name})")}


def validate_schema(connection: sqlite3.Connection) -> None:
    version = connection.execute("PRAGMA user_version").fetchone()[0]
    if version != EXPECTED_SCHEMA_VERSION:
        raise DatabaseSafetyError(
            f"database user_version must be {EXPECTED_SCHEMA_VERSION}, got {version}"
        )
    for table_name, required in (("projects", PROJECT_COLUMNS), ("captures", CAPTURE_COLUMNS)):
        missing = sorted(required - table_columns(connection, table_name))
        if missing:
            raise DatabaseSafetyError(
                f"required {table_name} columns are missing: {', '.join(missing)}"
            )


def reusable_image_path(connection: sqlite3.Connection) -> str:
    row = connection.execute(
        """SELECT rendered_path, original_path FROM captures
           WHERE status='ready' AND project_id<>?
             AND (COALESCE(rendered_path, '')<>'' OR COALESCE(original_path, '')<>'')
           ORDER BY rowid ASC LIMIT 1""",
        (FIXTURE_PROJECT_ID,),
    ).fetchone()
    if row is None:
        raise DatabaseSafetyError(
            "no ready capture has a reusable image path; please take a test photo first (先拍一张测试照片)"
        )
    return row[0] or row[1]


def insert_fixture_project(connection: sqlite3.Connection) -> None:
    connection.execute(
        """INSERT INTO projects(id,name,name_key,safe_name_key,description,lifecycle_status,is_pinned,
           watermark_position,watermark_opacity,watermark_accent_color_argb,watermark_font_scale,
           created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (FIXTURE_PROJECT_ID, FIXTURE_PROJECT_NAME, FIXTURE_PROJECT_NAME_KEY,
         FIXTURE_PROJECT_SAFE_NAME_KEY, "Offline emulator performance fixture.", "active", 0,
         "bottomLeft", 0.78, 4281849227, 1.0, FIXTURE_TIMESTAMP, FIXTURE_TIMESTAMP),
    )


def fixture_capture_rows(image_path: str, captures: int):
    for index in range(1, captures + 1):
        timestamp = FIXTURE_TIMESTAMP + index
        yield (
            f"sitemark-performance-capture-{index:06d}", FIXTURE_PROJECT_ID,
            f"PERF-{index:06d}", "Emulator performance fixture", "Ready capture list load",
            "SiteMark performance tool", "Deterministic offline fixture", image_path, image_path,
            None, None, "ready", None, timestamp, timestamp, None, None, None, None,
            "resolved", 0, "zh", "resolved", None,
        )


def seed_performance_database(database: Path, captures: int) -> dict[str, object]:
    if captures < 1:
        raise DatabaseSafetyError("captures must be a positive integer")
    database = validate_database_path(Path(database))
    connection = database_connection(database)
    try:
        connection.execute("PRAGMA foreign_keys = ON")
        validate_schema(connection)
        image_path = reusable_image_path(connection)
        connection.execute("BEGIN IMMEDIATE")
        try:
            connection.execute("DELETE FROM projects WHERE id=?", (FIXTURE_PROJECT_ID,))
            insert_fixture_project(connection)
            connection.executemany(
                """INSERT INTO captures(id,project_id,photo_number,work_location,work_content,photographer,
                   notes,original_path,rendered_path,published_uri,original_sha256,status,failure_reason,
                   created_at,captured_at,latitude,longitude,accuracy_meters,address,location_outcome,
                   processing_attempts,watermark_locale_code,location_resolution,original_deleted_at)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                fixture_capture_rows(image_path, captures),
            )
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        checkpoint = connection.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        if checkpoint is None or checkpoint[0] != 0:
            raise DatabaseSafetyError("WAL checkpoint did not complete")
    finally:
        connection.close()
    return {
        "seeded": captures,
        "fixture_project_id": FIXTURE_PROJECT_ID,
        "database": str(database),
    }


def parse_arguments(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True, type=Path)
    parser.add_argument("--captures", required=True, type=require_positive)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_arguments(argv)
    try:
        print(json.dumps(seed_performance_database(arguments.database, arguments.captures), ensure_ascii=False))
    except (DatabaseSafetyError, sqlite3.Error, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
