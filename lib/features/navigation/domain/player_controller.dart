// 로컬 csv 버전

// /* 재생, 브리지, 방위 계산 */
// import 'dart:async';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
//
// import '../../shared/config.dart';
// import '../../shared/geo.dart';
// import '../../shared/time.dart';
// // AlertNode, RoadSurface, AlertEngine 포함
// import '../../alerts/domain/alert_engine.dart';
// // TraceData 포함
// import '../../navigation/domain/trace_models.dart';
//
//
// class BridgeState {
//   bool active = false;
//   int  elMs = 0;
//   LatLng? a; LatLng? b;
//   double vA = 0, vB = 0;
//   int t0 = 0, t1 = 0;
// }
//
// class PlayerController {
//   // 외부에서 읽는 상태
//   bool started = false;
//   int playMs = 0;
//   int t0 = 0;
//   int seg = 0;
//   double curKmh = 0.0;
//   double camBearingDeg = 0.0;
//
//   // 데이터
//   late TraceData data;
//   final AlertEngine? alertEngine;
//
//   // 내부
//   Timer? _timer;
//   final BridgeState bridge = BridgeState();
//
//   PlayerController({this.alertEngine});
//
//   void attachData(TraceData d) {
//     data = d;
//   }
//
//   void dispose() {
//     _timer?.cancel();
//   }
//
//   // 🔑 [해결]: 'firstMovingSeg' 메서드 정의
//   int firstMovingSeg({double minMeters = 1.0}) {
//     for (int i = 0; i < data.pts.length - 1; i++) {
//       if (haversineM(data.pts[i], data.pts[i + 1]) >= minMeters) return i;
//     }
//     return 0;
//   }
//
//   /// 시작(처음부터)
//   void start({required void Function() onTick}) {
//     if (!data.isValid) return;
//
//     started = true;
//     seg = 0;
//     t0 = data.timeMs.first;
//     playMs = t0;
//     curKmh = data.spdKmh.first;
//
//     final mvIdx = firstMovingSeg(minMeters: 1.0);
//     camBearingDeg = bearingDegBetween(data.pts[mvIdx], data.pts[mvIdx + 1]);
//
//     bridge.active = false;
//     alertEngine?.reset();
//
//     _run(onTick);
//   }
//
//   /// 일시정지
//   void stop() => _timer?.cancel();
//
//   /// 현재 위치에서 계속(초기화 없음)
//   void resume({required void Function() onTick}) {
//     if (!data.isValid) return;
//     started = true;
//     _run(onTick);
//   }
//
//   /// 처음 상태로 되돌림(타이머 정지 포함)
//   void reset() {
//     stop();
//     started = false;
//     seg = 0; playMs = 0; t0 = 0; curKmh = 0; camBearingDeg = 0;
//     bridge.active = false;
//     alertEngine?.reset();
//   }
//
//   /// ±ms 만큼 위치 이동 (예: +10000 = 10초 앞으로)
//   void seekBy(int deltaMs) {
//     if (!data.isValid) return;
//     // 브릿지 진행 중엔 취소
//     bridge.active = false;
//
//     final minT = data.timeMs.first;
//     final maxT = data.timeMs.last;
//     playMs = (playMs + deltaMs).clamp(minT, maxT);
//
//     // seg 재계산: timeMs[seg] <= playMs < timeMs[seg+1]
//     while (seg < data.timeMs.length - 2 && playMs > data.timeMs[seg + 1]) seg++;
//     while (seg > 0 && playMs < data.timeMs[seg]) seg--;
//
//     // 보간 위치/속도 재계산
//     if (seg >= data.timeMs.length - 1) {
//       curKmh = data.spdKmh.last;
//       return;
//     }
//
//     final int t0s = data.timeMs[seg];
//     final int t1s = data.timeMs[seg + 1];
//     final double tau = ((playMs - t0s) / (t1s - t0s)).clamp(0.0, 1.0);
//     final LatLng a = data.pts[seg];
//     final LatLng b = data.pts[seg + 1];
//     final LatLng p = lerpLatLng(a, b, tau);
//
//     curKmh = data.spdKmh[seg] + (data.spdKmh[seg + 1] - data.spdKmh[seg]) * tau;
//
//     // 베어링은 큰 변화가 있을 때만 부드럽게 수렴
//     final double segDist = haversineM(a, b);
//     final double targetBrg = (segDist < 0.5) ? camBearingDeg : bearingDegBetween(a, b);
//     camBearingDeg = smoothBearing(camBearingDeg, targetBrg, alpha: 0.25);
//   }
//
//   /// 경과 시간 포맷
//   String fmtElapsed() {
//     final elapsed = (playMs - t0).clamp(0, 1 << 30);
//     final s = elapsed ~/ 1000;
//     final m = s ~/ 60, ss = s % 60;
//     return '${m.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
//   }
//
//   // =========================
//   // 내부: 주행 루프(타이머) 공통화
//   // =========================
//   void _run(void Function() onTick) {
//     _timer?.cancel();
//     _timer = Timer.periodic(const Duration(milliseconds: AppConfig.tickMs), (_) {
//       // 1) 갭 감지
//       if (!bridge.active && seg < data.timeMs.length - 1) {
//         final int t0s = data.timeMs[seg];
//         final int t1s = data.timeMs[seg + 1];
//         if ((t1s - t0s) >= AppConfig.gapMs) {
//           bridge
//             ..active = true
//             ..elMs = 0
//             ..a = data.pts[seg]
//             ..b = data.pts[seg + 1]
//             ..vA = data.spdKmh[seg]
//             ..vB = data.spdKmh[seg + 1]
//             ..t0 = t0s
//             ..t1 = t1s;
//         }
//       }
//
//       // 2) 브릿지 구간
//       if (bridge.active) {
//         bridge.elMs = (bridge.elMs + AppConfig.tickMs).clamp(0, AppConfig.bridgeMs);
//         final double u = easeSmoothstep(bridge.elMs / AppConfig.bridgeMs);
//
//         final LatLng p = LatLng(
//           bridge.a!.latitude  + (bridge.b!.latitude  - bridge.a!.latitude)  * u,
//           bridge.a!.longitude + (bridge.b!.longitude - bridge.a!.longitude) * u,
//         );
//         curKmh = bridge.vA + (bridge.vB - bridge.vA) * u;
//         playMs = (bridge.t0 + ((bridge.t1 - bridge.t0) * u)).round();
//
//         camBearingDeg = smoothBearing(
//           camBearingDeg,
//           bearingDegBetween(bridge.a!, bridge.b!),
//           alpha: 0.25,
//         );
//
//         onTick();
//         if (bridge.elMs >= AppConfig.bridgeMs) {
//           bridge.active = false;
//           seg++;
//           playMs = bridge.t1;
//         }
//         return;
//       }
//
//       // 3) 일반 구간
//       if (seg < data.timeMs.length - 2 && playMs > data.timeMs[seg + 1]) {
//         seg++;
//         playMs = data.timeMs[seg];
//       }
//       if (seg >= data.timeMs.length - 1) {
//         _timer?.cancel();
//         onTick();
//         return;
//       }
//
//       final int t0s = data.timeMs[seg];
//       final int t1s = data.timeMs[seg + 1];
//       final int dt = (t1s - t0s).clamp(1, 1 << 30);
//       final double tau = ((playMs - t0s) / dt).clamp(0.0, 1.0);
//
//       final LatLng a = data.pts[seg];
//       final LatLng b = data.pts[seg + 1];
//       final LatLng p = lerpLatLng(a, b, tau);
//
//       curKmh = data.spdKmh[seg] + (data.spdKmh[seg + 1] - data.spdKmh[seg]) * tau;
//
//       final double segDist = haversineM(a, b);
//       final double targetBrg = (segDist < 0.5) ? camBearingDeg : bearingDegBetween(a, b);
//       camBearingDeg = smoothBearing(camBearingDeg, targetBrg, alpha: 0.25);
//
//       onTick();
//       playMs += AppConfig.tickMs;
//     });
//   }
// }