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

// 시나리오별 매핑 (실제 경로로 수정)
const Map<DriveScenario, ScenarioFiles> _filesByScenario = {
  DriveScenario.sunny: ScenarioFiles(
    'data/csv/250418video1_data.xlsx',
    'data/videos/2209youtube_video1.mp4',
    'data/models/BEST_convnext_tiny_scenarioC_seed4.pth',
  ),
  DriveScenario.rain: ScenarioFiles(
    'data/csv/240716video5_data.xlsx',
    'data/videos/240716_video5.mp4',
    'data/models/BEST_convnext_tiny_scenarioC_seed4.pth',
  ),
  DriveScenario.snow: ScenarioFiles(
    'data/csv/250212video2_data.xlsx',
    'data/videos/250212_video2.mp4',
    'data/models/BEST_convnext_tiny_scenarioC_seed4.pth',
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
  double? _totalKm; // 전체 경로 길이 (csv 기반)
  double? _remainingKm; // 남은 거리

  double? _hudMaxSpd; // 제한 속도 HUD용

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  Marker? _car;
  BitmapDescriptor? _carIcon;

  bool _booting = true;
  bool _running = false;
  bool _followCar = true;

  // TAS 배너 상태(표시 전담)
  int? _tasSeverity;  // 1=주의, 2=위험, null=비표시
  String? _tasTitle;  // '도로 주의' / '도로 위험'
  String? _tasSub;    // 'NN km/h 이하로 서행'

  // 경고가 처음 발생한 시점 (밀리초 단위)
  int _alertEnterTimeMs = 0;

  // SSE
  late TasSseClient _sse;
  bool _sseRunning = false;

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  // Future<String?> _dummyAddress(LatLng pos) async => null;

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

    // 2. 시나리오 프리로드 (모든 Future를 리스트에 담아 대기)
    final List<Future<void>> preloadTasks = [];

    for (final s in _mgr.scenarios.keys) {
      // Future를 리스트에 추가
      preloadTasks.add(() async {
        try {
          await _mgr.preload(s, (p) => KrAddressService.krRoadAddress(p))
              .timeout(const Duration(seconds: 15));
        } catch (e) {
          debugPrint('preload 실패($s): $e');
        }
        // 모든 작업이 끝난 후 한 번만 호출합니다.
      }());
    }

    // 3. 모든 프리로드 작업이 완료되기를 기다림 (하나라도 끝나면 다음 줄로 넘어감)
    await Future.wait(preloadTasks.map((e) => e.catchError((_) {}))); // 에러가 나도 진행되도록 처리

    if (mounted) {
      await Future.delayed(Duration.zero); // 다음 프레임까지 대기하여 비동기 작업이 시작될 시간을 줌
      setState(() => _booting = false);
      debugPrint('Booting complete. Moving to scenario selection.');
    }
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

  // 전체 경로 길이 (CSV pts 기반)
  double _computeRouteLengthKm(List<LatLng> pts) {
    double total = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      total += _haversineKm(pts[i], pts[i + 1]);
    }
    return total;
  }

  // 현재 위치와 가장 가까운 경로 인덱스
  int _findNearestIndex(List<LatLng> pts, LatLng pos) {
    double bestDist = double.infinity;
    int bestIdx = 0;

    for (int i = 0; i < pts.length; i++) {
      final d = _haversineKm(pts[i], pos);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  // 현재 위치 기준 남은 거리 (경로를 따라 합산)
  double _computeRemainingKm(List<LatLng> pts, LatLng current) {
    if (pts.length < 2) return 0.0;

    final idx = _findNearestIndex(pts, current);
    double remain = 0;

    for (int i = idx; i < pts.length - 1; i++) {
      remain += _haversineKm(pts[i], pts[i + 1]);
    }
    return remain;
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
  int _lastAppCameraMoveMs = 0;

  Future<void> _applyNavCamera(LatLng pos, double bearing) async {

    if (!_mapReadyOk) return;
    if (!_followCar) return;

    _lastBearing = bearing;
    _lastAppCameraMoveMs = DateTime.now().millisecondsSinceEpoch;

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

    // 지도: 시작/끝 마커 + 파란 경로
    final tr = _trace!;
    final first = tr.pts.first;
    final second = tr.pts.length > 1 ? tr.pts[1] : first;

    // 전체 경로 길이 (csv 기반)
    _totalKm = _computeRouteLengthKm(tr.pts);
    // 시작할 때는 남은 거리 = 전체 거리
    _remainingKm = _totalKm;

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

    // 1. Completer 및 상태 설정
    _mapReady = Completer<void>();
    _running = true;
    setState(() {});

    // 2. 맵 준비 대기
    await _mapReady!.future;

    // 3. 변수 설정
    final heading0 = _bearingDeg(first, second);
    _currentPos = first;
    _currentKmh = 0.0;
    _startTime = DateTime.now();
    _elapsedTime = '00:00';

    _followCar = true;
    _lastBearing = heading0;

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

          _hudMaxSpd = maxSpd; // HUD에 쓸 제한 속도 갱신

          // 경과 시간
          final elapsedDuration = DateTime.now().difference(_startTime!);
          final currentRunTimeMs = elapsedDuration.inMilliseconds;

          // 차량 이동
          final next = LatLng(lat, lon);
          final bearing = _pickBearing(_currentPos ?? next, next, _lastBearing);
          _currentPos = next;
          _currentKmh = spd;
          await _updateCarAndCamera(next, bearing);

          //  현재 위치 기준 남은 거리 (start-end 직선 대신 현재 위치-end 직선)
          if (_trace != null && _currentPos != null) {
            _remainingKm = _computeRemainingKm(_trace!.pts, _currentPos!);
          }

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
          _tasTitle = showTas
              ?(dc == 2 ? '⚠ Icy Road ⚠\nHigh-risk section' : '⚠ Wet Road ⚠\nCaution section') : null;
          final recSafe = rec.clamp(0.0, maxSpd);
          _tasSub = showTas ? 'Slow down to ${recSafe.round()} km/h or less' : null;

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
              const SnackBar(content: Text('Simulation finished (SSE closed)')),
            );
            setState(() {});
          }
        },
        onError: (e) async {
          _sseRunning = false;
          await _sse.stop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('SSE error: $e'), backgroundColor: Colors.red),
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
          SnackBar(content: Text('Failed to start SSE: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _stopSse() async {
    _sseRunning = false;
    try { await _sse.stop(); } catch (_) {}
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
    _totalKm = null;
    _remainingKm = null;

    _tasSeverity = null;
    _tasTitle = null;
    _tasSub = null;

    _followCar = true;

    setState(() {});
  }

  void _onReturnPressed() {
    if (_currentPos == null) return;
    if (!_mapReadyOk) return;

    setState(() {
      _followCar = true;
    });

    // 마지막 베어링 방향으로 현재 차량 위치로 카메라 복귀
    _applyNavCamera(_currentPos!, _lastBearing);
  }

  @override
  void dispose() {
    _stopSse();
    // _map.dispose();
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
      final order = [
        DriveScenario.sunny,
        DriveScenario.rain,
        DriveScenario.snow
      ];
      return Scaffold(
        appBar: AppBar(
            titleSpacing: 0,
            title: const Text('TAS Navigator')
        ),
        drawer: _buildDrawer(context),
        body: Padding(
          padding: const EdgeInsets.all(14),
          child: ListView.separated(
            itemCount: order.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, idx) {
              final s = order[idx];
              final slot = _mgr.scenarios[s];
              debugPrint('Scenario check: $s, slot is null: ${slot == null}');

              if (slot == null) {
                return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Fatal Error: Scenario data missing.',
                          style: TextStyle(color: Colors.white)
                      ),
                    ),
                );
              }

              // 리스트 카드
              return _scenarioListCard(
                title: slot.startAddrKr ?? 'Route',
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
                        const SnackBar(content: Text('Scenario file paths are not configured.')),
                      );
                    }
                    return;
                  }
                  await _start();
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Guidance'),
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
        actions: [IconButton(onPressed: _resetAll, icon: const Icon(Icons.output))],
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

            // 지도 드래그하면 follow 해제
            onCameraMoveStarted: () {
              final nowMs = DateTime.now().millisecondsSinceEpoch;
              final diff = nowMs - _lastAppCameraMoveMs;

              // animateCamera 직후(예: 400ms 이내)에 발생한 moveStarted는
              // 앱이 움직인 걸로 보고 무시
              if (diff >= 0 && diff < 400) {
                return;
              }

              // 그 이후에 발생한 moveStarted는 사용자가 드래그했다고 보고 follow 해제
              if (_running && _followCar && _currentPos != null) {
                setState(() {
                  _followCar = false;
                });
              }
            },

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

          // 좌하단 좌표/경과 시간 HUD
          Positioned(
            left: 25,
            bottom: 70,
            child: hud.SpeedLimitHud(
              maxSpd: _hudMaxSpd?.toInt(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: MediaQuery.removePadding(
        context: context,
        removeBottom: true,   // ← 하단 SafeArea 제거
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                // [1] 마커 포커싱
                Expanded(
                  flex: 1,
                  child: InkWell(
                    onTap: _onReturnPressed,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        border: Border.all(color: Colors.black),
                      ),
                      child: const Center(
                        child: Icon(
                          color: Colors.white,
                          Icons.my_location,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),

                // [2] 주행 시간
                Expanded(
                  flex: 2,
                  child: _BottomInfoBox(
                    title: 'Elapsed time',
                    value: _elapsedTime,
                  ),
                ),

                // [3] 남은 거리
                Expanded(
                  flex: 2,
                  child: _BottomInfoBox(
                    title: 'Remaining distance',
                    value: _remainingKm != null
                        ? '${_remainingKm!.toStringAsFixed(1)} km'
                        : '-- km',
                  ),
                ),
              ],
            ),
          ),
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
      elevation: 1,
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
                const Text(
                  '❌ Failed to load route (file or format error)',
                  style: TextStyle(color: Colors.red),
                )
              else
                card.StartEndCard(
                  startAddr: startAddr ?? 'Address lookup failed',
                  start: card.LatLngLite(trace!.start.latitude, trace.start.longitude),
                  endAddr: endAddr ?? 'Address lookup failed',
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
        title: 'Preview route',
        trace: tr,
        startAddr: slot.startAddrKr ?? 'Resolving address…',
        endAddr:   slot.endAddrKr ?? 'Resolving address…',
        onStart: () async {
          Navigator.of(context).pop();
          _trace = tr;
          setState(() => _selected = s);
          await _start();
        },
      ),
    );
  }

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
}

class _BottomInfoBox extends StatelessWidget {
  final String title;
  final String value;
  final VoidCallback? onTap;
  final bool emphasize;

  const _BottomInfoBox({
    super.key,
    required this.title,
    required this.value,
    this.onTap,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (title.isNotEmpty) ...[
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            color: Colors.white,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );

    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: content,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.black87,
        border: Border.all(color: Colors.black),
      ),
      child: onTap == null
          ? inner
          : InkWell(
        onTap: onTap,
        child: inner,
      ),
    );
  }
}
