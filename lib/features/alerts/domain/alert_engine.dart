import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../shared/config.dart';
import '../../shared/geo.dart';
import 'alert_models.dart';

class AlertState {
  final AlertNode? current;
  final bool visible;
  final Set<Circle> circles;
  final int firstEnterPlayMs;
  final int lastSeenPlayMs;

  const AlertState({
    required this.current,
    required this.visible,
    required this.circles,
    required this.firstEnterPlayMs,
    required this.lastSeenPlayMs,
  });

  AlertState copyWith({
    AlertNode? current,
    bool? visible,
    Set<Circle>? circles,
    int? firstEnterPlayMs,
    int? lastSeenPlayMs,
  }) => AlertState(
    current: current ?? this.current,
    visible: visible ?? this.visible,
    circles: circles ?? this.circles,
    firstEnterPlayMs: firstEnterPlayMs ?? this.firstEnterPlayMs,
    lastSeenPlayMs: lastSeenPlayMs ?? this.lastSeenPlayMs,
  );

  static AlertState initial() => const AlertState(
      current: null, visible: false, circles: {}, firstEnterPlayMs: 0, lastSeenPlayMs: 0);
}

class AlertEngine {
  final List<AlertNode> _nodes;
  AlertState _state = AlertState.initial();
  AlertEngine(this._nodes);

  AlertState get state => _state;

  // 👇 추가
  void replaceNodes(List<AlertNode> nodes) {
    _nodes
      ..clear()
      ..addAll(nodes);
    // 필요시 현재 경고 상태 초기화
    // _state = AlertState.initial(); // 상태를 리셋하고 싶으면 주석 해제
  }

  void reset() => _state = AlertState.initial();

  void _setAlertCircle(AlertNode a) {
    _state = _state.copyWith(circles: {
      Circle(
        circleId: const CircleId('alert'),
        center: a.p,
        radius: AppConfig.alertEnterM,
        strokeWidth: 2,
        strokeColor: switch (a.surface) {
          RoadSurface.icy => Colors.cyanAccent,
          RoadSurface.wet => Colors.lightBlueAccent,
          RoadSurface.dry => Colors.amberAccent,
        },
        fillColor: switch (a.surface) {
          RoadSurface.icy => Colors.cyanAccent.withOpacity(0.15),
          RoadSurface.wet => Colors.lightBlueAccent.withOpacity(0.15),
          RoadSurface.dry => Colors.amberAccent.withOpacity(0.12),
        },
      )
    });
  }

  void update({required LatLng pos, required int playMs}) {
    final cur = _state.current;

    // 1) 기존 알림 유지
    if (cur != null) {
      final dPrev = haversineM(pos, cur.p);
      if (dPrev <= AppConfig.alertExitM) {
        _state = _state.copyWith(visible: true, lastSeenPlayMs: playMs);
        _setAlertCircle(cur);
        return;
      }
    }

    // 2) 새 진입(가장 가까운 노드)
    double bestD = 1e9;
    AlertNode? best;
    for (final a in _nodes) {
      final d = haversineM(pos, a.p);
      if (d < bestD && d <= AppConfig.alertEnterM) { bestD = d; best = a; }
    }
    if (best != null) {
      final enteringNew = cur != best;
      _state = _state.copyWith(
        current: best,
        visible: true,
        lastSeenPlayMs: playMs,
        firstEnterPlayMs: enteringNew ? playMs : _state.firstEnterPlayMs,
      );
      _setAlertCircle(best);
      return;
    }

    // 3) 벗어나면 잔류시간 뒤 숨김
    if (_state.visible && (playMs - _state.lastSeenPlayMs) > AppConfig.alertLingerMs) {
      _state = AlertState.initial();
    }
  }
}
