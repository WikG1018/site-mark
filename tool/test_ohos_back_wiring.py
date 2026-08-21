import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INDEX_SOURCE = ROOT / "ohos-native/entry/src/main/ets/pages/Index.ets"
ABILITY_SOURCE = ROOT / "ohos-native/entry/src/main/ets/entryability/EntryAbility.ets"
GENERATED_INDEX = ROOT / "ohos-native/entry/src/main/ets/generated/Index.ets"
PROJECT_SCREENS = ROOT / "ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets"


class HarmonyBackWiringContractTest(unittest.TestCase):
    def test_root_dispatcher_is_wired_to_page_back_callback(self) -> None:
        index = INDEX_SOURCE.read_text(encoding="utf-8")
        self.assertIn("RootBackDispatcher", index)
        self.assertRegex(
            index,
            re.compile(
                r"onBackPress\(\): boolean\s*\{\s*return RootBackDispatcher\.handle\(\);\s*\}",
                re.S,
            ),
        )

    def test_ability_does_not_override_lifecycle_back_behavior(self) -> None:
        ability = ABILITY_SOURCE.read_text(encoding="utf-8")
        self.assertNotIn("RootBackDispatcher", ability)
        self.assertNotRegex(ability, r"\bonBackPressed\s*\(")

    def test_preview_fallback_generated_page_is_not_used_for_back_dispatch(self) -> None:
        generated = GENERATED_INDEX.read_text(encoding="utf-8")
        self.assertNotIn("RootBackDispatcher", generated)
        self.assertNotRegex(generated, r"\bonBackPress\s*\(")

    def test_project_list_registers_a_root_back_handler_for_search(self) -> None:
        projects = PROJECT_SCREENS.read_text(encoding="utf-8")
        project_list = projects.split("export struct ProjectListView", 1)[1].split(
            "export struct ProjectEditorScreen", 1
        )[0]
        self.assertIn("RootBackDispatcher.register", project_list)
        self.assertIn("RootBackDispatcher.unregister", project_list)
        self.assertRegex(project_list, r"searchText\.length\s*===\s*0")
        self.assertRegex(project_list, r"searchText\s*=\s*''")

    def test_project_detail_and_forms_wire_busy_policies_to_controls(self) -> None:
        projects = PROJECT_SCREENS.read_text(encoding="utf-8")
        detail = projects.split("export struct ProjectDetailScreen", 1)[1].split(
            "export struct ProjectSettingsScreen", 1
        )[0]
        editor = projects.split("export struct ProjectEditorScreen", 1)[1].split(
            "export struct ProjectDetailScreen", 1
        )[0]
        settings = projects.split("export struct ProjectSettingsScreen", 1)[1]
        self.assertGreaterEqual(detail.count(".enabled(this.canMutateProject())"), 8)
        self.assertIn("if (this.pageBusy()) return;", detail)
        self.assertIn("this.batchBusy || this.mutationBusy", detail)
        self.assertIn("ProjectOperationKind.BATCH", detail)
        self.assertIn("ProjectOperationKind.MUTATION", detail)
        self.assertIn("this.projectOperations.activate();\n    this.reconcileProjectOperationBusyState();", detail)
        self.assertIn("this.batchBusy = state.batchBusy;", detail)
        self.assertIn("this.mutationBusy = state.mutationBusy;", detail)
        self.assertNotIn("this.batchBusy = true;", detail)
        self.assertNotIn("this.mutationBusy = true;", detail)
        self.assertEqual(editor.count("fieldEnabled: !this.saving"), 2)
        self.assertGreaterEqual(settings.count(".enabled(!this.saving)"), 4)


if __name__ == "__main__":
    unittest.main()
