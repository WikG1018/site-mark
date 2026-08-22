import { describe, expect, it } from '@ohos/hypium';
import {
  ProjectFormMetrics,
  projectFormCopy,
  projectNameValidationError,
  projectSaveFeedback,
  selectionKey,
  selectionVisual,
  watermarkAccentChoices,
  watermarkPreviewLayer,
  watermarkPreviewLayout,
  watermarkPositionChoices,
  WatermarkPreviewStyle,
} from '../main/ets/feature/projects/ProjectFormPolicy';
import { FormLengthPolicy } from '../main/ets/shared/FormComponents';
import { UiTokens } from '../main/ets/shared/UiTokens';

export default function projectFormPolicyTest(): void {
  describe('Project form policy', () => {
    it('keeps fields and controls stable and touchable', 0, () => {
      expect(ProjectFormMetrics.SINGLE_LINE_HEIGHT >= 48 &&
        ProjectFormMetrics.SINGLE_LINE_HEIGHT <= 52).assertTrue();
      expect(ProjectFormMetrics.TEXT_AREA_HEIGHT >= 104).assertTrue();
      expect(ProjectFormMetrics.SUPPORTING_TEXT_MIN_HEIGHT >= 18).assertTrue();
      expect(ProjectFormMetrics.TOUCH_TARGET >= 44).assertTrue();
    });

    it('keeps Chinese and English labels helpers and errors non-empty', 0, () => {
      const chinese = projectFormCopy(false);
      const english = projectFormCopy(true);
      const values: string[] = [
        chinese.nameLabel, chinese.nameHelper, chinese.nameRequiredError, chinese.nameTooLongError,
        chinese.nameConflictError,
        chinese.descriptionLabel, chinese.descriptionHelper, chinese.watermarkPositionLabel,
        chinese.opacityLabel, chinese.opacityHelper, chinese.fontScaleLabel, chinese.fontScaleHelper,
        english.nameLabel, english.nameHelper, english.nameRequiredError, english.nameTooLongError,
        english.nameConflictError,
        english.descriptionLabel, english.descriptionHelper, english.watermarkPositionLabel,
        english.opacityLabel, english.opacityHelper, english.fontScaleLabel, english.fontScaleHelper,
      ];

      expect(values.every((value: string): boolean => value.trim().length > 0)).assertTrue();
      expect(chinese.nameHelper === chinese.nameRequiredError).assertFalse();
      expect(english.nameHelper === english.nameRequiredError).assertFalse();
    });

    it('maps required and duplicate project errors to the name field only', 0, () => {
      const chinese = projectFormCopy(false);
      expect(projectNameValidationError('   ', false)).assertEqual(chinese.nameRequiredError);
      expect(projectNameValidationError('有效项目', false)).assertEqual('');
      expect(projectNameValidationError('A'.repeat(120), false)).assertEqual('');
      expect(projectNameValidationError('A'.repeat(121), false)).assertEqual(chinese.nameTooLongError);
      expect(ProjectFormMetrics.PROJECT_NAME_MAX_LENGTH).assertEqual(120);

      const duplicate = projectSaveFeedback('project_name_conflict', false);
      expect(duplicate.nameError).assertEqual(chinese.nameConflictError);
      expect(duplicate.pageMessage).assertEqual('');

      const invalid = projectSaveFeedback('project_name_invalid', false);
      expect(invalid.nameError).assertEqual(chinese.nameInvalidError);
      expect(invalid.pageMessage).assertEqual('');

      const storage = projectSaveFeedback('database_unavailable', false);
      expect(storage.nameError).assertEqual('');
      expect(storage.pageMessage.length > 0).assertTrue();
    });

    it('gives every watermark position a unique selected-state description', 0, () => {
      const chinese = watermarkPositionChoices(false, 'bottomLeft');
      const english = watermarkPositionChoices(true, 'bottomRight');

      expect(chinese.length).assertEqual(2);
      expect(english.length).assertEqual(2);
      expect(chinese[0].accessibilityText === chinese[1].accessibilityText).assertFalse();
      expect(english[0].accessibilityText === english[1].accessibilityText).assertFalse();
      expect(chinese[0].accessibilityText.includes('已选择')).assertTrue();
      expect(chinese[1].accessibilityText.includes('未选择')).assertTrue();
      expect(english[0].accessibilityText).assertEqual('Bottom left, not selected');
      expect(english[1].accessibilityText).assertEqual('Bottom right, selected');
    });

    it('gives accent presets unique bilingual names and selected state', 0, () => {
      const chinese = watermarkAccentChoices(false, 0xFF2E7D61);
      const english = watermarkAccentChoices(true, 0xFF1565C0);

      expect(chinese.length).assertEqual(5);
      expect(english.length).assertEqual(5);
      expect(chinese.map((choice): string => choice.label).join('|'))
        .assertEqual('墨绿|蓝色|棕橙|紫色|深灰');
      expect(english.map((choice): string => choice.label).join('|'))
        .assertEqual('Forest green|Blue|Burnt orange|Purple|Charcoal');
      expect(chinese[0].accessibilityText.includes('已选择')).assertTrue();
      expect(english[1].accessibilityText.includes('selected')).assertTrue();
    });

    it('uses theme tokens and a non-color selected indicator for choices', 0, () => {
      const unselected = selectionVisual(false);
      const selected = selectionVisual(true);

      expect(unselected.backgroundColor).assertEqual(UiTokens.CONTROL);
      expect(unselected.borderColor).assertEqual(UiTokens.OUTLINE_SUBTLE);
      expect(unselected.touchTarget).assertEqual(ProjectFormMetrics.TOUCH_TARGET);
      expect(selected.backgroundColor).assertEqual(UiTokens.PRIMARY_CONTAINER);
      expect(selected.borderWidth > unselected.borderWidth).assertTrue();
      expect(selected.indicator.length > 0).assertTrue();
    });

    it('rebuilds only choices whose selected state changes', 0, () => {
      const leftBefore = selectionKey('bottomLeft', true);
      const leftAfter = selectionKey('bottomLeft', false);
      const rightBefore = selectionKey('bottomRight', false);
      const rightAfter = selectionKey('bottomRight', true);
      const unrelatedBefore = selectionKey('charcoal', false);
      const unrelatedAfter = selectionKey('charcoal', false);

      expect(leftBefore === leftAfter).assertFalse();
      expect(rightBefore === rightAfter).assertFalse();
      expect(unrelatedBefore).assertEqual(unrelatedAfter);
    });

    it('leaves project descriptions unlimited while preserving explicit limits', 0, () => {
      expect(ProjectFormMetrics.PROJECT_DESCRIPTION_MAX_LENGTH).assertEqual(0);
      expect(FormLengthPolicy.shouldApply(ProjectFormMetrics.PROJECT_DESCRIPTION_MAX_LENGTH)).assertFalse();
      expect(FormLengthPolicy.shouldApply(-1)).assertFalse();
      expect(FormLengthPolicy.shouldApply(1000)).assertTrue();
    });

    it('keeps preview text and border opaque while applying opacity once to its background', 0, () => {
      const layer = watermarkPreviewLayer(0.78);

      expect(layer.backgroundOpacity).assertEqual(0.78);
      expect(layer.contentOpacity).assertEqual(1);
      expect(layer.borderOpacity).assertEqual(1);
      expect(WatermarkPreviewStyle.BACKGROUND.length).assertEqual(7);
    });

    it('grows preview height safely for two-line project names at every font preset edge', 0, () => {
      const small = watermarkPreviewLayout(0.75);
      const normal = watermarkPreviewLayout(1.0);
      const large = watermarkPreviewLayout(1.6);

      expect(small.fontScale).assertEqual(0.75);
      expect(normal.frameHeight >= small.frameHeight).assertTrue();
      expect(large.frameHeight > normal.frameHeight).assertTrue();
      expect(small.panelHeight >= small.requiredContentHeight).assertTrue();
      expect(normal.panelHeight >= normal.requiredContentHeight).assertTrue();
      expect(large.panelHeight >= large.requiredContentHeight).assertTrue();
      expect(large.projectNameLineHeight > normal.projectNameLineHeight).assertTrue();
      expect(large.detailLineHeight > normal.detailLineHeight).assertTrue();
    });
  });
}
