/* 배너 UI - 겹치는 라운드 직사각형 경고 배너 */
import 'dart:async'; // ← 추가
import 'package:flutter/material.dart';
import '../../shared/config.dart';
import '../domain/alert_engine.dart';

class AlertBanner extends StatefulWidget {
  final bool visible;
  final AlertNode? alert; // (현재는 사용 안 함)
  final double curKmh;
  final int playMs;
  final int firstEnterPlayMs;

  final String? tasTitle;   // "도로 젖음\n주의 구간입니다" 등
  final String? tasSub;     // "40km/h 이하로 서행하세요" 등
  final int? severity;      // 1=주의(오렌지), 2=위험(레드)

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

  @override
  State<AlertBanner> createState() => _AlertBannerState();
}

class _AlertBannerState extends State<AlertBanner> {
  bool _flashOn = true;
  Timer? _timer;

  // decel_class 1 or 2일 때만
  bool get _isActive => widget.severity == 1 || widget.severity == 2;

  @override
  void initState() {
    super.initState();
    // alertFlashMs 주기로 깜빡임 토글
    _timer = Timer.periodic(
      const Duration(milliseconds: AppConfig.alertFlashMs),
          (_) {
        if (!mounted) return;
        // 경고가 실제로 표시되는 상태에서만 깜빡임
        if (!widget.visible || !_isActive || widget.tasTitle == null) return;
        setState(() {
          _flashOn = !_flashOn;
        });
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // severity가 1/2가 아니면 표시 안 함
    if (!widget.visible || !_isActive || widget.tasTitle == null) {
      return const SizedBox.shrink();
    }

    // Timer로 토글되는 플래그 사용
    final bool flashing = _flashOn;
    final bool danger = widget.severity == 2;

    // 기본 색 (완전 불투명)
    final Color baseOuterColor =
    danger ? Colors.deepOrangeAccent : const Color(0xFFfe9333);
    final Color baseInnerColor =
    danger ? Colors.deepOrangeAccent : const Color(0xFFfe9333);
    const Color baseBorderColor = Colors.white;

    const Color baseTextColor = Colors.black;
    const Color baseTextDangerColor = Color(0xFFff0000);

    // '전체 알파'만 컨트롤
    final double alpha = flashing ? 0.8 : 0.4;

    final Color outerColor = baseOuterColor.withOpacity(alpha);
    final Color innerColor = baseInnerColor.withOpacity(alpha);
    final Color borderColor = baseBorderColor.withOpacity(alpha);

    final Color textColor = baseTextColor.withOpacity(alpha);
    final Color textDangerColor = baseTextDangerColor.withOpacity(alpha);

    return AnimatedSlide(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      offset: widget.visible ? Offset.zero : const Offset(0, -1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 100),
        opacity: widget.visible ? 1 : 0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 150, 12, 0),
          child: Container(
            // 제일 바깥 라운드 직사각형
            width: 300,
            height: 138,
            decoration: BoxDecoration(
              color: outerColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              // 안쪽 라운드 직사각형 (하얀 테두리)
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: innerColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor, width: 6),
              ),
              child: Padding(
                // 안쪽 여백 (텍스트/아이콘 공간)
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 첫 줄: "⚠ 도로 젖음 ⚠"
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 4),
                        Text(
                          widget.tasTitle!.split('\n').first,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),

                    const SizedBox(height: 0),

                    // 두 번째 줄: "주의 구간입니다"
                    if (widget.tasTitle!.contains('\n')) ...[
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: widget.tasTitle!
                                  .split('\n')
                                  .last
                                  .replaceAll('입니다', ''),
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                color: textDangerColor,
                              ),
                            ),
                            TextSpan(
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: textColor,
                              ),
                              text: '입니다',
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 세 번째 줄: "40km/h 이하로 서행하세요"
                    if (widget.tasSub != null) ...[
                      const SizedBox(height: 0),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: _extractNumber(widget.tasSub!),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: textColor,
                                height: 1.0,
                              ),
                            ),
                            TextSpan(
                              text: _extractRest(widget.tasSub!),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: textColor,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _extractNumber(String text) {
  final reg = RegExp(r'\d+'); // 숫자만 추출
  final match = reg.firstMatch(text);
  return match?.group(0) ?? '';
}

String _extractRest(String text) {
  final reg = RegExp(r'\d+');
  return text.replaceFirst(reg, '');
}
