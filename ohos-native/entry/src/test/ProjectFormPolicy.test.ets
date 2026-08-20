import { describe, expect, it } from '@ohos/hypium';
import {
  ProjectFormMetrics,
  projectFormCopy,
  projectNameValidationError,
  projectSaveFeedback,
  selectionVisual,
  watermarkAccentChoices,
  watermarkPositionChoices,
} from '../main/ets/feature/projects/ProjectFormPolicy';
import { UiTokens } from '../main/ets/shared/UiTokens';

export default function projectFormPolicyTest(): void {
  describe('Project form policy', () => {
    it('keeps fields and controls stable and touchable', 0, () => {
      expect(ProjectFormMetrics.SINGLE_LINE_HEIGHT >= 48 &&
        ProjectFormMetrics.SINGLE_LINE_HEIGHT <= 52).assertTrue();
      expect(ProjectFormMetrics.TEXT_AREA_HEIGHT >= 104).assertTrue();
      expect(ProjectFormMetrics.SUPPORTING_TEXT_MIN_HEIGHT >= 32).assertTrue();
      expect(ProjectFormMetrics.TOUCH_TARGET >= 44).assertTrue();
    });

    it('keeps Chinese and English labels helpers and errors non-empty', 0, () => {
      const chinese = projectFormCopy(false);
      const english = projectFormCopy(true);
      const values: string[] = [
        chinese.nameLabel, chinese.nameHelper, chinese.nameRequiredError, chinese.nameConflictError,
        chinese.descriptionLabel, chinese.descriptionHelper, chinese.watermarkPositionLabel,
        chinese.opacityLabel, chinese.opacityHelper, chinese.fontScaleLabel, chinese.fontScaleHelper,
        english.nameLabel, english.nameHelper, english.nameRequiredError, english.nameConflictError,
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
  });
}
