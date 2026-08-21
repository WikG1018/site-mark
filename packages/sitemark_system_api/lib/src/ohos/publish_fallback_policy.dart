enum PublishFallbackDecision { album, sandbox }

class PublishFallbackPolicy {
  static bool isUserCancelledPublish(Object? error) {
    if (error == null) return false;
    final message = '$error';
    return message.contains('cancelled') || message.contains('Canceled');
  }

  static PublishFallbackDecision decide({
    List<String>? destinations,
    Object? error,
  }) {
    if (error != null) return PublishFallbackDecision.sandbox;
    if (destinations == null || destinations.isEmpty) {
      return PublishFallbackDecision.sandbox;
    }
    return PublishFallbackDecision.album;
  }

  static bool shouldRethrow({List<String>? destinations, Object? error}) {
    decide(destinations: destinations, error: error);
    return false;
  }
}
