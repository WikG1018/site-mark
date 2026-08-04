int adaptiveSkeletonCount({
  required double viewportHeight,
  required double itemExtent,
  int min = 2,
  int max = 8,
}) {
  if (!viewportHeight.isFinite ||
      viewportHeight <= 0 ||
      !itemExtent.isFinite ||
      itemExtent <= 0) {
    return min;
  }
  return (viewportHeight / itemExtent).ceil().clamp(min, max).toInt();
}
