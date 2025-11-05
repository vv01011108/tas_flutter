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
    final Color borderColor = danger ? Colors.red : Colors.orange;
    final Color iconColor   = borderColor;

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
                Icon(
                  danger ? Icons.dangerous : Icons.warning_amber_rounded,
                  size: 44,
                  color: iconColor,
                ),
                const SizedBox(height: 10),
                Text(
                  tasTitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
                if (tasSub != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    tasSub!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
    final Color signColor = flashOn ? Colors.white : Colors.amber.shade50;
    return CustomPaint(
      painter: _RoundedTrianglePainter(
        color: signColor,
        borderColor: borderColor,
        borderWidth: borderWidth,
        cornerRadius: cornerRadius,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 20 + borderWidth,
          vertical: 24 + borderWidth / 2,
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

    final top   = Offset(w / 2, 0);
    final left  = Offset(0, h);
    final right = Offset(w, h);

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
