"""Seed a disposable SiteMark Native database copy for emulator list-load tests."""

import argparse
from dataclasses import dataclass
import json
import os
import sqlite3
import stat
import sys
import time
from pathlib import Path


EXPECTED_DATABASE_NAME = "sitemark_native.db"
EXPECTED_SCHEMA_VERSION = 14
MAX_CAPTURES = 10_000
CHECKPOINT_BUSY_EXIT_CODE = 3
CHECKPOINT_ATTEMPTS = 3
CHECKPOINT_BUSY_TIMEOUT_MILLISECONDS = 50
REPARSE_POINT_ATTRIBUTE = 0x0400
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


@dataclass(frozen=True)
class DatabaseTarget:
    path: Path
    identity: tuple[int, int, int, int]


def validate_capture_count(captures: int) -> int:
    if isinstance(captures, bool) or not isinstance(captures, int):
        raise DatabaseSafetyError(f"captures must be in range 1..{MAX_CAPTURES}")
    if not 1 <= captures <= MAX_CAPTURES:
        raise DatabaseSafetyError(f"captures must be in range 1..{MAX_CAPTURES}")
    return captures


def require_positive(value: str) -> int:
    try:
        captures = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            f"--captures must be in range 1..{MAX_CAPTURES}"
        ) from error
    try:
        return validate_capture_count(captures)
    except DatabaseSafetyError as error:
        raise argparse.ArgumentTypeError(str(error)) from error


def path_identity(details: os.stat_result) -> tuple[int, int, int, int]:
    return (
        details.st_dev,
        details.st_ino,
        stat.S_IFMT(details.st_mode),
        getattr(details, "st_file_attributes", 0),
    )


def checked_lstat(path: Path) -> os.stat_result:
    try:
        details = os.lstat(path)
    except FileNotFoundError as error:
        raise DatabaseSafetyError("database path must already exist") from error
    if stat.S_ISLNK(details.st_mode) or (
        getattr(details, "st_file_attributes", 0) & REPARSE_POINT_ATTRIBUTE
    ):
        raise DatabaseSafetyError(
            f"database path must not contain a symbolic link or reparse point: {path}"
        )
    return details


def lexical_absolute_path(database: Path) -> Path:
    expanded = os.path.expanduser(os.fspath(database))
    if ".." in Path(expanded).parts:
        raise DatabaseSafetyError("database path must not contain parent traversal")
    return Path(os.path.abspath(expanded))


def inspect_database_path(database: Path) -> DatabaseTarget:
    if database.name != EXPECTED_DATABASE_NAME:
        raise DatabaseSafetyError(
            f"database basename must be exactly {EXPECTED_DATABASE_NAME!r}"
        )
    absolute_path = lexical_absolute_path(database)
    if not absolute_path.anchor:
        raise DatabaseSafetyError("database path must have an absolute filesystem anchor")
    current = Path(absolute_path.anchor)
    root_details = checked_lstat(current)
    if not stat.S_ISDIR(root_details.st_mode):
        raise DatabaseSafetyError("database filesystem anchor must be a directory")
    parts = absolute_path.parts
    for index, part in enumerate(parts[1:], start=1):
        current = current / part
        details = checked_lstat(current)
        if index == len(parts) - 1:
            if not stat.S_ISREG(details.st_mode):
                raise DatabaseSafetyError("database must be an existing regular file")
            return DatabaseTarget(absolute_path, path_identity(details))
        if not stat.S_ISDIR(details.st_mode):
            raise DatabaseSafetyError(f"database parent is not a directory: {current}")
    raise DatabaseSafetyError("database path must name an existing regular file")


def validate_database_path(database: Path) -> DatabaseTarget:
    return inspect_database_path(database)


def verify_database_target(target: DatabaseTarget) -> None:
    current = inspect_database_path(target.path)
    if current.path != target.path or current.identity != target.identity:
        raise DatabaseSafetyError("database path changed during validation")


def database_connection(database: Path) -> sqlite3.Connection:
    return sqlite3.connect(f"{database.as_uri()}?mode=rw", uri=True)


def table_columns(connection: sqlite3.Connection, table_name: str) -> set[str]:
    row = connection.execute(
        "SELECT type FROM sqlite_master WHERE name=?", (table_name,)
    ).fetchone()
    if row is None or row[0] != "table":
        raise DatabaseSafetyError(f"required table {table_name!r} is missing")
    if table_name == "projects":
        info_rows = connection.execute("PRAGMA table_info(projects)")
    elif table_name == "captures":
        info_rows = connection.execute("PRAGMA table_info(captures)")
    else:
        raise DatabaseSafetyError(f"unsupported table {table_name!r}")
    return {row[1] for row in info_rows}


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


def checkpoint_wal(connection: sqlite3.Connection) -> str:
    original_timeout = int(connection.execute("PRAGMA busy_timeout").fetchone()[0])
    connection.execute("PRAGMA busy_timeout=50")
    try:
        for attempt in range(CHECKPOINT_ATTEMPTS):
            try:
                checkpoint = connection.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
            except sqlite3.OperationalError as error:
                if "busy" not in str(error).lower() and "locked" not in str(error).lower():
                    raise
                checkpoint = (1, 0, 0)
            if checkpoint is None:
                raise DatabaseSafetyError("WAL checkpoint returned no status")
            if checkpoint[0] == 0:
                return "complete"
            if attempt + 1 < CHECKPOINT_ATTEMPTS:
                time.sleep(CHECKPOINT_BUSY_TIMEOUT_MILLISECONDS / 1000)
    finally:
        if original_timeout == 0:
            connection.execute("PRAGMA busy_timeout=0")
        elif original_timeout == CHECKPOINT_BUSY_TIMEOUT_MILLISECONDS:
            connection.execute("PRAGMA busy_timeout=50")
        else:
            connection.execute("PRAGMA busy_timeout=0")
    return "busy"


def seed_performance_database(database: Path, captures: int) -> dict[str, object]:
    captures = validate_capture_count(captures)
    target = validate_database_path(Path(database))
    connection = database_connection(target.path)
    try:
        verify_database_target(target)
        connection.execute("PRAGMA foreign_keys = ON")
        validate_schema(connection)
        image_path = reusable_image_path(connection)
        verify_database_target(target)
        connection.execute("BEGIN IMMEDIATE")
        try:
            verify_database_target(target)
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
            verify_database_target(target)
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        checkpoint = checkpoint_wal(connection)
    finally:
        connection.close()
    return {
        "seeded": captures,
        "fixture_project_id": FIXTURE_PROJECT_ID,
        "database": str(target.path),
        "committed": True,
        "checkpoint": checkpoint,
    }


def parse_arguments(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True, type=Path)
    parser.add_argument("--captures", required=True, type=require_positive)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_arguments(argv)
    try:
        summary = seed_performance_database(arguments.database, arguments.captures)
    except (DatabaseSafetyError, sqlite3.Error, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(json.dumps(summary, ensure_ascii=False))
    if summary["checkpoint"] == "busy":
        print("warning: data committed; WAL checkpoint remains busy", file=sys.stderr)
        return CHECKPOINT_BUSY_EXIT_CODE
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
