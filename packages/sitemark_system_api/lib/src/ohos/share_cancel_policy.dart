class ShareCancelPolicy {
  static bool isUserCancelled(Object? error) {
    if (error == null) return false;
    final message = '$error';
    return message.contains('cancelled') || message.contains('Canceled');
  }
}
