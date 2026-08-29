import re
import sqlite3
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATABASE_SOURCE = ROOT / "ohos-native/entry/src/main/ets/data/database/AppDatabase.ets"
RECORD_SOURCE = ROOT / "ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets"


def source() -> str:
    return DATABASE_SOURCE.read_text(encoding="utf-8")


def method_body(name: str) -> str:
    text = source()
    match = re.search(rf"async {name}\([^{{]+\{{(.*?)(?=\n  async |\n}}\n)", text, re.S)
    if not match:
        raise AssertionError(f"method not found: {name}")
    return match.group(1)


def trigger_sql() -> list[str]:
    return re.findall(r"`(CREATE TRIGGER IF NOT EXISTS captures_fields_validate_.*?END)`", source(), re.S)


def database() -> sqlite3.Connection:
    connection = sqlite3.connect(":memory:")
    connection.executescript(
        """
        CREATE TABLE projects(id TEXT PRIMARY KEY, lifecycle_status TEXT NOT NULL);
        CREATE TABLE captures(
          id TEXT PRIMARY KEY, project_id TEXT, work_location TEXT, work_content TEXT,
          photographer TEXT, notes TEXT, status TEXT, original_path TEXT,
          original_deleted_at INTEGER, captured_at INTEGER, created_at INTEGER);
        CREATE TABLE capture_templates(
          id TEXT PRIMARY KEY, project_id TEXT, name TEXT, name_key TEXT,
          work_location TEXT, work_content TEXT, photographer TEXT,
          created_at INTEGER, updated_at INTEGER, UNIQUE(project_id,name_key));
        """
    )
    return connection


def install_capture_guards(connection: sqlite3.Connection) -> None:
    for statement in trigger_sql():
        connection.execute(statement)


class HarmonyCaptureDatabaseContractTest(unittest.TestCase):
    def test_capture_guards_install_on_new_database(self) -> None:
        db = database()
        install_capture_guards(db)
        db.execute(
            "INSERT INTO captures VALUES(?,?,?,?,?,?,?,?,?,?,?)",
            ("valid", "p", " A ", " 巡检 ", " 王工 ", "", "ready", "/a", None, 1, 1),
        )
        with self.assertRaises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO captures VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                ("blank", "p", " ", "巡检", "王工", "", "ready", "/b", None, 2, 2),
            )

    def test_capture_guards_install_on_existing_database_and_reject_invalid_writes(self) -> None:
        db = database()
        db.execute(
            "INSERT INTO captures VALUES(?,?,?,?,?,?,?,?,?,?,?)",
            ("legacy", "p", "A", "巡检", "王工", "", "ready", "/a", None, 1, 1),
        )
        self.assertEqual(len(trigger_sql()), 2)
        install_capture_guards(db)
        with self.assertRaises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO captures VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                ("bad", "p", "A\0B", "巡检", "王工", "", "ready", "/b", None, 2, 2),
            )
        with self.assertRaises(sqlite3.IntegrityError):
            db.execute("UPDATE captures SET work_content=? WHERE id='legacy'", ("   ",))
        db.execute("UPDATE captures SET work_location=? WHERE id='legacy'", ("😀" * 160,))
        with self.assertRaises(sqlite3.IntegrityError):
            db.execute("UPDATE captures SET work_location=? WHERE id='legacy'", ("😀" * 161,))

    def test_normalized_capture_writes_and_restore_transaction_are_atomic(self) -> None:
        db = database()
        install_capture_guards(db)
        normalized = tuple(value.strip() for value in ("  A区  ", "  月检  ", "  王工  ", "  备注  "))
        db.execute(
            "INSERT INTO captures VALUES(?,?,?,?,?,?,?,?,?,?,?)",
            ("create", "p", *normalized, "ready", "/a", None, 1, 1),
        )
        self.assertEqual(
            db.execute(
                "SELECT work_location,work_content,photographer,notes FROM captures WHERE id='create'"
            ).fetchone(),
            normalized,
        )
        db.execute(
            "UPDATE captures SET work_location=?,work_content=?,photographer=?,notes=? WHERE id='create'",
            tuple(value.strip() for value in ("  B区  ", "  复检  ", "  李工  ", "  新备注  ")),
        )
        db.commit()
        try:
            db.execute("BEGIN")
            db.execute(
                "INSERT INTO captures VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                ("restore-ok", "p", "C区", "验收", "周工", "", "ready", "/c", None, 3, 3),
            )
            db.execute(
                "INSERT INTO captures VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                ("restore-bad", "p", "D区", "验收", "周\0工", "", "ready", "/d", None, 4, 4),
            )
            db.commit()
        except sqlite3.IntegrityError:
            db.rollback()
        self.assertIsNone(db.execute("SELECT id FROM captures WHERE id='restore-ok'").fetchone())

    def test_every_capture_persistence_boundary_uses_shared_normalization(self) -> None:
        text = source()
        for name in ("createCaptured", "updateCaptureFields"):
            body = method_body(name)
            self.assertIn("inspectCaptureFields", body)
            self.assertIn("capture_form_invalid", body)
        restore = method_body("restoreProjects")
        self.assertIn("inspectCaptureFields", restore)
        self.assertIn("createTransaction", restore)
        self.assertIn("rollback", restore)
        self.assertIn("restore_capture_fields_invalid", restore)
        self.assertIn("instr(NEW.notes,char(0))", text)

    def test_single_and_bundle_restore_preflight_before_private_media_extraction(self) -> None:
        restore = (
            ROOT / "ohos-native/entry/src/main/ets/feature/backup/RestoreService.ets"
        ).read_text(encoding="utf-8")
        attempt = restore[
            restore.index("private async restoreFromLocal") : restore.index("private async expandSources")
        ]
        self.assertLess(attempt.index("RestoreAttemptGate"), attempt.index("this.expandSources"))
        self.assertLess(attempt.index("this.expandSources"), attempt.index("this.preflightSources(sources)"))
        self.assertLess(attempt.index("this.preflightSources(sources)"), attempt.index("extractArchivePhoto"))
        self.assertLess(attempt.index("extractArchivePhoto"), attempt.index("finally"))
        self.assertLess(attempt.index("finally"), attempt.index("this.removeDirectory(staging)"))

        expand = restore[restore.index("private async expandSources") : restore.index("private async uniqueProjectName")]
        self.assertIn("extractBundleEntry", expand)
        self.assertIn("`${staging}/project-${index}.zip`", expand)
        self.assertNotIn("extractArchivePhoto", expand)

        preflight = restore[restore.index("private preflightSources") : restore.index("private async rollbackFiles")]
        self.assertIn("for (const source of sources)", preflight)
        for contract in (
            "inspectCaptureFields",
            "validateTemplateField",
            "restore_capture_fields_invalid",
            "restore_template_fields_invalid",
            "restore_template_duplicate",
            "validTimestamp",
        ):
            self.assertIn(contract, preflight)

    def test_restore_cleans_staging_when_bundle_preflight_rejects_before_media_import(self) -> None:
        restore = (
            ROOT / "ohos-native/entry/src/main/ets/feature/backup/RestoreService.ets"
        ).read_text(encoding="utf-8")
        attempt = restore[
            restore.index("private async restoreFromLocal") : restore.index("private async expandSources")
        ]
        # A thrown bundle preflight cannot reach the later media call, while the
        # same lexical try/finally always removes the staging tree containing
        # selected.zip and expanded project-*.zip temporary archives.
        order = tuple(
            attempt.index(token)
            for token in (
                "try {",
                "this.expandSources",
                "this.preflightSources(sources)",
                "extractArchivePhoto",
                "finally",
                "this.removeDirectory(staging)",
            )
        )
        self.assertEqual(order, tuple(sorted(order)))
        self.assertIn("restore_preview_invalid:", attempt)

    def test_restore_selection_copy_is_inside_executable_staging_scope(self) -> None:
        restore = (
            ROOT / "ohos-native/entry/src/main/ets/feature/backup/RestoreService.ets"
        ).read_text(encoding="utf-8")
        choose = restore[restore.index("async chooseAndRestore") : restore.index("private async restoreFromLocal")]
        for token in (
            "new RestoreStagingScope().run",
            "this.ensureDirectory(staging)",
            "fileIo.copyFile(uris[0], sourcePath)",
            "this.restoreFromLocal(sourcePath, operationId, staging)",
            "this.removeDirectory(staging)",
        ):
            self.assertIn(token, choose)
        scope = (
            ROOT / "ohos-native/entry/src/main/ets/feature/backup/RestoreStagingScope.ets"
        ).read_text(encoding="utf-8")
        self.assertLess(scope.index("try {"), scope.index("return await action()"))
        self.assertLess(scope.index("return await action()"), scope.index("finally"))
        self.assertLess(scope.index("finally"), scope.index("cleanup()"))

    def test_templates_insert_without_overwrite_and_database_recomputes_rename_keys(self) -> None:
        save = method_body("saveTemplate")
        rename = method_body("renameTemplate")
        self.assertIn("normalizeCaptureTemplateName", save)
        self.assertIn("captureTemplateNameKey", save)
        self.assertIn("INSERT INTO capture_templates", save)
        self.assertNotIn("OR REPLACE", save)
        self.assertIn("normalizeCaptureTemplateName", rename)
        self.assertIn("captureTemplateNameKey", rename)
        self.assertIn("changed < 1", rename)
        db = database()
        db.execute(
            "INSERT INTO capture_templates VALUES(?,?,?,?,?,?,?,?,?)",
            ("a", "p", "巡检", "巡检", "A", "月检", "王", 1, 1),
        )
        with self.assertRaises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO capture_templates VALUES(?,?,?,?,?,?,?,?,?)",
                ("b", "p", "巡检", "巡检", "B", "复检", "李", 2, 2),
            )
        row = db.execute("SELECT work_location FROM capture_templates WHERE id='a'").fetchone()
        self.assertEqual(row, ("A",))
        cursor = db.execute(
            "UPDATE capture_templates SET name=?,name_key=? WHERE id=?",
            (" 新名称 ".strip(), " 新名称 ".strip().lower(), "a"),
        )
        self.assertEqual(cursor.rowcount, 1)
        self.assertEqual(
            db.execute("SELECT name,name_key FROM capture_templates WHERE id='a'").fetchone(),
            ("新名称", "新名称"),
        )
        missing = db.execute(
            "UPDATE capture_templates SET name=?,name_key=? WHERE id=?", ("无", "无", "missing")
        )
        self.assertEqual(missing.rowcount, 0)

    def test_recent_suggestions_are_latest_first_deduplicated_and_exclude_pending(self) -> None:
        db = database()
        rows = [
            ("1", "p", " A ", "巡检", "王", "", "ready", "/1", None, 10, 10),
            ("2", "p", "a", "巡检", "王", "", "ready", "/2", None, 30, 30),
            ("3", "p", "B", "巡检", "王", "", "ready", "/3", None, 20, 20),
            ("4", "p", "C", "巡检", "王", "", "pendingCamera", "/4", None, 40, 40),
        ]
        db.executemany("INSERT INTO captures VALUES(?,?,?,?,?,?,?,?,?,?,?)", rows)
        query_match = re.search(
            r"async recentSuggestions.*?querySql\(\s*`(SELECT value FROM \(.*?LIMIT \?)`",
            source(),
            re.S,
        )
        self.assertIsNotNone(query_match)
        query = query_match.group(1).replace("${field}", "work_location")
        values = [row[0] for row in db.execute(query, ("p", 20)).fetchall()]
        self.assertEqual(values, ["a", "B"])

    def test_custom_button_text_has_explicit_action_colors(self) -> None:
        records = RECORD_SOURCE.read_text(encoding="utf-8")
        contracts = (
            (r"Text\(this\.renamingTemplateId.*?Save name.*?fontColor\(UiTokens\.ON_PRIMARY\)", "save"),
            (r"Text\(tr\('取消重命名'.*?fontColor\(UiTokens\.TEXT\)", "cancel"),
            (r"Text\(tr\('改名'.*?fontColor\(UiTokens\.PRIMARY\)", "rename"),
            (r"Text\(this\.deleteTemplateId.*?Confirm delete.*?fontColor\(UiTokens\.DANGER\)", "delete"),
        )
        for pattern, label in contracts:
            self.assertRegex(records, re.compile(pattern, re.S), label)

    def test_project_description_and_watermark_updates_own_disjoint_columns(self) -> None:
        description = method_body("updateProjectDescription")
        watermark = method_body("updateProjectWatermark")
        self.assertIn("SET description=?,updated_at=?", description)
        self.assertNotIn("watermark_", description)
        self.assertIn("watermark_position=?", watermark)
        self.assertNotIn("description=?", watermark)
        self.assertIn("changed < 1", description)
        self.assertIn("changed < 1", watermark)

        db = sqlite3.connect(":memory:")
        db.execute(
            "CREATE TABLE projects(id TEXT PRIMARY KEY,description TEXT,watermark_position TEXT,"
            "watermark_opacity REAL,watermark_accent_color_argb INTEGER,watermark_font_scale REAL,"
            "updated_at INTEGER)"
        )
        db.execute("INSERT INTO projects VALUES('p','old','bottomLeft',0.78,1,1.0,0)")
        db.execute(
            "UPDATE projects SET watermark_position=?,watermark_opacity=?,"
            "watermark_accent_color_argb=?,watermark_font_scale=?,updated_at=? WHERE id=?",
            ("topRight", 0.6, 22, 1.3, 1, "p"),
        )
        db.execute(
            "UPDATE projects SET description=?,updated_at=? WHERE id=?",
            ("new description", 2, "p"),
        )
        row = db.execute(
            "SELECT description,watermark_position,watermark_opacity,"
            "watermark_accent_color_argb,watermark_font_scale FROM projects WHERE id='p'"
        ).fetchone()
        self.assertEqual(row, ("new description", "topRight", 0.6, 22, 1.3))


if __name__ == "__main__":
    unittest.main()
