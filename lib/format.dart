/// Formatting helpers. These are local on purpose so the UI never depends on
/// the shape of a helper inside the native package.
String fmtBytes(num bytes) {
  var value = bytes <= 0 ? 0.0 : bytes.toDouble();
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String fmtSpeed(num bytesPerSecond) => '${fmtBytes(bytesPerSecond)}/s';

String fmtClock(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String fmtWait(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) return '${seconds}s';
  return '${seconds ~/ 60}m ${seconds % 60}s';
}

String fmtEta(int remainingBytes, int bytesPerSecond) {
  if (remainingBytes <= 0) return 'done';
  if (bytesPerSecond <= 0) return '—';
  return fmtClock(Duration(seconds: remainingBytes ~/ bytesPerSecond));
}

String fmtAgo(int millisSinceEpoch) {
  if (millisSinceEpoch <= 0) return '';
  final then = DateTime.fromMillisecondsSinceEpoch(millisSinceEpoch);
  final diff = DateTime.now().difference(then);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${then.year}-${then.month.toString().padLeft(2, '0')}-${then.day.toString().padLeft(2, '0')}';
}
