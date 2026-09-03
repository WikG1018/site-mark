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

final _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

/// Whether [host] is a LAN / local-network NAS target.
///
/// Android 17 (targetSdk 37) requires the `ACCESS_LOCAL_NETWORK` runtime
/// permission before sockets to these destinations succeed. Public IPs and
/// public DNS names only need `INTERNET`.
bool isLanNasHost(String host) {
  final value = host.trim().toLowerCase();
  if (value.isEmpty) return false;
  if (value == 'localhost' || value == '::1') return true;
  if (value.endsWith('.local')) return true;
  if (!value.contains('.')) return true;
  if (value.contains(':') &&
      (value.startsWith('fe80:') ||
          value.startsWith('fc') ||
          value.startsWith('fd'))) {
    return true;
  }
  final match = _ipv4.firstMatch(value);
  if (match == null) return false;
  final a = int.parse(match.group(1)!);
  final b = int.parse(match.group(2)!);
  if (a == 10 || a == 127 || a == 0) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 169 && b == 254) return true;
  return false;
}
