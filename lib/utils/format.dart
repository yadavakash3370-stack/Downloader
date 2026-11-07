String formatBytes(int bytes) {
  if (bytes <= 0) return '—';
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  final String text =
      (value >= 100 || index == 0) ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$text ${units[index]}';
}

String formatDuration(int seconds) {
  if (seconds <= 0) return '--:--';
  final int h = seconds ~/ 3600;
  final int m = (seconds % 3600) ~/ 60;
  final int s = seconds % 60;
  final String mm = m.toString().padLeft(2, '0');
  final String ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

String formatEta(int seconds) {
  if (seconds <= 0) return '';
  if (seconds < 60) return '${seconds}s left';
  final int m = seconds ~/ 60;
  final int s = seconds % 60;
  return '${m}m ${s}s left';
}

String formatDate(DateTime value) {
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final DateTime local = value.toLocal();
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year}, $hour:$minute';
}

String fileNameOf(String path) {
  final int index = path.lastIndexOf('/');
  return index < 0 ? path : path.substring(index + 1);
}
