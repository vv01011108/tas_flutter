/* trace. csv 로더 */
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../shared/time.dart';
import '../../shared/geo.dart';
import '../domain/trace_models.dart';

class TraceRepo {
  Future<TraceData> loadFromCsv(String assetPath) async {
    final raw   = await rootBundle.loadString(assetPath);
    final lines = raw.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();

    int startIdx = 0;
    if (lines.isNotEmpty) {
      final lower = lines.first.toLowerCase();
      if (lower.contains('datetime') && lower.contains('latitude')) startIdx = 1;
    }

    final pts    = <LatLng>[];
    final timeMs = <int>[];
    final spd    = <double>[];

    for (int i = startIdx; i < lines.length; i++) {
      final cols = smartSplitLine(lines[i]);
      if (cols.length < 4) continue;
      final tms = parseTimeMs(cols[0]);
      final lat = double.tryParse(cols[1]);
      final lon = double.tryParse(cols[2]);
      final v   = double.tryParse(cols[3]);
      if (tms == null || lat == null || lon == null || v == null) continue;

      final safeT = timeMs.isEmpty ? tms : (tms >= timeMs.last ? tms : timeMs.last + 1);
      timeMs.add(safeT);
      pts.add(LatLng(lat, lon));
      spd.add(v);
    }

    if (pts.length < 2) {
      throw StateError('CSV 포인트가 2개 미만입니다');
    }

    spreadSameMinuteBuckets(timeMs);

    final start = pts.first;
    final end   = pts.last;

    final startAddr = await _reverseGeocode(start);
    await Future.delayed(const Duration(milliseconds: 200));
    final endAddr   = await _reverseGeocode(end);

    return TraceData(
      pts: pts, timeMs: timeMs, spdKmh: spd,
      start: start, end: end, startAddr: startAddr, endAddr: endAddr,
    );
  }

  Future<String?> _reverseGeocode(LatLng p) async {
    final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${p.latitude}&lon=${p.longitude}');
    try {
      final res = await http.get(uri, headers: {'User-Agent': 'tas_app/1.0 (demo@example.com)'});
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        return (data['display_name'] as String?)?.trim();
      }
    } catch (_) {}
    return null;
  }
}
