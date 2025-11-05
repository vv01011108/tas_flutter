/* features/navigation/presentation/map_page.dart */

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../api/tas_status.dart';
import '../../misc/about_page.dart';
import '../../shared/config.dart';
import '../../alerts/presentation/alert_banner.dart';
import '../../navigation/domain/trace_models.dart';
import '../../navigation/domain/scenario_manager.dart';
import '../../navigation/presentation/widgets/preview_sheet.dart';
import '../../navigation/presentation/widgets/start_end_card.dart' as card;
import '../../navigation/presentation/hud_basic.dart' as hud;
import '../../api/tas_api.dart';
import 'dart:math' as math;

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {

  // 서버 호스트(IP[:PORT])
  static const String _serverHost = '192.168.0.22:8000'; // 포트가 8000이면 그대로

  final ScenarioManager _mgr = ScenarioManager();

  late final TasApi _tasApi;
  Timer? _timer;
  TasStatus? _tas;
  String _sessionId = 'dev-local';

  // 💡 [1] 서버 IP 및 모델 경로 (네트워크 환경에 따라 변경되어야 함)
  static const String _serverVideoPath = 'C:\\Users\\seonga\\Desktop\\TAS_251101\\api\\data\\videos\\240716_video5.mp4';
  static const String _serverModelPath = 'C:\\Users\\seonga\\Desktop\\TAS_251101\\api\\data\\models\\cnn_best.pth';

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

  @override
  void initState() {
    super.initState();
    _tasApi = TasApi(baseHost: _serverHost);
    _initAll();
  }

  Future<String?> _dummyAddress(LatLng pos) async {
    return null; // 주소 검색 시도 없이 즉시 null 반환
  }

  // 필수 함수: 초기 설정
  Future<void> _initAll() async {
    // 아이콘은 실패해도 앱 로딩이 막히지 않게 try/catch
    try {
      _carIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(),
        'assets/icons/car.png',
      );
    } catch (_) {
      // 아이콘 로드 실패시 기본 마커로 진행
      _carIcon = null;
    }

    // 2) 프리로드는 "대기하지 말고" 흘려보내기 + 타임아웃/에러 캐치
    for (final s in _mgr.scenarios.keys) {
      // 한 시나리오가 끝날 때마다 UI 갱신 (개별 실패해도 앱은 진행)
      () async {
        try {
          await _mgr.preload(s, _dummyAddress).timeout(const Duration(seconds: 15));
        } catch (e, st) {
          debugPrint('preload 실패($s): $e');
        } finally {
          if (mounted) setState(() {}); // 카드 갱신
        }
      }();
    }

    // 3) 전역 안전망: 어떤 이유로든 위 프리로드들이 지연되더라도 UI는 즉시 뜨게
    //    (지도/리스트 먼저 표시, 각 카드가 로딩/에러/성공 상태로 알아서 바뀜)
    if (mounted) setState(() => _booting = false);
  }

  // API 호출 함수 수정: 서버로 현재 위치/속도를 보내고, 서버에서 받은 위치로 갱신
  Future<void> _fetchTas(LatLng pos, double curKmh) async {
    try {
      final raw = await _tasApi.fetchCurrentStatusRaw(
        sessionId: _sessionId,
        spd: curKmh,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );

      // 1) 영상이 끝난 경우 처리
      if (raw['finished'] == true) {
        debugPrint('영상 종료: ${raw['message']}');
        _stopTasPolling();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('세션 종료: ${raw['message'] ?? "모의 주행 완료"}')),
          );
        }
        return;
      }

      // 2) 정상 응답일 때만 TasStatus 변환
      final s = TasStatus.fromJson(raw);
      _tas = s;

      final int? dc = s.decelClass;      // 0=정상, 1=주의, 2=위험
      final bool warn = s.warn == 1;    // API에서 넘어온 그대로 사용

      // 배너 노출 조건: “경고(warn)” 이고 “cls가 1/2”
      final bool showTas = warn && (dc == 1 || dc == 2);

      // severity, 타이틀/부제 생성 (표시는 AlertBanner에서만)
      _tasSeverity = showTas ? dc : null;
      _tasTitle    = showTas ? (dc == 2 ? '도로 위험' : '도로 주의') : null;

      // rec 안전 클램프 (num→double 캐스팅)
      final double recSafe = ((s.rec.isFinite ? s.rec : 0.0)
          .clamp(0.0, s.maxSpd)).toDouble();
      _tasSub = showTas ? '${recSafe.round()} km/h 이하로 서행' : null;

      // 경과 시간 HUD
      if (_startTime != null) {
        final duration = DateTime.now().difference(_startTime!);
        _elapsedTime = _formatDuration(duration);
      }

      // 디버그 로그
      debugPrint('[TAS] cls=$dc warn=$warn | '
          'spd=${s.spd.toStringAsFixed(1)} '
          'rec=${s.rec.toStringAsFixed(1)} '
          'max=${s.maxSpd.toStringAsFixed(0)} '
          'title=$_tasTitle sub=$_tasSub');

      if (mounted) setState(() {});

    } catch (e) {
      debugPrint('⚠️ TAS fetch 오류: $e');
    }
  }

  int _traceIdx = 0;

  // 아주 작은 이동(정지)인지 판단: 0.0x km ≈ 몇 m
  bool _isNearlyStopped(LatLng a, LatLng b) {
    final km = _haversineKm(a, b);
    return km < 0.0003; // ≈ 0.3m (원하면 1~3m로 올려도 됨: 0.001~0.003)
  }

  // 정지면 마지막 각도 유지, 이동이면 새 bearing
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

  // 경과 시간 포맷 함수
  String _formatDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  // 폴링 루프: 1초 간격
  void _startTasPolling() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_running || _trace == null) {
        _timer?.cancel();
        return;
      }

      final tr = _trace!;

      if (_traceIdx >= tr.pts.length - 1) {
        // 경로 끝
        _stopTasPolling();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('모의 주행 완료')),
          );
        }
        return;
      }

      // === prev/next ===
      final int nextIdx = _traceIdx + 1;
      final LatLng prev = _currentPos ?? tr.pts[_traceIdx];
      final LatLng next = tr.pts[nextIdx];

      // === 속도(km/h) ===
      final double km = _haversineKm(prev, next);
      final double kmh = (km * 3600.0).clamp(0.0, 130.0);
      final double bearingDeg = _pickBearing(prev, next, _lastBearing);

      // === 상태 반영 ===
      _currentPos = next;
      _currentKmh = kmh;
      _traceIdx = nextIdx;

      // === 지도/마커 업데이트 (항상 1회) ===
     await _updateCarAndCamera(next, bearingDeg);

      // === 서버 호출: 세션일 때만 ===
      if (_sessionId != 'dev-local') {
        await _fetchTas(next, _currentKmh);
      }

      // 필요시 로컬 상태 갱신 표시
      if (mounted) setState(() {});
    });
  }

  void _stopTasPolling() {
    _timer?.cancel();
    _timer = null;
    _tas = null;
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
    return (theta + 360.0) % 360.0; // 0~360 정규화
  }

  // ① 유틸: 두 점 사이 bearing(deg)
  double _lastBearing = 0.0;
  LatLng? _lastPos;

  // ② 카메라 적용을 animate로
  Future<void> _applyNavCamera(LatLng pos, double bearing) async {
    if (!_mapReadyOk) return;

    _lastPos = pos;
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

  // ③ 차량/카메라 업데이트 시 rotation 전달
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

  // _start 함수 수정: [5] 비디오 파일 전송 로직을 제거하고, 경로만 서버에 전달
  Future<void> _start() async {
    if (_trace == null) return;

    try {
      // 업로드 X, 경로로 세션 시작
      final newSessionId = await _tasApi.startByPath(
        serverVideoPath: _serverVideoPath,
        serverModelPath: _serverModelPath,
        imgSize: 224,
        intervalSec: 1.0,
      );
      _sessionId = newSessionId;
      print('✅ 세션 시작: $_sessionId');

      _tas = null;
      _tasSeverity = null;
      _tasTitle = null;
      _tasSub = null;

      _currentPos = _trace!.pts.first;
      _currentKmh = 0.0;
      _traceIdx = 0;
      _startTime = DateTime.now();
      _elapsedTime = '00:00';

    } catch (e) {
      print('❌ 세션 시작 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('세션 시작 실패: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final tr = _trace!;
    _running = true;
    _mapReady = Completer<void>();
    setState(() {});

    await _mapReady!.future;

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

    final first = _trace!.pts.first;
    final second = _trace!.pts.length > 1 ? _trace!.pts[1] : first;
    final heading0 = _bearingDeg(first, second);
    await _updateCarAndCamera(_currentPos!, heading0);

    _startTasPolling();
    setState(() {});
  }

  // ⬅️ _pause 함수 수정 (폴링만 중단)
  void _pause() {
    _stopTasPolling();
    _startTime = null; // 시간 측정도 중단
    setState(() {});
  }

  // ⬅️ _restart 함수 수정 (세션 종료 후 다시 시작)
  Future<void> _restart() async {
    if (_sessionId != 'dev-local') {
      try {
        await _tasApi.stopVideoSession(sessionId: _sessionId);
      } catch (e) {
        print('세션 종료 실패: $e');
      }
      _sessionId = 'dev-local';
    }

    _stopTasPolling();
    _currentPos = null;
    _currentKmh = 0.0;
    _elapsedTime = '00:00';
    _startTime = null;

    _tas = null;
    _tasSeverity = null;
    _tasTitle = null;
    _tasSub = null;

    await _start();
  }

  // _resetAll 함수 수정 (상태 완전 초기화)
  Future<void> _resetAll() async {
    _stopTasPolling();

    if (_sessionId != 'dev-local') {
      try {
        await _tasApi.stopVideoSession(sessionId: _sessionId);
      } catch (e) {
        print('세션 종료 실패: $e');
      }
      _sessionId = 'dev-local';
    }

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
    _tas = null;
    _tasSeverity = null;
    _tasTitle = null;
    _tasSub = null;

    setState(() {});
  }

  @override
  void dispose() {
    _stopTasPolling();
    _tasApi.close();
    super.dispose();
  }

  // =========================================================================
  // UI 빌드 메서드
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 1. 시나리오 선택 화면
    if (_selected == null) {
      final order = const [DriveScenario.rain, DriveScenario.snow];
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
              return _scenarioListCard(
                title: _scenarioTitle(s),
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

    // 2. 주행 전 상세 화면
    final slot = _mgr.scenarios[_selected]!;
    final tr = slot.trace!;
    if (!_running) {
      return Scaffold(
        appBar: AppBar(title: Text('TAS · ${_scenarioTitle(_selected)}')),
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

    // 3. 지도 + 재생 화면

    return Scaffold(
      appBar: AppBar(
        title: Text('TAS · ${_scenarioTitle(_selected)}'),
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
            rotateGesturesEnabled: true,   // 회전 제스처 허용
            tiltGesturesEnabled: true,     // 틸트 제스처 허용(렌더러가 최신일 때 bearing/tilt 안정)
            compassEnabled: false,
          ),

          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: AlertBanner(
                visible: _tasSeverity == 1 || _tasSeverity == 2,
                alert: null,
                curKmh: _currentKmh,
                playMs: 0,
                firstEnterPlayMs: 0,
                tasTitle: _tasTitle,
                tasSub: _tasSub,
                severity: _tasSeverity,
              ),
            ),
          ),

          // 속도: 나침반 아래(상단 좌측)
          Positioned(
            top: 68,
            left: 12,
            child: hud.SpeedHud(kmh: _currentKmh),
          ),

          // TAS 상태 HUD 위치 조정
          if (_tas != null)
            Positioned(
              top: 140,
              left: 12,
              child: _buildTasStatusHud(_tas!),
            ),

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

  // --- 보조 UI 함수 (변경 없음) ---

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
        title: _scenarioTitle(s),
        trace: tr,
        onStart: () async {
          Navigator.of(context).pop();
          _trace = tr;
          setState(() => _selected = s);
          await _start();
        },
      ),
    );
  }

  String _scenarioTitle(DriveScenario? s) {
    switch (s) {
      case DriveScenario.rain:
        return '비 오는 날';
      case DriveScenario.snow:
        return '눈 오는 날';
      default:
        return '주행 구간';
    }
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

  Widget _buildTasStatusHud(TasStatus s) {
    final int? dc = s.decelClass; // 0=정상, 1=주의, 2=위험
    final Color bg = switch (dc) {
      2 => Colors.red.shade700,
      1 => Colors.orange.shade700,
      _ => Colors.green.shade700,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('제한 속도: ${s.maxSpd.toStringAsFixed(0)} km/h',
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          Text('추천 속도: ${s.rec.toStringAsFixed(0)} km/h',
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          Text(
            dc == 2 ? '🚨 위험' : (dc == 1 ? '⚠️ 주의' : '✅ 정상 주행'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }
}