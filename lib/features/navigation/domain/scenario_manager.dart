import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../navigation/domain/trace_models.dart';
import '../../shared/config.dart';

enum DriveScenario { rain, snow }

class ScenarioData {
  ScenarioData(this.scenario);
  final DriveScenario scenario;

  TraceData? trace;
  String? startAddrKr;
  String? endAddrKr;

  bool loading = false;
}

class ScenarioManager {
  // 초기값: loading=false (preload가 실행되도록)
  final Map<DriveScenario, ScenarioData> scenarios = {
    DriveScenario.rain: ScenarioData(DriveScenario.rain),
    DriveScenario.snow: ScenarioData(DriveScenario.snow),
  };

  String csvFor(DriveScenario s) =>
      s == DriveScenario.rain ? AppConfig.kTraceCsvRain! : AppConfig.kTraceCsvSnow!;

  /// CSV를 asset에서 읽어 TraceData로 만든 다음, 주소(있다면) 세팅
  Future<void> preload(
      DriveScenario s,
      Future<String?> Function(LatLng) krAddr,
      ) async {
    final slot = scenarios[s]!;
    if (slot.loading) return;

    slot.loading = true;
    slot.trace = null;
    slot.startAddrKr = null;
    slot.endAddrKr = null;

    try {
      final csvPath = csvFor(s); // ex) assets/rain_trace.csv
      final csvText = await rootBundle.loadString(csvPath);

      final trace = _parseCsvToTrace(csvText); // <- 클래스 내부 private 메서드
      if (!trace.isValid) {
        throw StateError('CSV 파싱 결과가 유효하지 않음: ${trace.pts.length} pts');
      }

      // 주소 조회는 실패 무시(타임아웃 5s)
      final startName = await _safeAddr(krAddr, trace.start);
      final endName = await _safeAddr(krAddr, trace.end);

      slot.trace = trace;
      slot.startAddrKr = startName ?? trace.startAddr ?? '출발지';
      slot.endAddrKr = endName ?? trace.endAddr ?? '도착지';
    } catch (e, st) {
      debugPrint('[preload] $s 실패: $e\n$st');
      slot.trace = null; // UI에서 실패 표시
    } finally {
      slot.loading = false; // 반드시 false로 내려줘야 UI가 풀림
    }
  }

  // ---------------------- 아래부터 private 메서드들 ----------------------

  Future<String?> _safeAddr(
      Future<String?> Function(LatLng) krAddr, LatLng p
      ) async {
    try {
      return await krAddr(p).timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }

  TraceData _parseCsvToTrace(String csvText) {
    // BOM 제거 + 라인 정리
    final cleaned = csvText.replaceAll('\ufeff', '');
    final lines = const LineSplitter()
        .convert(cleaned)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return TraceData(
        pts: const [],
        timeMs: const [],
        spdKmh: const [],
        start: const LatLng(0, 0),
        end: const LatLng(0, 0),
      );
    }

    // 구분자 자동감지(탭 우선)
    final String delim = lines.first.contains('\t') ? '\t' : ',';

    // 헤더 파싱
    final header = lines.first.split(delim).map((h) => h.trim().toLowerCase()).toList();
    int _idx(List<String> keys) {
      for (final k in keys) {
        final i = header.indexOf(k);
        if (i >= 0) return i;
      }
      return -1;
    }

    final iLat = _idx(['lat', 'latitude']);
    final iLng = _idx(['lng', 'lon', 'longitude']);
    if (iLat < 0 || iLng < 0) {
      return const TraceData(
        pts: [],
        timeMs: [],
        spdKmh: [],
        start: LatLng(0, 0),
        end: LatLng(0, 0),
      );
    }

    final iTimeMs = _idx(['time_ms', 'ms']);
    final iTimeGeneric = _idx(['datetime_kst', 'datetime', 'timestamp', 'time', 't', 'sec']);
    final iSpd = _idx(['speed_kmh', 'spd', 'kmh']);

    final pts = <LatLng>[];
    final timeMs = <int>[];
    final spdKmh = <double>[];

    for (int r = 1; r < lines.length; r++) {
      final cols = lines[r].split(delim);
      if (cols.length <= iLng) continue;

      final lat = double.tryParse(cols[iLat]);
      final lng = double.tryParse(cols[iLng]);
      if (lat == null || lng == null) continue;

      pts.add(LatLng(lat, lng));

      // 시간(ms)
      int? ms;
      if (iTimeMs >= 0 && cols.length > iTimeMs) {
        ms = int.tryParse(cols[iTimeMs]);
      } else if (iTimeGeneric >= 0 && cols.length > iTimeGeneric) {
        ms = _parseTimeLikeToMs(cols[iTimeGeneric].trim());
      }
      timeMs.add(ms ?? -1);

      // 속도(km/h)
      double? v;
      if (iSpd >= 0 && cols.length > iSpd) {
        v = double.tryParse(cols[iSpd]);
      }
      spdKmh.add(v ?? double.nan);
    }

    if (pts.length < 2) {
      return TraceData(
        pts: pts,
        timeMs: List<int>.filled(pts.length, 0),
        spdKmh: List<double>.filled(pts.length, 0.0),
        start: pts.isNotEmpty ? pts.first : const LatLng(0, 0),
        end: pts.isNotEmpty ? pts.last : const LatLng(0, 0),
      );
    }

    _fillTimeMsInPlace(timeMs);
    _fillSpeedInPlace(pts, timeMs, spdKmh);

    return TraceData(
      pts: pts,
      timeMs: timeMs,
      spdKmh: spdKmh,
      start: pts.first,
      end: pts.last,
      startAddr: null,
      endAddr: null,
    );
  }

  /// "2025-11-04 12:34:56" / "2025-11-04T12:34:56" / "123.4"(초) → ms
  int _parseTimeLikeToMs(String raw) {
    final s = raw.trim();

    // HH:MM:SS(.mmm)
    if (s.contains(':') && !s.contains('-') && s.length <= 12) {
      final seg = s.split(':');
      if (seg.length >= 2) {
        final hh = int.tryParse(seg[0]) ?? 0;
        final mm = int.tryParse(seg[1]) ?? 0;
        final ss = (seg.length >= 3 ? double.tryParse(seg[2]) : null) ?? 0.0;
        return (((hh * 3600) + (mm * 60) + ss) * 1000).round();
      }
    }

    // ISO 스타일 시도
    final d1 = DateTime.tryParse(s);
    if (d1 != null) return d1.millisecondsSinceEpoch;

    // 공백을 T로 바꿔 재시도
    if (s.contains(' ')) {
      final d2 = DateTime.tryParse(s.replaceFirst(' ', 'T'));
      if (d2 != null) return d2.millisecondsSinceEpoch;
    }

    // 그냥 숫자면 초로 간주
    final asNum = double.tryParse(s);
    if (asNum != null) return (asNum * 1000).round();

    return 0;
  }

  void _fillTimeMsInPlace(List<int> timeMs) {
    final n = timeMs.length;
    final missing = timeMs.where((v) => v == -1).length;

    if (missing == n) {
      for (int i = 0; i < n; i++) {
        timeMs[i] = i * 1000;
      }
      return;
    }
    // 일부만 -1이면 간단히 인덱스*1000으로 채움
    for (int i = 0; i < n; i++) {
      if (timeMs[i] == -1) {
        timeMs[i] = i * 1000;
      }
    }
  }

  void _fillSpeedInPlace(List<LatLng> pts, List<int> timeMs, List<double> spdKmh) {
    double haversineKm(LatLng a, LatLng b) {
      const R = 6371.0; // km
      final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
      final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
      final la1 = a.latitude * math.pi / 180.0;
      final la2 = b.latitude * math.pi / 180.0;
      final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
      final c = 2 * math.asin(math.sqrt(h));
      return R * c;
    }

    final n = pts.length;
    if (n == 0) return;

    spdKmh[0] = 0.0;
    for (int i = 1; i < n; i++) {
      if (spdKmh[i].isNaN) {
        final dtMs = (timeMs[i] - timeMs[i - 1]).clamp(1, 1 << 30);
        final dtH = dtMs / 3600000.0; // h
        final km = haversineKm(pts[i - 1], pts[i]);
        final v = dtH > 0 ? (km / dtH) : 0.0;
        spdKmh[i] = v.clamp(0.0, 130.0);
      }
    }
  }
}
