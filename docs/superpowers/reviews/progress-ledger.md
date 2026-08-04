# Settings Secondary Menu Refactor — Progress Ledger

Tracks per-task status and Minor findings to triage at the final whole-branch review.

## Task Status

| Task | Status | Commit | Verdict |
|------|--------|--------|---------|
| 1: AppSettingController | DONE | `adc06c3` | APPROVED |
| 2: Shared scaffold | — | — | — |
| 3: AppearanceSectionScreen | — | — | — |
| 4: LanguageSectionScreen | — | — | — |
| 5: WatermarkDefaultsSectionScreen | — | — | — |
| 6: StorageSectionScreen | — | — | — |
| 7: LocationSectionScreen | — | — | — |
| 8: NotificationSectionScreen | — | — | — |
| 9: AboutSectionScreen | — | — | — |
| 10: Rewrite GlobalSettingsScreen | — | — | — |
| 11: Update routes | — | — | — |
| 12: Regression + cleanup | — | — | — |
| 13: Push to PR #14 | — | — | — |

## Minor Findings (defer to final review triage)

### Task 1 — AppSettingController
- **[Minor] 并发竞态（理论）** `app_setting_controller.dart:30-58` — 两次并发 `update` 调用时，A 回滚可能覆盖 B 的乐观值。设置页为单用户串行 UI，实际触发概率低；计划未要求串行化；Riverpod 内建 `update` 同特性。可接受。
- **[Minor] `null` 分支跳过持久化** `app_setting_controller.dart:31-35` — state 为 loading/error 时走 `super.update`，绕过 DB 写入。语义合理（无当前值可计算 next），注释已说明。可接受。
- **[Minor] 缺回滚测试** `app_setting_controller_test.dart` — 仅 happy path。Brief 未要求，但 failure→rollback→onError/rethrow 路径无回归保护。后续若改动 controller 建议补注入抛错的用例。

## Cross-Task / Cannot-verify items
- 234+ 既有 widget 测试全通过 — 跨任务集成验证（Task 12 执行）。
- l10n keys 未变 / 无新依赖 / 无 schema 变更 — 各 task diff 结构性满足，最终 Task 12 复核。
