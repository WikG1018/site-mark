import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AbilityContextHolder } from '../app/AbilityContextHolder';

@Entry
@Component
struct Index {
  @State private status: string = 'API 22 / x86_64 模拟器技术探测';
  @State private publishedUri: string = '';

  private abilityContext(): common.UIAbilityContext {
    return AbilityContextHolder.require();
  }

  private errorText(error: Error | BusinessError): string {
    const businessError = error as BusinessError;
    return `${businessError.code ?? 'unknown'} ${businessError.message ?? String(error)}`;
  }

  private async probeFileUri(): Promise<string> {
    const context = this.abilityContext();
    const targetPath = `${context.filesDir}/probe.jpg`;
    const source = await context.resourceManager.getRawFileContent('probe.jpg');
    const target = fileIo.openSync(
      targetPath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
    );
    try {
      fileIo.writeSync(target.fd, source.buffer);
    } finally {
      fileIo.closeSync(target);
    }
    return fileUri.getUriFromPath(targetPath);
  }

  private async runCameraProbe(): Promise<void> {
    this.status = '正在拉起系统相机…';
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const result = await cameraPicker.pick(
        this.abilityContext(),
        [cameraPicker.PickerMediaType.PHOTO],
        profile
      );
      this.status = `相机 resultCode=${result.resultCode}, uri=${result.resultUri || '(空)'}`;
    } catch (error) {
      this.status = `相机失败：${this.errorText(error as BusinessError)}`;
    }
  }

  private async runAlbumProbe(): Promise<void> {
    this.status = '正在拉起相册保存确认…';
    try {
      const sourceUri = await this.probeFileUri();
      const helper = photoAccessHelper.getPhotoAccessHelper(this.abilityContext());
      const config: photoAccessHelper.PhotoCreationConfig = {
        title: `SiteMark-Probe-${Date.now()}`,
        fileNameExtension: 'jpg',
        photoType: photoAccessHelper.PhotoType.IMAGE
      };
      const uris = await helper.showAssetsCreationDialog([sourceUri], [config]);
      this.publishedUri = uris.length > 0 ? uris[0] : '';
      this.status = `相册保存返回 ${uris.length} 项：${this.publishedUri || '(用户取消)'}`;
    } catch (error) {
      this.status = `相册保存失败：${this.errorText(error as BusinessError)}`;
    }
  }

  private async runDeleteProbe(): Promise<void> {
    if (this.publishedUri.length === 0) {
      this.status = '请先完成“相册保存”探测。';
      return;
    }
    this.status = '正在请求删除刚才保存的探测照片…';
    try {
      await photoAccessHelper.MediaAssetChangeRequest.deleteAssets(
        this.abilityContext(),
        [this.publishedUri]
      );
      this.status = '删除请求已完成。';
      this.publishedUri = '';
    } catch (error) {
      this.status = `删除失败/拒绝：${this.errorText(error as BusinessError)}`;
    }
  }

  private async runSettingsProbe(): Promise<void> {
    this.status = '正在打开应用详情…';
    try {
      const context = this.abilityContext();
      await context.startAbility({
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'application_info_entry',
        parameters: {
          'pushParams': context.applicationInfo.name
        }
      });
      this.status = '应用详情页已打开。';
    } catch (error) {
      this.status = `应用详情失败：${this.errorText(error as BusinessError)}`;
    }
  }

  private async runLinkProbe(): Promise<void> {
    this.status = '正在打开 GitHub 链接…';
    try {
      await this.abilityContext().openLink('https://github.com/WikG1018/site-mark');
      this.status = 'openLink 调用成功。';
    } catch (error) {
      this.status = `openLink 失败：${this.errorText(error as BusinessError)}`;
    }
  }

  private async runDocumentSaveProbe(): Promise<void> {
    this.status = '正在打开备份保存选择器…';
    try {
      const documentPicker = new picker.DocumentViewPicker(this.abilityContext());
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = ['SiteMark-Probe.zip'];
      options.fileSuffixChoices = ['ZIP|.zip'];
      const uris = await documentPicker.save(options);
      this.status = `文件保存选择器返回 ${uris.length} 项。`;
    } catch (error) {
      this.status = `文件保存取消/失败：${this.errorText(error as BusinessError)}`;
    }
  }

  @Builder
  private probeButton(label: string, action: () => Promise<void>) {
    Button(label)
      .width('100%')
      .height(52)
      .fontSize(16)
      .onClick(() => action())
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('SiteMark 原生能力探测')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .width('100%')
        Text(this.status)
          .fontSize(14)
          .fontColor('#385147')
          .padding(14)
          .backgroundColor('#EAF8F1')
          .borderRadius(16)
          .width('100%')
        this.probeButton('1. 系统相机 CameraPicker', () => this.runCameraProbe())
        this.probeButton('2. 相册保存确认', () => this.runAlbumProbe())
        this.probeButton('3. 删除相册探测照片', () => this.runDeleteProbe())
        this.probeButton('4. 应用详情设置页', () => this.runSettingsProbe())
        this.probeButton('5. 浏览器打开 GitHub', () => this.runLinkProbe())
        this.probeButton('6. DocumentViewPicker 保存 ZIP', () => this.runDocumentSaveProbe())
      }
      .padding({ left: 20, right: 20, top: 28, bottom: 28 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7FBF8')
  }
}
