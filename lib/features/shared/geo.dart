/* haversine, bearing, lerp (최단 거리) */
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

LatLng lerpLatLng(LatLng a, LatLng b, double t) => LatLng(
  a.latitude + (b.latitude - a.latitude) * t,
  a.longitude + (b.longitude - a.longitude) * t,
);

double bearingDegBetween(LatLng a, LatLng b) {
  final lat1 = a.latitude * math.pi / 180.0;
  final lat2 = b.latitude * math.pi / 180.0;
  final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  var brng = math.atan2(y, x) * 180.0 / math.pi;
  if (brng < 0) brng += 360.0;
  return brng;
}

double smoothBearing(double current, double target, {double alpha = 0.25}) {
  double delta = target - current;
  delta = (delta + 540.0) % 360.0 - 180.0;
  return (current + alpha * delta + 360.0) % 360.0;
}

double haversineM(LatLng a, LatLng b) {
  const R = 6371000.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
  final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
  final lat1 = a.latitude * math.pi / 180.0;
  final lat2 = b.latitude * math.pi / 180.0;
  final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.sin(dLon / 2) * math.sin(dLon / 2) * math.cos(lat1) * math.cos(lat2);
  return 2 * R * math.atan2(math.sqrt(x), math.sqrt(1 - x));
}

LatLngBounds boundsFrom(List<LatLng> pts) {
  double minLat = pts.first.latitude, maxLat = pts.first.latitude;
  double minLng = pts.first.longitude, maxLng = pts.first.longitude;
  for (final p in pts) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }
  return LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
}

double easeSmoothstep(double u) => u*u*(3-2*u);

