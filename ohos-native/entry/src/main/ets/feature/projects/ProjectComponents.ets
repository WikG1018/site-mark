import { ProjectRecord, ProjectSummary } from '../../domain/Models';
import { ProjectLifecycleStatus } from '../../domain/StateMachine';
import { tr } from '../../shared/AppText';
import { formatDateTime, imageUri, lifecycleLabel } from '../../shared/Formatters';
import { UiTokens } from '../../shared/UiTokens';

function emptyProjectSummary(): ProjectSummary {
  return new ProjectSummary(new ProjectRecord({
    id: '', name: '', description: '', lifecycleStatus: ProjectLifecycleStatus.ACTIVE,
    isPinned: false, watermarkPosition: 'bottomLeft', watermarkOpacity: 0.82,
    watermarkAccentColorArgb: 0xFF176B55, watermarkFontScale: 1, createdAt: 0, updatedAt: 0
  }), 0, 0, 0, 0, []);
}

export function projectCardKey(item: ProjectSummary): string {
  return `${item.project.id}\u001F${item.project.updatedAt}\u001F${item.captureCount}` +
    `\u001F${item.readyCount}\u001F${item.pendingCount}\u001F${item.latestCaptureAt}` +
    `\u001F${item.recentRenderedPaths.join('\u001F')}`;
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
          ForEach(this.summary.recentRenderedPaths.slice(0, 3), (path: string) => {
            Stack() {
              Row()
                .width(56)
                .height(56)
                .backgroundColor(UiTokens.IMAGE_PLACEHOLDER)
              Image(imageUri(path))
                .width(56)
                .height(56)
                .sourceSize({ width: 112, height: 112 })
                .objectFit(ImageFit.Cover)
            }
            .width(56)
            .height(56)
            .clip(true)
            .borderRadius(UiTokens.CONTROL_RADIUS)
          }, (path: string): string => path)
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
