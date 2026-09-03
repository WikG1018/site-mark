import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OHOS = ROOT / "ohos-native"
ETS = OHOS / "entry" / "src" / "main" / "ets"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def method_body(source: str, signature: str, next_signature: str) -> str:
    start = source.index(signature)
    end = source.index(next_signature, start)
    return source[start:end]


class OhosNativeReviewContractsTest(unittest.TestCase):
    def test_album_save_copies_jpeg_before_committing_publish_journal(self) -> None:
        source = read(ETS / "core" / "system" / "SystemServices.ets")
        body = method_body(source, "async saveJpegToAlbum", "recoverPublishJournals")
        dialog = body.index("showAssetsCreationDialog")
        copy = body.index("copyFile")
        journal = body.index("journals.record")
        self.assertLess(dialog, copy)
        self.assertLess(copy, journal)

    def test_app_never_deletes_user_gallery_assets(self) -> None:
        services = read(ETS / "core" / "system" / "SystemServices.ets")
        database = read(ETS / "data" / "database" / "AppDatabase.ets")
        delete_capture = method_body(database, "async scheduleCaptureDeletion", "async discardMediaCleanups")
        self.assertNotIn("MediaAssetChangeRequest.deleteAssets", services)
        self.assertNotIn("capture_media_cleanups", delete_capture)

    def test_root_project_list_uses_overlay_content_offset(self) -> None:
        source = read(ETS / "feature" / "projects" / "ProjectScreens.ets")
        list_start = source.index("List({ space: 12, scroller: this.projectScroller })")
        list_end = source.index(".onScrollIndex", list_start)
        block = source[list_start:list_end]
        self.assertIn("overlayListViewportBottomPadding()", block)
        self.assertIn("overlayContentEndOffset(this.safeAreaBottomVp)", block)

    def test_completion_notifications_have_capture_scoped_want_agents(self) -> None:
        source = read(ETS / "core" / "system" / "CompletionNotifications.ets")
        self.assertNotIn("requestCode: 0", source)
        self.assertIn("requestCode: this.notificationId(captureId)", source)

    def test_entry_ability_awaits_window_mode_and_reacts_to_system_configuration(self) -> None:
        source = read(ETS / "entryability" / "EntryAbility.ets")
        self.assertIn("await win.setWindowLayoutFullScreen(true)", source)
        self.assertIn("await win.setWindowSystemBarProperties", source)
        self.assertIn("onConfigurationUpdate", source)
        self.assertIn("applyAppearance", source)

    def test_manual_backup_is_the_only_enabled_backup_channel(self) -> None:
        config = json.loads(read(OHOS / "entry" / "src" / "main" / "resources" /
                                 "base" / "profile" / "backup_config.json"))
        self.assertIs(config["allowToBackupRestore"], False)

    def test_export_cleanup_reclaims_interrupted_work_directories(self) -> None:
        source = read(ETS / "core" / "system" / "StorageInspector.ets")
        self.assertIn("work-", source)
        self.assertRegex(source, re.compile(r"removeDirectory|removeTree"))
        runtime = read(ETS / "app" / "AppRuntime.ets")
        self.assertIn("clearInterruptedExports", runtime)

    def test_runtime_version_is_not_hardcoded_in_about_or_diagnostics(self) -> None:
        about = read(ETS / "feature" / "settings" / "SettingsScreens.ets")
        diagnostics = read(ETS / "feature" / "diagnostics" / "DiagnosticBundleService.ets")
        self.assertNotIn("版本 1.0.0", about)
        self.assertNotIn("Version 1.0.0", about)
        self.assertNotIn("app_version: '1.0.0'", diagnostics)
        self.assertNotIn("build_number: '1'", diagnostics)
        self.assertIn("loadAppVersion", about)
        self.assertIn("loadAppVersion", diagnostics)

    def test_project_database_does_not_map_every_write_error_to_name_conflict(self) -> None:
        source = read(ETS / "data" / "database" / "AppDatabase.ets")
        create = method_body(source, "async createProject", "async renameProject")
        rename = method_body(source, "async renameProject", "async updateProjectDescription")
        blanket = "catch (_) {\n      throw new Error('project_name_conflict');\n    }"
        self.assertNotIn(blanket, create)
        self.assertNotIn(blanket, rename)
        self.assertIn("project_name_conflict", create)
        self.assertIn("project_name_conflict", rename)

    def test_about_and_privacy_gate_describe_optional_nas_not_closed_network(self) -> None:
        about = read(ETS / "feature" / "settings" / "SettingsScreens.ets")
        index = read(ETS / "pages" / "Index.ets")
        self.assertNotIn("不申请网络权限", about)
        self.assertNotIn("does not request network permission", about)
        self.assertIn("NAS", about)
        self.assertNotIn("也不申请网络权限", index)
        self.assertNotIn("or network permission", index)
        self.assertIn("NAS", index)

    def test_native_link_includes_time_service_for_iana_timezone(self) -> None:
        cmake = read(OHOS / "entry" / "src" / "main" / "cpp" / "CMakeLists.txt")
        self.assertIn("libtime_service_ndk.so", cmake)

    def test_nas_sync_service_uses_arkts_legal_constructors_and_asset_maps(self) -> None:
        source = read(ETS / "core" / "sync" / "NasSyncService.ets")
        self.assertNotIn("constructor(private readonly database", source)
        self.assertNotIn("readonly failure: string | null,", source)
        self.assertIn("asset.Tag.ALIAS", source)
        self.assertIn("asset.Tag.SECRET", source)
        self.assertIn("bearerTypes", source)
        self.assertNotIn("bearType", source)

    def test_nas_settings_exposes_protocol_choice_and_shared_form_fields(self) -> None:
        source = read(ETS / "feature" / "settings" / "NasSyncScreen.ets")
        self.assertIn("LifecycleSegment", source)
        self.assertIn("SegmentOption('webdav'", source)
        self.assertIn("SegmentOption('sftp'", source)
        self.assertIn("SegmentOption('smb'", source)
        self.assertIn("FormField", source)
        self.assertNotIn("padding({ top: 6, bottom: 6 })", source)
        self.assertNotIn("private fieldRow", source)
        self.assertNotIn("Align.Top", source)
        self.assertNotIn("@State private enabled", source)
        self.assertIn("SectionHeader", source)
        self.assertIn("../../shared/AppComponents", source)


if __name__ == "__main__":
    unittest.main()
