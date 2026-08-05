int adaptiveSkeletonCount({
  required double viewportHeight,
  required double itemExtent,
  int min = 2,
  int max = 8,
}) {
  if (min < 0) {
    throw ArgumentError.value(min, 'min', 'must be non-negative');
  }
  if (max < 0) {
    throw ArgumentError.value(max, 'max', 'must be non-negative');
  }
  if (min > max) {
    throw ArgumentError('min must not exceed max');
  }
  if (!viewportHeight.isFinite ||
      viewportHeight <= 0 ||
      !itemExtent.isFinite ||
      itemExtent <= 0) {
    return min;
  }
  return (viewportHeight / itemExtent).ceil().clamp(min, max).toInt();
}
