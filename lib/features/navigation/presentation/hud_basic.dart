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

    const double fontSize = 40.0;
    const FontWeight fontWeight = FontWeight.w900;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack( // 테두리와 채우기를 위해 Stack으로 감싸 두 개의 Text를 겹칩니다.
          alignment: Alignment.center,
          children: [
            // 1. 아래 텍스트: 테두리(Stroke) 역할
            Text(
              '${kmh.toInt()}',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: fontWeight,
                // 테두리 스타일 정의 (빨간색)
                foreground: Paint()
                  ..style = PaintingStyle.stroke // 스타일을 '테두리'로 설정
                  ..strokeWidth = 6.0           // 테두리 두께 (2.0에서 4.0으로 늘려 테두리가 더 잘 보이게 했습니다.)
                  ..color = Colors.white,         // 테두리 색상
              ),
            ),

            // 2. 위 텍스트: 채우기(Fill) 역할
            Text(
              '${kmh.toInt()}',
              style: const TextStyle(
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: Colors.black,           // 글자 내부 채우기 색상 (흰색으로 설정)
              ),
            ),
          ],
        ),
      ],
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