/* 일시정지, 재시작 */

int? parseTimeMs(String s) {
  s = s.trim();

  final n = int.tryParse(s);
  if (n != null) {
    if (n > 1000000000000) return n;      // ms
    if (n > 1000000000) return n * 1000;  // sec -> ms
  }

  final mFull = RegExp(r'^(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(s);
  if (mFull != null) {
    final y  = int.parse(mFull.group(1)!);
    final mo = int.parse(mFull.group(2)!);
    final d  = int.parse(mFull.group(3)!);
    final h  = int.parse(mFull.group(4)!);
    final mi = int.parse(mFull.group(5)!);
    final se = int.parse(mFull.group(6) ?? '0');
    return DateTime(y, mo, d, h, mi, se).millisecondsSinceEpoch;
  }
  try {
    return DateTime.parse(s.replaceFirst(' ', 'T')).millisecondsSinceEpoch;
  } catch (_) {}
  return null;
}

List<String> smartSplitLine(String line) {
  final s = line.replaceAll('\ufeff', '').replaceAll('\u00A0', ' ').trim();
  final byDelims =
  s.split(RegExp(r'[,\t;]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
  if (byDelims.length >= 4) return byDelims;

  final p = s.split(RegExp(r'\s+'));
  if (p.length >= 4) {
    final dt  = '${p[0]} ${p[1]}';
    final lat = p[2];
    final lon = p[3];
    final spd = (p.length > 4) ? p[4] : '';
    return [dt, lat, lon, spd];
  }
  return const [];
}

void spreadSameMinuteBuckets(List<int> timeMs) {
  if (timeMs.isEmpty) return;
  int i = 0;
  while (i < timeMs.length) {
    int j = i;
    final minuteStart = timeMs[i] - (timeMs[i] % 60000);
    while (j + 1 < timeMs.length) {
      final nm = timeMs[j + 1] - (timeMs[j + 1] % 60000);
      if (nm != minuteStart) break;
      j++;
    }
    if (j > i) {
      final n = j - i + 1;
      for (int k = 0; k < n; k++) {
        timeMs[i + k] = minuteStart + (60000 * k) ~/ n;
      }
    } else {
      timeMs[i] = minuteStart;
    }
    i = j + 1;
  }
  for (int k = 1; k < timeMs.length; k++) {
    if (timeMs[k] <= timeMs[k - 1]) timeMs[k] = timeMs[k - 1] + 1;
  }
}

String fmtKst(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

