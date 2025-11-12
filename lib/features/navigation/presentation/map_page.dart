/* features/navigation/presentation/map_page.dart */

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../shared/geo_addr.dart';  // ← KrAddressService 사용


import '../../api/tas_sse_client.dart';
import '../../misc/about_page.dart';
import '../../shared/config.dart';
import '../../alerts/presentation/alert_banner.dart';
import '../../navigation/domain/trace_models.dart';
import '../../navigation/domain/scenario_manager.dart';
import '../../navigation/presentation/widgets/preview_sheet.dart';
import '../../navigation/presentation/widgets/start_end_card.dart' as card;
import '../../navigation/presentation/hud_basic.dart' as hud;

/// ─────────────────────────────────────────────────────────────
/// MapPage
/// ─────────────────────────────────────────────────────────────
class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

// 시나리오별 파일 경로 묶음
class ScenarioFiles {
  final String xlsxPath;
  final String videoPath;
  final String modelPath;
  const ScenarioFiles(this.xlsxPath, this.videoPath, this.modelPath);
}

// 시나리오별 매핑 (실제 경로로 수정하세요)
const Map<DriveScenario, ScenarioFiles> _filesByScenario = {
  DriveScenario.rain: ScenarioFiles(
    r'C:\Users\seonga\Desktop\TAS_251101\api\data\csv\240716video5_data.xlsx',
    r'C:\Users\seonga\Desktop\TAS_251101\api\data\videos\240716_video5.mp4',
    r'C:\Users\seonga\Desktop\TAS_251101\api\data\models\cnn_mobilenet_v3_small_ensemble_calibrated.pth',
  ),
  DriveScenario.snow: ScenarioFiles(
    r'C:\Users\seonga\Desktop\TAS_251101\api\data\csv\250212video2_data.xlsx',
    r'C:\Users\seonga\Desktop\TAS_251101\api\data\videos\250212_video2.mp4',
    r'C:\Users\seonga\Desktop\TAS_251101\api\data\models\cnn_mobilenet_v3_small_ensemble_calibrated.pth',
  ),
};

class _MapPageState extends State<MapPage> {
  // 서버 호스트(IP[:PORT])
  static const String _serverHost = '192.168.0.22:8000'; // 포트 8000 기본

  final ScenarioManager _mgr = ScenarioManager();

  late GoogleMapController _map;
  Completer<void>? _mapReady;

  DriveScenario? _selected;
  TraceData? _trace;

  LatLng? _currentPos;
  double _currentKmh = 0.0;
  String _elapsedTime = '00:00';
  DateTime? _startTime;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  Marker? _car;
  BitmapDescriptor? _carIcon;

  bool _booting = true;
  bool _running = false;

  // TAS 배너 상태(표시 전담)
  int? _tasSeverity;  // 1=주의, 2=위험, null=비표시
  String? _tasTitle;  // '도로 주의' / '도로 위험'
  String? _tasSub;    // 'NN km/h 이하로 서행'

  // 경고가 처음 발생한 시점 (밀리초 단위)
  int _alertEnterTimeMs = 0;

  // HUD(간단 수치) — SSE tick에서 갱신
  double? _hudMaxSpd;
  double? _hudRec;
  int? _hudDecelClass;

  // SSE
  late TasSseClient _sse;
  bool _sseRunning = false;

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<String?> _dummyAddress(LatLng pos) async => null;

  Future<void> _initAll() async {
    // 차량 아이콘
    try {
      _carIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(),
        'assets/icons/car.png',
      );
    } catch (_) {
      _carIcon = null;
    }

    // 시나리오 프리로드(비동기, 실패해도 앱 진행)
    for (final s in _mgr.scenarios.keys) {
      () async {
        try {
          // 진짜 주소 함수 넘기기
          await _mgr.preload(s, (p) => KrAddressService.krRoadAddress(p))
              .timeout(const Duration(seconds: 15));
        } catch (e) {
          debugPrint('preload 실패($s): $e');
        } finally {
          if (mounted) setState(() {});
        }
      }();
    }

    if (mounted) setState(() => _booting = false);
  }

  // ─────────────────────────────────────────────────────────
  // 지오/카메라 유틸
  // ─────────────────────────────────────────────────────────
  bool _isNearlyStopped(LatLng a, LatLng b) {
    final km = _haversineKm(a, b);
    return km < 0.0003; // ≈ 0.3m
  }

  double _pickBearing(LatLng prev, LatLng next, double fallback) {
    if (_isNearlyStopped(prev, next)) return fallback;
    return _bearingDeg(prev, next);
  }

  double _haversineKm(LatLng a, LatLng b) {
    const R = 6371.0; // km
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
    final la1 = a.latitude * math.pi / 180.0;
    final la2 = b.latitude * math.pi / 180.0;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.asin(math.sqrt(h));
    return R * c;
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  bool get _mapReadyOk => _mapReady?.isCompleted ?? false;

  double _bearingDeg(LatLng a, LatLng b) {
    final phi1 = a.latitude  * math.pi / 180.0;
    final phi2 = b.latitude  * math.pi / 180.0;
    final dLambda = (b.longitude - a.longitude) * math.pi / 180.0;

    final y = math.sin(dLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2)
        - math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);

    final theta = math.atan2(y, x) * 180.0 / math.pi;
    return (theta + 360.0) % 360.0; // 0~360
  }

  double _lastBearing = 0.0;

  Future<void> _applyNavCamera(LatLng pos, double bearing) async {
    if (!_mapReadyOk) return;
    _lastBearing = bearing;

    await _map.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: pos,
          zoom: AppConfig.camZoom,
          tilt: AppConfig.camTilt,
          bearing: bearing,
        ),
      ),
    );
  }

  Future<void> _updateCarAndCamera(LatLng pos, double rotationDeg) async {
    _car = _car?.copyWith(positionParam: pos, rotationParam: rotationDeg) ??
        Marker(
          markerId: const MarkerId('car'),
          position: pos,
          icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          rotation: rotationDeg,
          flat: true,
        );
    await _applyNavCamera(pos, rotationDeg);
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────
  // SSE 시작/정지
  // ─────────────────────────────────────────────────────────
  Future<void> _start() async {
    if (_trace == null) return;

    // 초기 상태 클린
    _tasSeverity = null;
    _tasTitle = null;
    _tasSub = null;
    _hudMaxSpd = null;
    _hudRec = null;
    _hudDecelClass = null;

    // 지도: 시작/끝 마커 + 파란 경로
    final tr = _trace!;
    final first = tr.pts.first;
    final second = tr.pts.length > 1 ? tr.pts[1] : first;

    _markers
      ..clear()
      ..addAll({
        Marker(
          markerId: const MarkerId('start'),
          position: tr.start,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
        Marker(
          markerId: const MarkerId('end'),
          position: tr.end,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      });

    _polylines
      ..clear()
      ..add(Polyline(
        polylineId: const PolylineId('route'),
        points: tr.pts,
        color: Colors.blueAccent,
        width: 6,
      ));

    final heading0 = _bearingDeg(first, second);
    _currentPos = first;
    _currentKmh = 0.0;
    _startTime = DateTime.now();
    _elapsedTime = '00:00';

    _running = true;
    _mapReady = Completer<void>();
    setState(() {});

    await _mapReady!.future;
    await _updateCarAndCamera(first, heading0);

    // SSE 시작
    _sse = TasSseClient(_serverHost);
    _sseRunning = true;

    try {
      // 선택된 시나리오의 파일 묶음 가져오기
      final files = _filesByScenario[_selected];
      if (files == null) {
        _sseRunning = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('시나리오 파일 경로가 설정되지 않았습니다.')),
          );
        }
        return;
      }

      await _sse.start(
        xlsxPath: files.xlsxPath,
        videoPath: files.videoPath,
        modelPath: files.modelPath,
        fps: 1.0,
        imgSize: 224,
        intervalSec: 1.0,
        onStart: (meta) {
          if (mounted) setState(() {});
        },
        onTick: (p) async {
          if (!_sseRunning) return;

          final lat = (p['latitude'] as num).toDouble();
          final lon = (p['longitude'] as num).toDouble();
          final spd = (p['spd'] as num).toDouble();
          final rec = (p['rec'] as num).toDouble();
          final maxSpd = (p['max_spd'] as num).toDouble();
          final dc = p['decel_class'] as int;
          final warn = p['warn'] == 1;

          // 경과 시간
          final elapsedDuration = DateTime.now().difference(_startTime!);
          final currentRunTimeMs = elapsedDuration.inMilliseconds;

          // 차량 이동
          final next = LatLng(lat, lon);
          final bearing = _pickBearing(_currentPos ?? next, next, _lastBearing);
          _currentPos = next;
          _currentKmh = spd;
          await _updateCarAndCamera(next, bearing);

          // TAS 배너 (서버 warn + dc=1/2일 때만)
          final showTas = warn && (dc == 1 || dc == 2);

          // 경고 발생 시점 기록 로직
          if (showTas && _alertEnterTimeMs == 0) {
            // 경고가 ON이 되었고, 아직 시작 시간이 기록되지 않았다면 기록
            _alertEnterTimeMs = currentRunTimeMs;
          } else if (!showTas) {
            // 경고가 OFF가 되면 시작 시간을 초기화
            _alertEnterTimeMs = 0;
          }

          _tasSeverity = showTas ? dc : null;
          _tasTitle = showTas ? (dc == 2 ? '위  험' : '주  의') : null;
          final recSafe = rec.clamp(0.0, maxSpd);
          _tasSub = showTas ? '${recSafe.round()} km/h 이하로 서행' : null;

          // HUD 숫자
          _hudMaxSpd = maxSpd;
          _hudRec = rec;
          _hudDecelClass = dc;

          // 경과 시간
          if (_startTime != null) {
            final d = DateTime.now().difference(_startTime!);
            _elapsedTime = _formatDuration(d);
          }

          if (mounted) setState(() {});
        },
        onEnd: (end) async {
          _sseRunning = false;
          await _sse.stop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('모의 주행 완료(SSE 종료)')),
            );
            setState(() {});
          }
        },
        onError: (e) async {
          _sseRunning = false;
          await _sse.stop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('SSE 오류: $e'), backgroundColor: Colors.red),
            );
            setState(() {});
          }
        },
      );
    } catch (e) {
      _sseRunning = false;
      await _sse.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SSE 시작 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _stopSse() async {
    _sseRunning = false;
    try { await _sse.stop(); } catch (_) {}
  }

  void _pause() {
    _stopSse();
    _startTime = null; // 시간 측정 중단
    setState(() {});
  }

  Future<void> _restart() async {
    await _stopSse();
    _currentPos = null;
    _currentKmh = 0.0;
    _elapsedTime = '00:00';
    _startTime = null;

    _tasSeverity = null;
    _tasTitle = null;
    _tasSub = null;
    _hudMaxSpd = null;
    _hudRec = null;
    _hudDecelClass = null;

    await _start();
  }

  Future<void> _resetAll() async {
    await _stopSse();

    _markers.clear();
    _polylines.clear();
    _car = null;
    _running = false;
    _selected = null;
    _trace = null;
    _currentPos = null;
    _currentKmh = 0.0;
    _elapsedTime = '00:00';
    _startTime = null;

    _tasSeverity = null;
    _tasTitle = null;
    _tasSub = null;
    _hudMaxSpd = null;
    _hudRec = null;
    _hudDecelClass = null;

    setState(() {});
  }

  @override
  void dispose() {
    _stopSse();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 현재 경과 시간 계산
    final elapsedDuration = _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero;
    final currentRunTimeMs = elapsedDuration.inMilliseconds;

    // 1) 시나리오 선택
    if (_selected == null) {
      final order = [DriveScenario.rain, DriveScenario.snow];
      return Scaffold(
        appBar: AppBar(title: const Text('TAS')),
        drawer: _buildDrawer(context),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView.separated(
            itemCount: order.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, idx) {
              final s = order[idx];
              final slot = _mgr.scenarios[s]!;

              // 리스트 카드
              return _scenarioListCard(
                title: slot.startAddrKr ?? '주행 경로',
                startAddr: slot.startAddrKr,
                endAddr: slot.endAddrKr,
                trace: slot.trace,
                loading: slot.loading,
                onTap: () => _openScenarioSheet(s),
              );
            },
          ),
        ),
      );
    }

    // 2) 주행 전 상세
    final slot = _mgr.scenarios[_selected]!;
    final tr = slot.trace!;
    if (!_running) {
      return Scaffold(
        // appBar: AppBar(title: Text('TAS · ${_scenarioTitle(_selected)}')),
        appBar: AppBar(title: const Text('TAS Navigator')),
        drawer: _buildDrawer(context),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              card.StartEndCard(
                startAddr: slot.startAddrKr ?? '주소 조회 실패',
                start: card.LatLngLite(tr.start.latitude, tr.start.longitude),
                endAddr: slot.endAddrKr ?? '주소 조회 실패',
                end: card.LatLngLite(tr.end.latitude, tr.end.longitude),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () async {
                  _trace = tr;
                  if (_trace == null || _trace!.pts.isEmpty) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('경로 데이터가 비어 있습니다. 시나리오 파일을 확인하세요.')),
                      );
                    }
                    return;
                  }
                  await _start();
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('안내 시작'),
              ),
            ],
          ),
        ),
      );
    }

    // 3) 지도 + 재생
    return Scaffold(
      appBar: AppBar(
        title: const Text('TAS Navigator'),
        actions: [IconButton(onPressed: _resetAll, icon: const Icon(Icons.refresh))],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _currentPos ?? tr.pts.first, zoom: 16),
            onMapCreated: (c) {
              _map = c;
              _mapReady?.complete();
            },
            markers: {if (_car != null) _car!, ..._markers},
            polylines: _polylines,
            zoomControlsEnabled: false,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            compassEnabled: false,
          ),

          // 상단 TAS 경고 배너
          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: AlertBanner(
                visible: _tasSeverity == 1 || _tasSeverity == 2,
                alert: null,
                curKmh: _currentKmh,
                playMs: currentRunTimeMs,
                firstEnterPlayMs: _alertEnterTimeMs,
                tasTitle: _tasTitle,
                tasSub: _tasSub,
                severity: _tasSeverity,
              ),
            ),
          ),

          // 좌상단 속도 HUD
          Positioned(
            top: 30,
            left: 40,
            child: hud.SpeedHud(kmh: _currentKmh),
          ),

          // // 좌상단 아래 제한/추천/상태 HUD (SSE 수치 기반)
          // if (_hudMaxSpd != null && _hudRec != null && _hudDecelClass != null)
          //   Positioned(
          //     top: 100,
          //     left: 30,
          //     child: _buildTasStatusHudNumbers(
          //       maxSpd: _hudMaxSpd!,
          //       rec: _hudRec!,
          //       decelClass: _hudDecelClass!,
          //     ),
          //   ),

          // 좌하단 좌표/경과 시간 HUD
          Positioned(
            left: 12,
            bottom: 20,
            child: hud.CoordTimeHud(
              pos: _car != null
                  ? card.LatLngLite(_car!.position.latitude, _car!.position.longitude)
                  : null,
              elapsed: _elapsedTime,
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Row(
          children: [
            Expanded(child: ElevatedButton(onPressed: _pause, child: const Text('일시정지'))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(onPressed: _restart, child: const Text('재시작'))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(onPressed: _resetAll, child: const Text('주행 종료'))),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // 보조 UI
  // ─────────────────────────────────────────────────────────
  Widget _scenarioListCard({
    required String title,
    required String? startAddr,
    required String? endAddr,
    required TraceData? trace,
    required bool loading,
    required VoidCallback onTap,
  }) {
    final isTraceReady = trace != null && trace.pts.isNotEmpty;
    final hasError = !loading && !isTraceReady;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      child: InkWell(
        onTap: loading || hasError ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (loading)
                const LinearProgressIndicator(minHeight: 6)
              else if (hasError)
                const Text('❌ 경로 로드 실패 (파일 또는 형식 오류)', style: TextStyle(color: Colors.red))
              else
                card.StartEndCard(
                  startAddr: startAddr ?? '주소 조회 실패',
                  start: card.LatLngLite(trace!.start.latitude, trace.start.longitude),
                  endAddr: endAddr ?? '주소 조회 실패',
                  end: card.LatLngLite(trace.end.latitude, trace.end.longitude),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openScenarioSheet(DriveScenario s) async {
    final slot = _mgr.scenarios[s]!;
    final tr = slot.trace!;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PreviewSheet(
        title: '주행 경로 미리보기',
        trace: tr,
        startAddr: slot.startAddrKr ?? '주소 조회 중…',
        endAddr:   slot.endAddrKr ?? '주소 조회 중…',
        onStart: () async {
          Navigator.of(context).pop();
          _trace = tr;
          setState(() => _selected = s);
          await _start();
        },
      ),
    );
  }

  // String _scenarioTitle(DriveScenario? s) {
  //   switch (s) {
  //     case DriveScenario.rain:
  //       return '비 오는 날';
  //     case DriveScenario.snow:
  //       return '눈 오는 날';
  //     default:
  //       return '주행 구간';
  //   }
  // }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blueGrey),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'TAS',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage()));
              },
            ),
          ],
        ),
      ),
    );
  }

  // // 개발시 제한, 추천 속도 확인용
  // // 숫자만으로 그리는 간단 TAS 상태 HUD
  // Widget _buildTasStatusHudNumbers({
  //   required double maxSpd,
  //   required double rec,
  //   required int decelClass,
  // }) {
  //   final Color bg = switch (decelClass) {
  //     2 => Colors.red.shade700,
  //     1 => Colors.orange.shade700,
  //     _ => Colors.green.shade700,
  //   };
  //
  //   return Container(
  //     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  //     decoration: BoxDecoration(
  //       color: bg,
  //       borderRadius: BorderRadius.circular(4),
  //       boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         Text('제한 속도: ${maxSpd.toStringAsFixed(0)} km/h',
  //             style: const TextStyle(color: Colors.white, fontSize: 14)),
  //         Text('추천 속도: ${rec.toStringAsFixed(0)} km/h',
  //             style: const TextStyle(color: Colors.white, fontSize: 14)),
  //         Text(
  //           decelClass == 2 ? '🚨 위험' : (decelClass == 1 ? '⚠️ 주의' : '✅ 정상 주행'),
  //           style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
  //         ),
  //       ],
  //     ),
  //   );
  // }
}
