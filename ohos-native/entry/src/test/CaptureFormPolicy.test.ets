import { describe, expect, it } from '@ohos/hypium';
import { CaptureStatus, ProjectLifecycleStatus } from '../main/ets/domain/StateMachine';
import {
  CaptureDraftSnapshot,
  CaptureFormLifecycle,
  CaptureFormMetrics,
  CaptureUndoCoordinator,
  SingleFlightRequestCoordinator,
  applyDraftSuggestion,
  applyCaptureOutcome,
  canEditCapture,
  captureFormCopy,
  filterSuggestions,
  restoreRequiredFields,
  validateCaptureDraft,
  validateTemplateDraft,
  validateTemplateName
} from '../main/ets/feature/capture/CaptureFormPolicy';

export default function captureFormPolicyTest(): void {
  describe('Capture form policy', () => {
    it('validates trimmed Unicode scalars at every database boundary', 0, () => {
      const valid = validateCaptureDraft(` ${'😀'.repeat(160)} `, '巡检', '王工', '不限长度');
      expect(valid.valid).assertTrue();
      expect(valid.location.length).assertEqual(320);
      expect(validateCaptureDraft('😀'.repeat(161), '巡检', '王工', '').locationError.length > 0).assertTrue();
      expect(validateCaptureDraft('A', '😀'.repeat(241), '王工', '').workError.length > 0).assertTrue();
      expect(validateCaptureDraft('A', '巡检', '😀'.repeat(81), '').photographerError.length > 0).assertTrue();
      expect(validateCaptureDraft('A\u0000', '巡检', '王工', '').locationError.length > 0).assertTrue();
      expect(validateCaptureDraft('A', '巡检', '王工', `备注\u0000`).notesError.length > 0).assertTrue();
      expect(validateCaptureDraft('A', '巡检', '王工', '备'.repeat(5000)).valid).assertTrue();
    });

    it('trims and validates template values instead of persisting invisible overflow', 0, () => {
      const valid = validateTemplateDraft('  日常巡检  ', '  A区  ', '  月检  ', '  王工  ');
      expect(valid.valid).assertTrue();
      expect(valid.name).assertEqual('日常巡检');
      expect(valid.location).assertEqual('A区');
      expect(validateTemplateDraft('模板', 'A', '巡检', `王\u0000工`).valid).assertFalse();
      expect(validateTemplateDraft('😀'.repeat(81), 'A', '巡检', '王工').nameError.length > 0).assertTrue();
      expect(validateTemplateName('  改名  ').value).assertEqual('改名');
      expect(validateTemplateName('模板').valid).assertTrue();
    });

    it('shows three focused suggestions and filters no more than twenty', 0, () => {
      const values: string[] = [];
      for (let index = 0; index < 30; index++) values.push(`位置 ${index}`);
      expect(filterSuggestions(values, '', 3).length).assertEqual(3);
      expect(filterSuggestions(values, '', 20).length).assertEqual(20);
      const filtered = filterSuggestions(values, '位置 2', 20);
      expect(filtered.length).assertEqual(11);
      expect(filtered[0]).assertEqual('位置 2');
    });

    it('keeps exactly one undo snapshot for suggestion or template application', 0, () => {
      const before = new CaptureDraftSnapshot('A', '巡检', '王工', '备注');
      const applied = applyDraftSuggestion(before, 'location', 'B');
      expect(applied.value.location).assertEqual('B');
      expect(applied.previous.location).assertEqual('A');
      const undone = applied.previous;
      expect(undone.location).assertEqual('A');
      expect(undone.notes).assertEqual('备注');
      const afterNotesEdit = new CaptureDraftSnapshot('B', '巡检', '王工', '新备注');
      const restored = restoreRequiredFields(afterNotesEdit, applied.previous);
      expect(restored.location).assertEqual('A');
      expect(restored.notes).assertEqual('新备注');
    });

    it('invalidates application undo after any manual required-field edit', 0, () => {
      const undo = new CaptureUndoCoordinator();
      undo.arm(new CaptureDraftSnapshot('A', '巡检', '王工', '备注'));
      expect(undo.available()).assertTrue();
      undo.requiredFieldEdited();
      expect(undo.available()).assertFalse();
      expect(undo.consume(new CaptureDraftSnapshot('B', '复检', '李工', '新备注')) === null).assertTrue();
    });

    it('preserves every field on camera cancellation and clears only notes after success', 0, () => {
      const draft = new CaptureDraftSnapshot('A区', '巡检', '王工', '本次备注');
      const cancelled = applyCaptureOutcome(draft, false);
      expect(cancelled.location).assertEqual('A区');
      expect(cancelled.work).assertEqual('巡检');
      expect(cancelled.photographer).assertEqual('王工');
      expect(cancelled.notes).assertEqual('本次备注');
      const captured = applyCaptureOutcome(draft, true);
      expect(captured.location).assertEqual('A区');
      expect(captured.work).assertEqual('巡检');
      expect(captured.photographer).assertEqual('王工');
      expect(captured.notes).assertEqual('');
    });

    it('serializes reloads and rejects results from invalidated request generations', 0, () => {
      const requests = new SingleFlightRequestCoordinator();
      const first = requests.begin();
      expect(first > 0).assertTrue();
      expect(requests.begin()).assertEqual(0);
      requests.invalidate();
      expect(requests.accept(first)).assertFalse();
      const second = requests.begin();
      expect(second > first).assertTrue();
      expect(requests.accept(second)).assertTrue();
      requests.finish(second);
      expect(requests.begin() > second).assertTrue();
    });

    it('closes transient panels before allowing navigation and rejects stale async writes', 0, () => {
      const lifecycle = new CaptureFormLifecycle();
      const first = lifecycle.activate();
      lifecycle.openTransient('templates');
      expect(lifecycle.consumeBack()).assertTrue();
      expect(lifecycle.consumeBack()).assertFalse();
      lifecycle.deactivate();
      expect(lifecycle.accept(first)).assertFalse();
      const second = lifecycle.activate();
      expect(second === first).assertFalse();
      expect(lifecycle.beginSave()).assertTrue();
      expect(lifecycle.beginSave()).assertFalse();
      lifecycle.finishSave(second);
      expect(lifecycle.beginSave()).assertTrue();
    });

    it('requires active project, ready or failed state, and retained original for edits', 0, () => {
      expect(canEditCapture(ProjectLifecycleStatus.ACTIVE, CaptureStatus.READY, true)).assertTrue();
      expect(canEditCapture(ProjectLifecycleStatus.ACTIVE, CaptureStatus.FAILED, true)).assertTrue();
      expect(canEditCapture(ProjectLifecycleStatus.ACTIVE, CaptureStatus.READY, false)).assertFalse();
      expect(canEditCapture(ProjectLifecycleStatus.COMPLETED, CaptureStatus.READY, true)).assertFalse();
      expect(canEditCapture(ProjectLifecycleStatus.ACTIVE, CaptureStatus.RENDERING, true)).assertFalse();
    });

    it('keeps touch targets and bilingual back descriptions explicit', 0, () => {
      expect(CaptureFormMetrics.TOUCH_TARGET >= 44).assertTrue();
      expect(CaptureFormMetrics.LOCATION_MAX_LENGTH).assertEqual(160);
      expect(CaptureFormMetrics.WORK_MAX_LENGTH).assertEqual(240);
      expect(CaptureFormMetrics.PHOTOGRAPHER_MAX_LENGTH).assertEqual(80);
      expect(CaptureFormMetrics.NOTES_MAX_LENGTH).assertEqual(0);
      expect(CaptureFormMetrics.TEMPLATE_ACTION_MIN_HEIGHT >= 44).assertTrue();
      expect(CaptureFormMetrics.TEMPLATE_ACTION_MAX_LINES >= 2).assertTrue();
      expect(captureFormCopy(false).captureBackAccessibility).assertEqual('返回项目详情');
      expect(captureFormCopy(true).editorBackAccessibility).assertEqual('Cancel editing and return to record details');
    });
  });
}
