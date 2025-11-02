/* 배너 UI - 둥근 모서리 정삼각형 경고 표지판 + 에셋 아이콘 */
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../shared/config.dart';
import '../domain/alert_models.dart';

class AlertBanner extends StatelessWidget {
  final bool visible;
  final AlertNode? alert;
  final double curKmh; // 표시에는 쓰지 않지만 계산용으로 유지
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
    final flashing = ((playMs - firstEnterPlayMs) ~/ AppConfig.alertFlashMs) % 2 == 0;

    // 상태별 문구 & 아이콘(에셋)
    final String title = switch (a.surface) {
      RoadSurface.wet => '도로 젖음 구간',
      RoadSurface.icy => '도로 결빙 구간',
      RoadSurface.dry => '주의 구간',
    };

    final String? iconAsset = switch (a.surface) {
      RoadSurface.wet => 'assets/icons/rain.png',
      RoadSurface.icy => 'assets/icons/snow.png',
      RoadSurface.dry => null, // 에셋 없으면 기본 아이콘 폴백
    };

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
            cornerRadius: 18, // 삼각형 모서리 라디우스
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 에셋 아이콘(없으면 기본 경고)
                if (iconAsset != null)
                  Image.asset(iconAsset, width: 70, height: 70, fit: BoxFit.contain)
                else
                  const Icon(Icons.warning_amber_rounded, size: 52, color: Colors.red),

                const SizedBox(height: 12),

                // 1) 상태 문구
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),

                const SizedBox(height: 8),

                // 2) 권장 속도 안내
                Text(
                  '${a.recKmh.toStringAsFixed(0)} km/h 이하로 서행',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
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
  final bool flashOn;            // 삼각형 전체 깜빡임
  final double borderWidth;
  final double cornerRadius;

  const _RoundedTriangleSign({
    required this.child,
    required this.flashOn,
    this.borderWidth = 8,
    this.cornerRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    // 원하는 사이즈로 직접 제어
    const double w = 300;
    const double h = 270;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: flashOn ? 1.0 : 0.55,  // 삼각형 전체 깜빡임
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(w, h),  // 페인터도 동일 크기
              painter: _RoundedTrianglePainter(
                borderColor: Colors.red,      // 테두리: 불투명 빨강
                fillColor: Colors.red[200]!,  // 배경: 연한 빨강(불투명)
                borderWidth: borderWidth,
                radius: cornerRadius,
              ),
            ),
            // 내부 패딩: 꼭짓점과 텍스트/아이콘이 겹치지 않게 w/h 기준 비율로
            Padding(
              padding: EdgeInsets.only(
                top:    h * 0.30,
                left:   w * 0.12,
                right:  w * 0.12,
                bottom: h * 0.08,
              ),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}


class _RoundedTrianglePainter extends CustomPainter {
  final Color borderColor;
  final Color fillColor;
  final double borderWidth;
  final double radius;

  _RoundedTrianglePainter({
    required this.borderColor,
    required this.fillColor,
    required this.borderWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 정삼각형 꼭짓점
    final p0 = Offset(size.width / 2, 0);           // 상단 중앙
    final p1 = Offset(size.width, size.height);     // 우하
    final p2 = Offset(0, size.height);              // 좌하
    final pts = [p0, p1, p2];

    final path = _roundedPolygonPath(pts, radius);

    // 내부 면(흰색)
    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fill);

    // 외곽(빨간 테두리) - 라운드 유지
    final stroke = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _RoundedTrianglePainter old) {
    return old.borderColor != borderColor ||
        old.fillColor != fillColor ||
        old.borderWidth != borderWidth ||
        old.radius != radius;
  }

  /// 다각형(여기선 삼각형) 라운드 코너 Path 생성
  Path _roundedPolygonPath(List<Offset> pts, double r) {
    assert(pts.length >= 3);
    final path = Path();

    for (int i = 0; i < pts.length; i++) {
      final prev = pts[(i - 1 + pts.length) % pts.length];
      final cur = pts[i];
      final next = pts[(i + 1) % pts.length];

      final v1 = (prev - cur);
      final v2 = (next - cur);

      final len1 = v1.distance;
      final len2 = v2.distance;

      // 각 코너에서 사용할 반지름(엣지 길이의 절반을 넘지 않도록 제한)
      final rr = math.min(r, math.min(len1, len2) * 0.45);

      // 코너에서 각 엣지 방향으로 rr만큼 떨어진 지점
      final pA = cur + (v1 / len1) * rr;
      final pB = cur + (v2 / len2) * rr;

      if (i == 0) {
        path.moveTo(pA.dx, pA.dy);
      } else {
        path.lineTo(pA.dx, pA.dy);
      }
      // 코너를 부드러운 아크로 연결 (쿼드 베지어)
      path.quadraticBezierTo(cur.dx, cur.dy, pB.dx, pB.dy);
    }

    path.close();
    return path;
  }
}
