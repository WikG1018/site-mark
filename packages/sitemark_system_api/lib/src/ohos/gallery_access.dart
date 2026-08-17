enum GalleryAccessMode { acl, pickerFallback }

class GalleryAccessProbe {
  GalleryAccessProbe({required Future<bool> Function() reader})
    : _reader = reader;

  final Future<bool> Function() _reader;

  Future<GalleryAccessMode> detect() async {
    return await _reader()
        ? GalleryAccessMode.acl
        : GalleryAccessMode.pickerFallback;
  }
}
