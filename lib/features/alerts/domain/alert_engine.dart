/* alerts/domain/alert_engine.dart (최종 수정) */
import 'package:google_maps_flutter/google_maps_flutter.dart';

// 🔑 [유일 정의]: AlertNode와 RoadSurface는 이 파일에서만 정의됩니다.
enum RoadSurface { dry, wet, icy }

class AlertNode {
  final LatLng p;
  final double recKmh;
  final RoadSurface surface;
  final String? description;
  const AlertNode(this.p, this.recKmh, this.surface, {this.description});
}
// -----------------------------------------------------

class AlertState {
  final AlertNode? current;
  final bool visible;
  final Set<Circle> circles;
  final int firstEnterPlayMs;
  final int lastSeenPlayMs; // 사용하지 않을 수 있으나 구조 유지를 위해 포함

  const AlertState({
    required this.current,
    required this.visible,
    required this.circles,
    required this.firstEnterPlayMs,
    required this.lastSeenPlayMs,
  });

  static AlertState initial() => const AlertState(
      current: null, visible: false, circles: {}, firstEnterPlayMs: 0, lastSeenPlayMs: 0);

  AlertState copyWith({
    AlertNode? current,
    bool? visible,
    Set<Circle>? circles,
    int? firstEnterPlayMs,
    int? lastSeenPlayMs,
  }) {
    return AlertState(
      current: current ?? this.current,
      visible: visible ?? this.visible,
      circles: circles ?? this.circles,
      firstEnterPlayMs: firstEnterPlayMs ?? this.firstEnterPlayMs,
      lastSeenPlayMs: lastSeenPlayMs ?? this.lastSeenPlayMs,
    );
  }
}

class AlertEngine {
  AlertState _state = AlertState.initial();

  AlertState get state => _state;

  void reset() {
    _state = AlertState.initial();
  }

  // 🟢 [추가]: map_page.dart에서 요구하는 clearAll() 메서드
  void clearAll() {
    reset(); // reset()을 호출하여 모든 경고 상태를 초기화합니다.
  }

  void showWarn(String description) {
    // 임시 AlertNode 생성 (실제 로직에 따라 수정 필요)
    final tempAlert = AlertNode(
      const LatLng(0, 0),
      60,
      RoadSurface.dry,
      description: description,
    );

    _state = _state.copyWith(
      current: tempAlert,
      visible: true,
      // circles 업데이트 로직...
    );
  }

  void clearWarn() {
    if (_state.current == null || _state.current?.description == null) return;

    _state = _state.copyWith(
      current: null,
      visible: false,
      circles: {},
    );
  }
}