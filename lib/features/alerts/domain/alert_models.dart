/* 경고 모델 (데이터 전용) */
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum RoadSurface { dry, wet, icy }

class AlertNode {
  final LatLng p;
  final double recKmh;
  final RoadSurface surface;

  const AlertNode(this.p, this.recKmh, this.surface);
}
