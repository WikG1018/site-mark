import { ProjectRecord, ProjectSummary } from '../../domain/Models';
import { ProjectLifecycleStatus } from '../../domain/StateMachine';
import { tr } from '../../shared/AppText';
import { formatDateTime, imageUri, lifecycleLabel } from '../../shared/Formatters';
import { UiTokens } from '../../shared/UiTokens';
import { AppImage, ImageDecodePolicy } from '../../shared/AppImage';

function emptyProjectSummary(): ProjectSummary {
  return new ProjectSummary(new ProjectRecord({
    id: '', name: '', description: '', lifecycleStatus: ProjectLifecycleStatus.ACTIVE,
    isPinned: false, watermarkPosition: 'bottomLeft', watermarkOpacity: 0.82,
    watermarkAccentColorArgb: 0xFF176B55, watermarkFontScale: 1, createdAt: 0, updatedAt: 0
  }), 0, 0, 0, 0, []);
}

function projectSummaryText(item: ProjectSummary): string {
  const records = tr(`${item.captureCount} 条记录`,
    `${item.captureCount} record${item.captureCount === 1 ? '' : 's'}`);
  if (item.pendingCount > 0) {
    return `${records} · ${tr(`${item.pendingCount} 条处理中`, `${item.pendingCount} processing`)}`;
  }
  if (item.latestCaptureAt > 0) {
    return `${records} · ${tr(`最近 ${formatDateTime(item.latestCaptureAt)}`,
      `Latest ${formatDateTime(item.latestCaptureAt)}`)}`;
  }
  return `${records} · ${tr('尚未拍摄', 'No captures yet')}`;
}

class ProjectPreviewItem {
  readonly key: string;
  readonly path: string;

  constructor(key: string, path: string) {
    this.key = key;
    this.path = path;
  }
}

function projectPreviewItems(projectId: string, paths: string[]): ProjectPreviewItem[] {
  const previews: ProjectPreviewItem[] = [];
  const limit = Math.min(3, paths.length);
  for (let index = 0; index < limit; index += 1) {
    previews.push(new ProjectPreviewItem(`${projectId}\u001F${index}\u001F${paths[index]}`, paths[index]));
  }
  return previews;
}

@Component
export struct ProjectCard {
  @Prop summary: ProjectSummary = emptyProjectSummary();
  onOpen: () => void = (): void => {};

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text(this.summary.project.isPinned ? '◆' : '▦')
          .width(24)
          .fontSize(18)
          .fontColor(UiTokens.PRIMARY)
          .textAlign(TextAlign.Center)
        Column({ space: 4 }) {
          Text(this.summary.project.name)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(UiTokens.TEXT)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(projectSummaryText(this.summary))
            .fontSize(13)
            .fontColor(UiTokens.TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(lifecycleLabel(this.summary.project.lifecycleStatus))
          .fontSize(11)
          .fontColor(UiTokens.PRIMARY)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(UiTokens.PRIMARY_CONTAINER)
          .borderRadius(9)
      }
      .width('100%')
      if (this.summary.project.description.length > 0) {
        Text(this.summary.project.description)
          .fontSize(13)
          .fontColor(UiTokens.TEXT_SECONDARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      if (this.summary.recentRenderedPaths.length > 0) {
        Row({ space: 8 }) {
          ForEach(projectPreviewItems(this.summary.project.id, this.summary.recentRenderedPaths),
            (preview: ProjectPreviewItem) => {
              Stack() {
                AppImage({ uri: imageUri(preview.path),
                  decodeEdge: ImageDecodePolicy.thumbnail(56, this.getUIContext().vp2px(1)) })
                  .width(56)
                  .height(56)
              }
              .width(56)
              .height(56)
              .clip(true)
              .borderRadius(UiTokens.CONTROL_RADIUS)
              .accessibilityText(tr('项目最近照片', 'Recent project photo'))
            }, (preview: ProjectPreviewItem): string => preview.key)
          Blank()
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(UiTokens.SURFACE)
    .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
    .borderRadius(UiTokens.CARD_RADIUS)
    .shadow({ radius: 10, color: UiTokens.CARD_SHADOW, offsetY: 3 })
    .accessibilityText(`${this.summary.project.name}，${projectSummaryText(this.summary)}`)
    .onClick(this.onOpen)
  }
}
