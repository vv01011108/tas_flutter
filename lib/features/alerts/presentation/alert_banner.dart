/* 배너 UI - 둥근 모서리 정삼각형 경고 표지판 + 에셋 아이콘 */
import 'package:flutter/material.dart';
import '../../shared/config.dart';
import '../domain/alert_engine.dart';

class AlertBanner extends StatelessWidget {
  final bool visible;
  final AlertNode? alert; // 기존 경고(Fallback) — 이제는 표시 안 함
  final double curKmh;
  final int playMs;
  final int firstEnterPlayMs;

  final String? tasTitle;   // "도로 주의 구간" / "위험 구간" 등
  final String? tasSub;     // "25 km/h 이하로 서행" 등
  final int? severity;      // 1=주의(오렌지), 2=위험(레드) — 이것만 표시

  const AlertBanner({
    super.key,
    required this.visible,
    required this.alert,
    required this.curKmh,
    required this.playMs,
    required this.firstEnterPlayMs,
    this.tasTitle,
    this.tasSub,
    this.severity,
  });

  bool get _isActive => severity == 1 || severity == 2;

  @override
  Widget build(BuildContext context) {
    // severity가 1/2가 아니면 아예 표시하지 않음 (기본/검은 테두리 배너 차단)
    if (!visible || !_isActive || tasTitle == null) {
      return const SizedBox.shrink();
    }

    final flashing = ((playMs - firstEnterPlayMs) ~/ AppConfig.alertFlashMs) % 2 == 0;

    // 테두리/아이콘 색상
    final bool danger = severity == 2;
    final Color borderColor = danger ? Colors.red : Colors.deepOrangeAccent;
    // final Color iconColor   = borderColor;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      offset: visible ? Offset.zero : const Offset(0, -1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 100),
        opacity: visible ? 1 : 0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
          child: _RoundedTriangleSign(
            flashOn: flashing,
            borderWidth: 15,
            cornerRadius: 18,
            borderColor: borderColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                
                // 경고판 안 텍스트 위치 조정
                const SizedBox(height: 80),
                Icon(
                  danger ? Icons.dangerous : Icons.warning_amber_rounded,
                  size: 44,
                  color: borderColor,
                ),
                const SizedBox(height: 8),
                Stack(
                  alignment: Alignment.center,
                  children: [

                    // 1. 아래 텍스트: 인위적으로 굵기를 더하는 Stroke 역할
                    Text(
                      tasTitle!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,

                        // 검은색 테두리/스트로크를 아주 얇게 적용하여 굵기를 보강
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = 0.9 // 굵기 보강용 얇은 스트로크 (원하는 값으로 조절)
                          ..color = Colors.black,
                      ),
                    ),

                    // 2. 위 텍스트: 내부 채우기 역할 (w900 굵기 유지)
                    Text(
                      tasTitle!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                if (tasSub != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    tasSub!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundedTriangleSign extends StatelessWidget {
  final Widget child;
  final bool flashOn;
  final double borderWidth;
  final double cornerRadius;
  final Color borderColor;

  const _RoundedTriangleSign({
    required this.child,
    required this.flashOn,
    required this.borderWidth,
    required this.cornerRadius,
    this.borderColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    final Color signColor = flashOn ? Colors.white : Colors.amber.shade200;
    return CustomPaint(
      painter: _RoundedTrianglePainter(
        color: signColor,
        borderColor: borderColor,
        borderWidth: borderWidth,
        cornerRadius: cornerRadius,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          // 경고판 패딩
          horizontal: 24 + borderWidth,
          vertical: 20 + borderWidth / 2,
        ),
        child: child,
      ),
    );
  }
}

class _RoundedTrianglePainter extends CustomPainter {
  final Color color;
  final Color borderColor;
  final double borderWidth;
  final double cornerRadius;

  _RoundedTrianglePainter({
    required this.color,
    required this.borderColor,
    required this.borderWidth,
    required this.cornerRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. 삼각형의 높이를 고정 (예: 캔버스 높이 전체를 사용한다고 가정)
    final triangleHeight = h;

    // 2. 이동시킬 거리를 정의
    final offset_y = 60.0; // 원하는 만큼 아래로 이동 (50.0 예시)

    // 3. 꼭짓점 좌표를 재정의
    // - top: (캔버스 중앙) + offset_y
    final top   = Offset(w / 2, 0 + offset_y);

    // - left/right: (top.y + 고정된 삼각형 높이)로 계산하여 높이를 유지
    final bottom_y = -60 + triangleHeight + offset_y;

    final left  = Offset(0, bottom_y);
    final right = Offset(w, bottom_y);

    // 하지만, 이 값이 캔버스 높이(h)를 넘으면 안 됨
    // 캔버스 안에서 삼각형 크기를 줄여야 함 (예시: 삼각형 높이를 캔버스 높이의 80%로 가정)

    // final fixedTriangleHeight = h * 0.8; // 삼각형 높이를 캔버스 높이의 80%로 고정
    // final top_y = 0 + offset_y;
    // final bottom_y_fixed = top_y + fixedTriangleHeight;
    //
    // // 최종 수정된 좌표
    // final final_top = Offset(w / 2, top_y);
    // final final_left = Offset(0, bottom_y_fixed);
    // final final_right = Offset(w, bottom_y_fixed);

    final path = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(left.dx, left.dy)
      ..close();

    final fill = Paint()..color = color;
    canvas.drawPath(path, fill);

    final strokePaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _RoundedTrianglePainter old) {
    return old.color != color ||
        old.borderColor != borderColor ||
        old.borderWidth != borderWidth ||
        old.cornerRadius != cornerRadius;
  }
}
