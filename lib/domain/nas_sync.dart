/// NAS synchronization domain rules (decision D-023).
///
/// The upload target for one capture is
/// `{root}/{projectKey}/{fileName}` where `projectKey` is the sanitized
/// project name (the same rules that shape local photo file names) and
/// `fileName` is `{photoNumber}.jpg`. The remote location is derived at
/// upload time — never stored — so project renames only affect future
/// uploads, mirroring the local file-name contract.
library;

import 'package:sitemark/domain/photo_number.dart';

/// Upload bookkeeping states for one capture.
enum NasUploadStatus { pending, uploaded, failed }

/// Remote file name of the uploaded watermarked JPEG for [photoNumber].
String nasRemoteFileName(String photoNumber) => '$photoNumber.jpg';

/// Remote directory name for a project: the same sanitized name the local
/// photo file names use, so NAS browsing mirrors the local naming.
String nasProjectKey(String projectName) => safePhotoProjectName(projectName);
