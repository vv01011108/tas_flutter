class TasStatus {
  final double spd;
  final double latitude;
  final double longitude;
  final double maxSpd;
  final double rec;
  final int warn;
  final int? decelClass;

  TasStatus({
    required this.spd,
    required this.latitude,
    required this.longitude,
    required this.maxSpd,
    required this.rec,
    required this.warn,
    this.decelClass,
  });

  factory TasStatus.fromJson(Map<String, dynamic> j) {
    double _toD(dynamic v) => (v as num).toDouble();
    return TasStatus(
      spd: _toD(j['spd']),
      latitude: _toD(j['latitude']),
      longitude: _toD(j['longitude']),
      maxSpd: _toD(j['max_spd']),
      rec: _toD(j['rec']),
      warn: j['warn'] as int,
      decelClass: j['decel_class'] == null ? null : (j['decel_class'] as num).toInt(),
    );
  }
}
