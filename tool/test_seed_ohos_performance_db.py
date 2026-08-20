import contextlib
import importlib.util
import io
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tool" / "ohos-native" / "seed-performance-db.py"


def load_module():
    spec = importlib.util.spec_from_file_location("seed_performance_db", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def create_schema(database: Path) -> None:
    connection = sqlite3.connect(database)
    try:
        connection.executescript(
            """
            PRAGMA foreign_keys = ON;
            PRAGMA user_version = 14;
            CREATE TABLE projects (
              id TEXT PRIMARY KEY NOT NULL,
              name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 120),
              name_key TEXT NOT NULL,
              safe_name_key TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              restore_operation_id TEXT,
              lifecycle_status TEXT NOT NULL DEFAULT 'active'
                CHECK(lifecycle_status IN ('active','completed','archived')),
              is_pinned INTEGER NOT NULL DEFAULT 0 CHECK(is_pinned IN (0,1)),
              watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
              watermark_opacity REAL NOT NULL DEFAULT 0.78,
              watermark_accent_color_argb INTEGER NOT NULL DEFAULT 4281849227,
              watermark_font_scale REAL NOT NULL DEFAULT 1.0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
            CREATE UNIQUE INDEX projects_name_key_idx ON projects(name_key);
            CREATE UNIQUE INDEX projects_safe_name_key_idx ON projects(safe_name_key);
            CREATE TABLE captures (
              id TEXT PRIMARY KEY NOT NULL,
              project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
              photo_number TEXT,
              work_location TEXT NOT NULL CHECK(length(work_location) BETWEEN 1 AND 160),
              work_content TEXT NOT NULL CHECK(length(work_content) BETWEEN 1 AND 240),
              photographer TEXT NOT NULL CHECK(length(photographer) BETWEEN 1 AND 80),
              notes TEXT NOT NULL DEFAULT '',
              original_path TEXT NOT NULL,
              rendered_path TEXT NOT NULL DEFAULT '',
              published_uri TEXT,
              original_sha256 TEXT,
              status TEXT NOT NULL CHECK(status IN ('pendingCamera','captured','rendering','ready','failed')),
              failure_reason TEXT,
              created_at INTEGER NOT NULL,
              captured_at INTEGER,
              latitude REAL,
              longitude REAL,
              accuracy_meters REAL,
              address TEXT,
              location_outcome TEXT,
              processing_attempts INTEGER NOT NULL DEFAULT 0,
              watermark_locale_code TEXT NOT NULL DEFAULT 'zh',
              location_resolution TEXT NOT NULL DEFAULT 'resolved',
              original_deleted_at INTEGER
            );
            """
        )
        connection.commit()
    finally:
        connection.close()


def insert_ready_source(connection: sqlite3.Connection, project_id: str = "source-project") -> None:
    connection.execute(
        """INSERT INTO projects(id,name,name_key,safe_name_key,description,lifecycle_status,is_pinned,
           watermark_position,watermark_opacity,watermark_accent_color_argb,watermark_font_scale,
           created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (project_id, "Source project", project_id, project_id, "", "active", 0,
         "bottomLeft", 0.78, 4281849227, 1.0, 1000, 1000),
    )
    connection.execute(
        """INSERT INTO captures(id,project_id,photo_number,work_location,work_content,photographer,
           notes,original_path,rendered_path,published_uri,original_sha256,status,failure_reason,
           created_at,captured_at,latitude,longitude,accuracy_meters,address,location_outcome,
           processing_attempts,watermark_locale_code,location_resolution,original_deleted_at)
           VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (f"source-ready-{project_id}", project_id, f"SRC-{project_id}", "Source location", "Source content", "Tester",
         "", "/existing/original.jpg", "/existing/rendered.jpg", None, None, "ready", None,
         1000, 1000, None, None, None, None, "resolved", 0, "zh", "resolved", None),
    )
    connection.commit()


def database_snapshot(connection: sqlite3.Connection) -> tuple[object, tuple[tuple[object, ...], ...], tuple[tuple[object, ...], ...]]:
    return (
        connection.execute("PRAGMA user_version").fetchone()[0],
        tuple(connection.execute("SELECT * FROM projects ORDER BY id").fetchall()),
        tuple(connection.execute("SELECT * FROM captures ORDER BY id").fetchall()),
    )


class SeedPerformanceDatabaseTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.database = self.directory / "sitemark_native.db"
        create_schema(self.database)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_refuses_a_database_with_another_basename_without_modifying_it(self) -> None:
        module = load_module()
        wrong_name = self.directory / "not_sitemark_native.db"
        wrong_name.write_bytes(b"do-not-touch")

        with self.assertRaisesRegex(module.DatabaseSafetyError, "basename"):
            module.seed_performance_database(wrong_name, 1)

        self.assertEqual(wrong_name.read_bytes(), b"do-not-touch")

    def test_refuses_a_database_below_a_symbolic_linked_parent_without_modifying_it(self) -> None:
        module = load_module()
        actual_parent = self.directory / "actual"
        actual_parent.mkdir()
        actual_database = actual_parent / "sitemark_native.db"
        create_schema(actual_database)
        connection = sqlite3.connect(actual_database)
        try:
            insert_ready_source(connection)
            before = database_snapshot(connection)
        finally:
            connection.close()

    def test_refuses_parent_traversal_before_path_normalization(self) -> None:
        module = load_module()
        actual_parent = self.directory / "traversal-target"
        actual_parent.mkdir()
        actual_database = actual_parent / "sitemark_native.db"
        create_schema(actual_database)
        connection = sqlite3.connect(actual_database)
        try:
            insert_ready_source(connection)
            before = database_snapshot(connection)
        finally:
            connection.close()
        (self.directory / "traversal-start").mkdir()
        traversal_path = (
            self.directory / "traversal-start" / ".." / "traversal-target" / "sitemark_native.db"
        )

        with self.assertRaisesRegex(module.DatabaseSafetyError, "parent traversal"):
            module.seed_performance_database(traversal_path, 1)

        connection = sqlite3.connect(actual_database)
        try:
            self.assertEqual(database_snapshot(connection), before)
        finally:
            connection.close()
        linked_parent = self.directory / "linked-parent"
        try:
            linked_parent.symlink_to(actual_parent, target_is_directory=True)
        except OSError as error:
            self.skipTest(f"symbolic links unavailable: {error}")

        with self.assertRaisesRegex(module.DatabaseSafetyError, "symbolic link|reparse"):
            module.seed_performance_database(linked_parent / "sitemark_native.db", 1)

        connection = sqlite3.connect(actual_database)
        try:
            self.assertEqual(database_snapshot(connection), before)
        finally:
            connection.close()

    @unittest.skipUnless(os.name == "nt", "junctions are Windows-only")
    def test_refuses_a_database_below_a_windows_junction_when_available(self) -> None:
        module = load_module()
        actual_parent = self.directory / "junction-target"
        actual_parent.mkdir()
        actual_database = actual_parent / "sitemark_native.db"
        create_schema(actual_database)
        connection = sqlite3.connect(actual_database)
        try:
            insert_ready_source(connection)
            before = database_snapshot(connection)
        finally:
            connection.close()
        junction = self.directory / "junction-parent"
        environment = dict(os.environ)
        environment["SEED_TEST_JUNCTION"] = str(junction)
        environment["SEED_TEST_TARGET"] = str(actual_parent)
        result = subprocess.run(
            ["pwsh.exe", "-NoLogo", "-NoProfile", "-Command",
             "New-Item -ItemType Junction -LiteralPath $env:SEED_TEST_JUNCTION -Target $env:SEED_TEST_TARGET | Out-Null"],
            check=False, capture_output=True, text=True, env=environment,
        )
        if result.returncode != 0:
            self.skipTest(f"junction creation unavailable: {result.stderr.strip()}")
        try:
            with self.assertRaisesRegex(module.DatabaseSafetyError, "symbolic link|reparse"):
                module.seed_performance_database(junction / "sitemark_native.db", 1)
            connection = sqlite3.connect(actual_database)
            try:
                self.assertEqual(database_snapshot(connection), before)
            finally:
                connection.close()
        finally:
            junction.rmdir()

    def test_capture_count_is_limited_by_argument_parser_and_seed_function(self) -> None:
        module = load_module()
        self.assertEqual(module.require_positive("1"), 1)
        self.assertEqual(module.require_positive("10000"), 10000)
        for invalid in ("0", "10001"):
            with self.subTest(invalid=invalid):
                with contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit):
                        module.parse_arguments(
                            ["--database", str(self.database), "--captures", invalid]
                        )
        for invalid in (0, 10001):
            with self.subTest(invalid=invalid):
                with self.assertRaisesRegex(module.DatabaseSafetyError, "1..10000"):
                    module.seed_performance_database(self.database, invalid)

    def test_rejects_missing_required_schema_tables_or_columns(self) -> None:
        module = load_module()
        for index, (statement, expected) in enumerate((
            ("DROP TABLE projects", "projects"),
            ("DROP TABLE captures", "captures"),
            ("ALTER TABLE captures RENAME COLUMN rendered_path TO missing_path", "rendered_path"),
        )):
            with self.subTest(expected=expected):
                database = self.directory / f"schema-{index}" / "sitemark_native.db"
                database.parent.mkdir()
                create_schema(database)
                connection = sqlite3.connect(database)
                try:
                    connection.execute(statement)
                    connection.commit()
                finally:
                    connection.close()
                with self.assertRaisesRegex(module.DatabaseSafetyError, expected):
                    module.seed_performance_database(database, 1)

    def test_rejects_when_no_ready_capture_has_a_reusable_image_path(self) -> None:
        module = load_module()
        connection = sqlite3.connect(self.database)
        try:
            insert_ready_source(connection)
            connection.execute(
                "UPDATE captures SET original_path='', rendered_path='' WHERE id='source-ready-source-project'"
            )
            connection.commit()
        finally:
            connection.close()

        with self.assertRaisesRegex(module.DatabaseSafetyError, "拍一张测试照片"):
            module.seed_performance_database(self.database, 1)

    def test_creates_exact_ready_capture_count_with_current_schema_values(self) -> None:
        module = load_module()
        connection = sqlite3.connect(self.database)
        insert_ready_source(connection)
        connection.close()

        summary = module.seed_performance_database(self.database, 2000)

        self.assertEqual(summary["seeded"], 2000)
        self.assertEqual(summary["fixture_project_id"], module.FIXTURE_PROJECT_ID)
        connection = sqlite3.connect(self.database)
        try:
            rows = connection.execute(
                "SELECT id,photo_number,status,original_path,rendered_path,work_location,work_content,photographer "
                "FROM captures WHERE project_id=? ORDER BY id", (module.FIXTURE_PROJECT_ID,)
            ).fetchall()
            self.assertEqual(len(rows), 2000)
            self.assertEqual(len({row[0] for row in rows}), 2000)
            self.assertEqual(len({row[1] for row in rows}), 2000)
            self.assertTrue(all(row[2] == "ready" for row in rows))
            self.assertTrue(all(row[3] == "/existing/rendered.jpg" for row in rows))
            self.assertTrue(all(row[4] == "/existing/rendered.jpg" for row in rows))
            self.assertTrue(all(all(value for value in row[5:]) for row in rows))
        finally:
            connection.close()

    def test_second_run_replaces_fixture_without_affecting_other_project_rows(self) -> None:
        module = load_module()
        connection = sqlite3.connect(self.database)
        insert_ready_source(connection)
        insert_ready_source(connection, "other-project")
        connection.close()

        module.seed_performance_database(self.database, 2000)
        module.seed_performance_database(self.database, 2000)

        connection = sqlite3.connect(self.database)
        try:
            fixture_count = connection.execute(
                "SELECT COUNT(*) FROM captures WHERE project_id=?", (module.FIXTURE_PROJECT_ID,)
            ).fetchone()[0]
            other_project = connection.execute(
                "SELECT name FROM projects WHERE id='other-project'"
            ).fetchone()
            other_count = connection.execute(
                "SELECT COUNT(*) FROM captures WHERE project_id='other-project'"
            ).fetchone()[0]
            self.assertEqual(fixture_count, 2000)
            self.assertEqual(other_project, ("Source project",))
            self.assertEqual(other_count, 1)
        finally:
            connection.close()

    def test_mid_insert_failure_restores_a_complete_snapshot_of_old_fixture_and_other_rows(self) -> None:
        module = load_module()
        connection = sqlite3.connect(self.database)
        try:
            insert_ready_source(connection)
            insert_ready_source(connection, "other-project")
            connection.execute(
                """INSERT INTO projects(id,name,name_key,safe_name_key,description,lifecycle_status,is_pinned,
                   watermark_position,watermark_opacity,watermark_accent_color_argb,watermark_font_scale,
                   created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (module.FIXTURE_PROJECT_ID, "Old fixture", "old fixture", "old-fixture", "old description",
                 "archived", 1, "bottomRight", 0.35, 123, 1.6, 99, 101),
            )
            connection.execute(
                """INSERT INTO captures(id,project_id,photo_number,work_location,work_content,photographer,
                   notes,original_path,rendered_path,published_uri,original_sha256,status,failure_reason,
                   created_at,captured_at,latitude,longitude,accuracy_meters,address,location_outcome,
                   processing_attempts,watermark_locale_code,location_resolution,original_deleted_at)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                ("old-fixture-capture", module.FIXTURE_PROJECT_ID, "OLD-1", "Old location", "Old content",
                 "Old photographer", "old note", "/old/original.jpg", "/old/rendered.jpg", "media://old",
                 "old-sha", "ready", None, 99, 100, 1.25, 2.5, 3.75, "Old address", "manual", 4,
                 "en", "unresolved", 102),
            )
            connection.execute(
                """CREATE TRIGGER abort_second_fixture_capture BEFORE INSERT ON captures
                   WHEN NEW.id = 'sitemark-performance-capture-000002'
                   BEGIN SELECT RAISE(ABORT, 'fixture capture blocked'); END"""
            )
            connection.commit()
            before = database_snapshot(connection)
        finally:
            connection.close()

        with self.assertRaisesRegex(sqlite3.DatabaseError, "fixture capture blocked"):
            module.seed_performance_database(self.database, 3)

        connection = sqlite3.connect(self.database)
        try:
            self.assertEqual(database_snapshot(connection), before)
        finally:
            connection.close()

    def test_cli_checkpoint_leaves_database_reopenable_and_readable(self) -> None:
        connection = sqlite3.connect(self.database)
        try:
            connection.execute("PRAGMA journal_mode=WAL")
            insert_ready_source(connection)
        finally:
            connection.close()

        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--database", str(self.database), "--captures", "2000"],
            check=False, capture_output=True, text=True,
        )
        second_result = subprocess.run(
            [sys.executable, str(SCRIPT), "--database", str(self.database), "--captures", "2000"],
            check=False, capture_output=True, text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(second_result.returncode, 0, second_result.stderr)
        self.assertIn('"seeded": 2000', result.stdout)
        connection = sqlite3.connect(self.database)
        try:
            self.assertEqual(connection.execute("PRAGMA user_version").fetchone()[0], 14)
            self.assertEqual(
                connection.execute(
                    "SELECT COUNT(*) FROM captures WHERE project_id='sitemark-performance-fixture-v1'"
                ).fetchone()[0],
                2000,
            )
            self.assertEqual(
                connection.execute(
                    "SELECT COUNT(*) FROM captures WHERE project_id='source-project'"
                ).fetchone()[0],
                1,
            )
            self.assertEqual(connection.execute("PRAGMA wal_checkpoint(PASSIVE)").fetchone()[0], 0)
        finally:
            connection.close()

    def test_active_wal_reader_reports_committed_data_when_checkpoint_stays_busy(self) -> None:
        module = load_module()
        connection = sqlite3.connect(self.database)
        try:
            self.assertEqual(connection.execute("PRAGMA journal_mode=WAL").fetchone()[0], "wal")
            insert_ready_source(connection)
        finally:
            connection.close()
        reader = sqlite3.connect(self.database)
        try:
            reader.execute("BEGIN")
            reader.execute("SELECT * FROM captures").fetchall()
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--database", str(self.database), "--captures", "2"],
                check=False, capture_output=True, text=True,
            )
        finally:
            reader.rollback()
            reader.close()

        self.assertEqual(result.returncode, 3, result.stderr)
        summary = json.loads(result.stdout)
        self.assertEqual(summary["seeded"], 2)
        self.assertTrue(summary["committed"])
        self.assertEqual(summary["checkpoint"], "busy")
        self.assertIn("data committed", result.stderr)
        connection = sqlite3.connect(self.database)
        try:
            self.assertEqual(
                connection.execute(
                    "SELECT COUNT(*) FROM captures WHERE project_id='sitemark-performance-fixture-v1'"
                ).fetchone()[0],
                2,
            )
        finally:
            connection.close()


if __name__ == "__main__":
    unittest.main()
