/* 속도/시간 HUD 위젯 */
import 'package:flutter/material.dart';

/// 공용 HUD 박스(원본 스타일)
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

/* ───────── HUD 전용 재사용 위젯 두 개 ───────── */

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
        Stack( // 테두리와 채우기를 위해 Stack으로 감싸 두 개의 Text를 겹침
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
                  ..strokeWidth = 6.0           // 테두리 두께
                  ..color = Colors.white,         // 테두리 색상
              ),
            ),

            // 2. 글자 내부 채우기
            Text(
              '${kmh.toInt()}',
              style: const TextStyle(
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// 제한 속도 표지 HUD (좌하단 배치용)
class SpeedLimitHud extends StatelessWidget {
  final int? maxSpd; // null이면 '--'로 표시

  const SpeedLimitHud({super.key, this.maxSpd});
  
  @override
  Widget build(BuildContext context) {
    final text = maxSpd != null ? '$maxSpd' : '--';

    return Stack(
      clipBehavior: Clip.none, // 겹치기 허용
      alignment: Alignment.center,
      children: [
        // 제한 속도 원판
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.red, width: 6),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ),

        // 아래 "제한 속도" 텍스트 박스
        Positioned(
          bottom: -15, // 겹치는 정도
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(4),
            ),

            child: const Text(
              '제한 속도',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}