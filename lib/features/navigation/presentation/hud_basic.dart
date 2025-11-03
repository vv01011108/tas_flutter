/* 속도/시간 HUD 위젯 */
import 'package:flutter/material.dart';
// LatLngLite를 start_end_card.dart에서 가져옵니다.
import '../../navigation/presentation/widgets/start_end_card.dart';

/// 공용 HUD 박스(네 원본 스타일)
Widget hudBox({required Widget child}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.55),
      borderRadius: BorderRadius.circular(10),
    ),
    child: DefaultTextStyle(
      style: const TextStyle(color: Colors.white),
      child: child,
    ),
  );
}

/* ───────── 추가: HUD 전용 재사용 위젯 두 개 ───────── */

/// 스피드만 보여주는 HUD (컴파스 바로 아래 배치용)
class SpeedHud extends StatelessWidget {
  final double kmh;
  const SpeedHud({super.key, required this.kmh});

  @override
  Widget build(BuildContext context) {
    return hudBox(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.speed, size: 18, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            '${kmh.toStringAsFixed(1)} km/h',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// 좌표 + 주행시간을 함께 보여주는 HUD (좌하단 배치용)
class CoordTimeHud extends StatelessWidget {
  final LatLngLite? pos; // LatLngLite 사용
  final String elapsed; // "mm:ss" 형태를 넘겨주세요.

  const CoordTimeHud({
    super.key,
    required this.pos,
    required this.elapsed,
  });

  @override
  Widget build(BuildContext context) {
    final latStr = pos == null ? '—' : pos!.latitude.toStringAsFixed(6);
    final lngStr = pos == null ? '—' : pos!.longitude.toStringAsFixed(6);

    return hudBox(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place, size: 16, color: Colors.white70),
          const SizedBox(width: 4),
          Text('lat $latStr, lng $lngStr', style: const TextStyle(color: Colors.white70)),

          const SizedBox(width: 10),
          const Icon(Icons.timer, size: 16, color: Colors.white70),
          const SizedBox(width: 4),
          Text(elapsed, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}