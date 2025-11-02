/* TracePoint 등 */
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TraceData {
  final List<LatLng> pts;
  final List<int> timeMs;
  final List<double> spdKmh;
  final LatLng start;
  final LatLng end;
  final String? startAddr;
  final String? endAddr;

  const TraceData({
    required this.pts,
    required this.timeMs,
    required this.spdKmh,
    required this.start,
    required this.end,
    this.startAddr,
    this.endAddr,
  });

  bool get isValid => pts.length >= 2 && timeMs.length == pts.length && spdKmh.length == pts.length;
}
