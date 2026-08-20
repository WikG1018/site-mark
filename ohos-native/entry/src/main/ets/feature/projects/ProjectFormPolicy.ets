import { UiTokens } from '../../shared/UiTokens';
import { FormLayoutMetrics } from '../../shared/FormComponents';

export class ProjectFormMetrics {
  static readonly SINGLE_LINE_HEIGHT: number = FormLayoutMetrics.SINGLE_LINE_HEIGHT;
  static readonly TEXT_AREA_HEIGHT: number = FormLayoutMetrics.TEXT_AREA_HEIGHT;
  static readonly SUPPORTING_TEXT_MIN_HEIGHT: number = FormLayoutMetrics.SUPPORTING_TEXT_MIN_HEIGHT;
  static readonly TOUCH_TARGET: number = FormLayoutMetrics.TOUCH_TARGET;
}

export class ProjectFormCopy {
  nameLabel: string;
  namePlaceholder: string;
  nameHelper: string;
  nameRequiredError: string;
  nameInvalidError: string;
  nameConflictError: string;
  descriptionLabel: string;
  descriptionPlaceholder: string;
  descriptionHelper: string;
  saveFailure: string;
  watermarkPositionLabel: string;
  opacityLabel: string;
  opacityHelper: string;
  fontScaleLabel: string;
  fontScaleHelper: string;
  accentLabel: string;
  previewLabel: string;

  constructor(english: boolean) {
    this.nameLabel = english ? 'Project name' : '项目名称';
    this.namePlaceholder = english ? 'For example: Riverside Tower' : '例如：云湖之城';
    this.nameHelper = english ?
      'Required and unique. Renaming applies only to future photo names.' :
      '必填且不能与其他项目同名；重命名仅影响以后新拍照片。';
    this.nameRequiredError = english ? 'Enter a project name' : '请输入项目名称';
    this.nameInvalidError = english ? 'Enter a valid project name' : '请输入有效的项目名称';
    this.nameConflictError = english ?
      'A project with the same name or file name already exists' :
      '已存在同名项目或文件名冲突';
    this.descriptionLabel = english ? 'Project description (optional)' : '项目说明（选填）';
    this.descriptionPlaceholder = english ?
      'Add the location, contract, or site notes' :
      '补充项目位置、合同或现场说明';
    this.descriptionHelper = english ?
      'Optional. Add details that help identify this project.' :
      '选填，可记录位置、合同或现场说明。';
    this.saveFailure = english ?
      'The project could not be saved. Try again.' :
      '项目保存失败，请稍后重试';
    this.watermarkPositionLabel = english ? 'Watermark position' : '水印位置';
    this.opacityLabel = english ? 'Opacity' : '透明度';
    this.opacityHelper = english ?
      'Controls the watermark panel opacity in new or regenerated photos.' :
      '调整新拍或重新生成照片中的水印透明度。';
    this.fontScaleLabel = english ? 'Font size' : '字体大小';
    this.fontScaleHelper = english ?
      'Scales the watermark text while preserving its layout.' :
      '调整水印文字大小，不改变其他布局。';
    this.accentLabel = english ? 'Accent color' : '强调色';
    this.previewLabel = english ? 'SiteMark preview' : '工程印记预览';
  }
}

export function projectFormCopy(english: boolean): ProjectFormCopy {
  return new ProjectFormCopy(english);
}

export function projectNameValidationError(name: string, english: boolean): string {
  if (name.trim().length === 0) {
    return projectFormCopy(english).nameRequiredError;
  }
  return '';
}

export class ProjectSaveFeedback {
  nameError: string;
  pageMessage: string;

  constructor(nameError: string = '', pageMessage: string = '') {
    this.nameError = nameError;
    this.pageMessage = pageMessage;
  }
}

export function projectSaveFeedback(errorMessage: string, english: boolean): ProjectSaveFeedback {
  const copy = projectFormCopy(english);
  if (errorMessage.includes('conflict')) {
    return new ProjectSaveFeedback(copy.nameConflictError, '');
  }
  if (errorMessage.includes('project_name_invalid')) {
    return new ProjectSaveFeedback(copy.nameInvalidError, '');
  }
  return new ProjectSaveFeedback('', copy.saveFailure);
}

function selectionAccessibility(label: string, selected: boolean, english: boolean): string {
  if (english) {
    return `${label}, ${selected ? 'selected' : 'not selected'}`;
  }
  return `${label}，${selected ? '已选择' : '未选择'}`;
}

export class WatermarkPositionChoice {
  value: string;
  label: string;
  selected: boolean;
  accessibilityText: string;

  constructor(value: string, label: string, selected: boolean, english: boolean) {
    this.value = value;
    this.label = label;
    this.selected = selected;
    this.accessibilityText = selectionAccessibility(label, selected, english);
  }
}

export function watermarkPositionChoices(english: boolean, selectedValue: string): WatermarkPositionChoice[] {
  return [
    new WatermarkPositionChoice('bottomLeft', english ? 'Bottom left' : '左下',
      selectedValue === 'bottomLeft', english),
    new WatermarkPositionChoice('bottomRight', english ? 'Bottom right' : '右下',
      selectedValue === 'bottomRight', english),
  ];
}

export class WatermarkAccentChoice {
  value: number;
  color: string;
  label: string;
  selected: boolean;
  accessibilityText: string;

  constructor(value: number, color: string, label: string, selected: boolean, english: boolean) {
    this.value = value;
    this.color = color;
    this.label = label;
    this.selected = selected;
    this.accessibilityText = selectionAccessibility(label, selected, english);
  }
}

export function watermarkAccentChoices(english: boolean, selectedValue: number): WatermarkAccentChoice[] {
  return [
    new WatermarkAccentChoice(0xFF2E7D61, '#2E7D61', english ? 'Forest green' : '墨绿',
      selectedValue === 0xFF2E7D61, english),
    new WatermarkAccentChoice(0xFF1565C0, '#1565C0', english ? 'Blue' : '蓝色',
      selectedValue === 0xFF1565C0, english),
    new WatermarkAccentChoice(0xFFC05A24, '#C05A24', english ? 'Burnt orange' : '棕橙',
      selectedValue === 0xFFC05A24, english),
    new WatermarkAccentChoice(0xFF7B4DA8, '#7B4DA8', english ? 'Purple' : '紫色',
      selectedValue === 0xFF7B4DA8, english),
    new WatermarkAccentChoice(0xFF37474F, '#37474F', english ? 'Charcoal' : '深灰',
      selectedValue === 0xFF37474F, english),
  ];
}

export class SelectionVisual {
  backgroundColor: string;
  borderColor: string;
  borderWidth: number;
  indicator: string;
  touchTarget: number;

  constructor(backgroundColor: string, borderColor: string, borderWidth: number, indicator: string) {
    this.backgroundColor = backgroundColor;
    this.borderColor = borderColor;
    this.borderWidth = borderWidth;
    this.indicator = indicator;
    this.touchTarget = ProjectFormMetrics.TOUCH_TARGET;
  }
}

export function selectionVisual(selected: boolean): SelectionVisual {
  return selected ?
    new SelectionVisual(UiTokens.PRIMARY_CONTAINER, UiTokens.PRIMARY, 2, '✓') :
    new SelectionVisual(UiTokens.CONTROL, UiTokens.OUTLINE_SUBTLE, 1, '');
}

export class WatermarkPreviewStyle {
  static readonly BACKGROUND: string = '#CC17201C';
}
