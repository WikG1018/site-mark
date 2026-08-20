import domainRulesTest from './DomainRules.test';
import captureStateTest from './CaptureState.test';
import privacyConsentTest from './PrivacyConsent.test';
import imagePipelineTest from './ImagePipeline.test';
import publishJournalTest from './PublishJournal.test';
import serialCaptureQueueTest from './SerialCaptureQueue.test';
import captureSessionTest from './CaptureSession.test';
import restoreJournalTest from './RestoreJournal.test';
import albumPublishPolicyTest from './AlbumPublishPolicy.test';
import mediaCleanupTest from './MediaCleanup.test';
import appTextTest from './AppText.test';
import keyedOperationGateTest from './KeyedOperationGate.test';
import uiPolicyTest from './UiPolicy.test';
import lazyListDataSourceTest from './LazyListDataSource.test';
import capturePagedControllerTest from './CapturePagedController.test';
import photoViewerWindowTest from './PhotoViewerWindow.test';
import recordUiCoordinatorTest from './RecordUiCoordinator.test';

export default function testsuite(): void {
  domainRulesTest();
  captureStateTest();
  privacyConsentTest();
  imagePipelineTest();
  publishJournalTest();
  serialCaptureQueueTest();
  captureSessionTest();
  restoreJournalTest();
  albumPublishPolicyTest();
  mediaCleanupTest();
  appTextTest();
  keyedOperationGateTest();
  uiPolicyTest();
  lazyListDataSourceTest();
  capturePagedControllerTest();
  photoViewerWindowTest();
  recordUiCoordinatorTest();
}
