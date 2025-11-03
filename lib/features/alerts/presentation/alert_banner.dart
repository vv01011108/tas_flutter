/* 배너 UI - 둥근 모서리 정삼각형 경고 표지판 + 에셋 아이콘 */
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../shared/config.dart';
// 🔑 [수정]: AlertNode 타입 정의는 alert_engine.dart에서 가져옵니다.
import '../domain/alert_engine.dart';

class AlertBanner extends StatelessWidget {
  final bool visible;
  final AlertNode? alert; // alert_engine.dart의 AlertNode 사용
  final double curKmh;
  final int playMs;
  final int firstEnterPlayMs;

  const AlertBanner({
    super.key,
    required this.visible,
    required this.alert,
    required this.curKmh,
    required this.playMs,
    required this.firstEnterPlayMs,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible || alert == null) return const SizedBox.shrink();
    final a = alert!;
    final isTasWarning = a.description != null;
    final flashing = ((playMs - firstEnterPlayMs) ~/ AppConfig.alertFlashMs) % 2 == 0;

    final String title = isTasWarning ? a.description! : '주의 구간';

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 52, color: Colors.amber),

                const SizedBox(height: 12),

                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),

                const SizedBox(height: 8),
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

  const _RoundedTriangleSign({
    required this.child,
    required this.flashOn,
    required this.borderWidth,
    required this.cornerRadius,
  });

  @override
  Widget build(BuildContext context) {
    // flashOn 값에 따라 color를 미리 계산하여 Painter에 전달
    final Color signColor = flashOn ? Colors.white : Colors.amber.shade50;

    return CustomPaint(
      painter: _RoundedTrianglePainter(
        color: signColor, // 계산된 color 전달
        borderColor: Colors.black,
        borderWidth: borderWidth,
        cornerRadius: cornerRadius,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20 + borderWidth, vertical: 24 + borderWidth / 2),
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
    final path = Path();

    final top = Offset(w / 2, 0);
    final left = Offset(0, h);
    final right = Offset(w, h);

    // Path 정의 (정삼각형 모양)
    path.moveTo(top.dx, top.dy + cornerRadius);
    path.arcToPoint(Offset(top.dx + cornerRadius * math.tan(math.pi / 6), top.dy + cornerRadius / math.cos(math.pi / 6)), radius: Radius.circular(cornerRadius));
    path.lineTo(right.dx - cornerRadius, right.dy);
    path.arcToPoint(Offset(right.dx - cornerRadius * math.sin(math.pi / 3), right.dy - cornerRadius * math.cos(math.pi / 3)), radius: Radius.circular(cornerRadius));
    path.lineTo(left.dx + cornerRadius * math.sin(math.pi / 3), left.dy - cornerRadius * math.cos(math.pi / 3));
    path.arcToPoint(Offset(left.dx + cornerRadius, left.dy), radius: Radius.circular(cornerRadius));
    path.lineTo(top.dx - cornerRadius * math.tan(math.pi / 6), top.dy + cornerRadius / math.cos(math.pi / 6));
    path.close();

    canvas.drawPath(path, Paint()..color = color);

    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _RoundedTrianglePainter oldDelegate) {
    // 🔑 [수정]: 'flashOn' 게터 오류를 해결하기 위해 'color'의 변경 여부만 확인합니다.
    return oldDelegate.color != color;
  }
}