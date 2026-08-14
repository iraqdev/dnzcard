int compareAppVersions(String current, String minimum) {
  final currentParts = _parseVersionParts(current);
  final minimumParts = _parseVersionParts(minimum);
  final length = currentParts.length > minimumParts.length
      ? currentParts.length
      : minimumParts.length;

  for (var i = 0; i < length; i++) {
    final a = i < currentParts.length ? currentParts[i] : 0;
    final b = i < minimumParts.length ? minimumParts[i] : 0;
    if (a != b) return a.compareTo(b);
  }
  return 0;
}

bool isAppVersionBelowMinimum(String current, String minimum) {
  final min = minimum.trim();
  if (min.isEmpty) return false;
  return compareAppVersions(current.trim(), min) < 0;
}

List<int> _parseVersionParts(String raw) {
  final normalized = raw.split('+').first.trim();
  if (normalized.isEmpty) return const [0];
  return normalized
      .split('.')
      .map((part) => int.tryParse(part.trim()) ?? 0)
      .toList();
}
