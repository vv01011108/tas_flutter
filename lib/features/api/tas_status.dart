// lib/features/api/tas_status.dart
class TasStatus {
  final double spd;        // 현재 속도 (km/h)
  final double latitude;   // 위도
  final double longitude;  // 경도
  final double maxSpd;     // 제한 속도 (km/h)
  final double rec;        // 추천 속도 (km/h)
  final int warn;          // 0=정상, 1=감속 경고

  TasStatus({
    required this.spd,
    required this.latitude,
    required this.longitude,
    required this.maxSpd,
    required this.rec,
    required this.warn,
  });

  factory TasStatus.fromJson(Map<String, dynamic> j) {
    // 서버는 snake_case로 내려옴 (max_spd)
    double _toD(dynamic v) => (v as num).toDouble();
    return TasStatus(
      spd: _toD(j['spd']),
      latitude: _toD(j['latitude']),
      longitude: _toD(j['longitude']),
      maxSpd: _toD(j['max_spd']),
      rec: _toD(j['rec']),
      warn: j['warn'] as int,
    );
  }
}
