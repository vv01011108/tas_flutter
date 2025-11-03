/* features/navigation/presentation/map_page.dart */
import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../misc/about_page.dart';
import '../../shared/config.dart';
import '../../alerts/presentation/alert_banner.dart';
import '../../alerts/domain/alert_engine.dart';
import '../../navigation/domain/trace_models.dart';
import '../../navigation/domain/scenario_manager.dart';
import '../../navigation/presentation/widgets/preview_sheet.dart';
import '../../shared/geo_addr.dart';

import '../../navigation/presentation/widgets/start_end_card.dart' as card;

import '../../navigation/presentation/hud_basic.dart' as hud;

import '../../api/tas_api.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final ScenarioManager _mgr = ScenarioManager();

  late final TasApi _tasApi;
  Timer? _timer;
  TasStatus? _tas;
  String _sessionId = 'dev-local';

  // 💡 [1] 서버 IP 및 모델 경로 (네트워크 환경에 따라 변경되어야 함)
  static const String _serverIp = '192.168.0.22';
  static const String _modelPath = 'data/models/cnn_best.pth';

  late GoogleMapController _map;
  Completer<void>? _mapReady;

  DriveScenario? _selected;
  TraceData? _trace;

  final AlertEngine _engine = AlertEngine();
  LatLng? _currentPos;
  double _currentKmh = 0.0;
  String _elapsedTime = '00:00';
  DateTime? _startTime;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final Set<Circle> _circles = {};
  Marker? _car;
  BitmapDescriptor? _carIcon;

  bool _booting = true;
  bool _running = false;

  // 💡 [2] 하드코딩된 비디오 경로
  static const String _hardcodedVideoPath =
      'C:\\Users\\seonga\\Desktop\\TAS_251101\\api\\data\\videos\\240716_video5.mp4';

  @override
  void initState() {
    super.initState();
    _tasApi = TasApi(baseHost: _serverIp);
    _initAll();
  }

  Future<String?> _dummyAddress(LatLng pos) async {
    return null; // 주소 검색 시도 없이 즉시 null 반환
  }

  // ⬅️ 필수 함수: 초기 설정
  Future<void> _initAll() async {
    _carIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(),
      'assets/icons/car.png',
    );

    for (final s in _mgr.scenarios.keys) {
      // 주소 검색 API 호출로 인한 Failed host lookup 오류 방지
      _mgr.preload(s, _dummyAddress).then((_) {
        if (mounted) setState(() {});
      });
    }
    setState(() => _booting = false);
  }

  // API 호출 함수 수정: 서버로 현재 위치/속도를 보내고, 서버에서 받은 위치로 갱신
  Future<void> _fetchTas(LatLng pos, double curKmh) async {
    try {
      final s = await _tasApi.fetchCurrentStatus(
        sessionId: _sessionId,
        spd: curKmh,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );

      _tas = s;

      // 💡 [3] 서버 응답을 기반으로 현재 위치 및 속도 갱신
      _currentPos = LatLng(s.latitude, s.longitude);
      _currentKmh = s.spd;

      if (s.warn == 1) _engine.showWarn('감속 필요: ${s.spd.toStringAsFixed(1)} > ${s.rec.toStringAsFixed(1)}');
      else _engine.clearWarn();

      if (_startTime != null) {
        final duration = DateTime.now().difference(_startTime!);
        _elapsedTime = _formatDuration(duration);
      }

      await _updateCarAndCamera(_currentPos!, _currentKmh);
      setState(() {});

    } catch (_) {
      // 네트워크 에러는 조용히 무시
    }
  }

  // 경과 시간 포맷 함수
  String _formatDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }


  // ⬅️ 폴링 루프 수정: 💡 [4] API 폴링 간격을 서버 샘플링 간격에 맞춰 1.0초로 변경
  void _startTasPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_running || _trace == null || _currentPos == null) {
        _timer?.cancel();
        return;
      }

      final dummyPos = _currentPos!;
      final dummyKmh = _currentKmh;

      if (_sessionId != 'dev-local') {
        _fetchTas(dummyPos, dummyKmh);
      }
    });
  }

  void _stopTasPolling() {
    _timer?.cancel();
    _timer = null;
    _tas = null;
  }

  Future<void> _applyNavCamera(LatLng pos, double bearing) async {
    await _map.moveCamera(
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

  // ⬅️ 차량 마커/카메라 업데이트 로직
  Future<void> _updateCarAndCamera(LatLng pos, double spd) async {
    const double rotation = 0.0;

    _car = _car?.copyWith(positionParam: pos, rotationParam: rotation) ??
        Marker(
          markerId: const MarkerId('car'),
          position: pos,
          icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          rotation: rotation,
          flat: false,
        );

    _circles..clear()..addAll(_engine.state.circles);
    await _applyNavCamera(pos, rotation);
    setState(() {});
  }


  // ⬅️ _start 함수 수정: 💡 [5] 비디오 파일 전송 로직을 제거하고, 경로만 서버에 전달
  Future<void> _start() async {
    if (_trace == null) return;

    // 💡 [5-1] 비디오 경로를 하드코딩된 로컬 경로로 설정 (파일 전송 대신 경로만 사용)
    final String actualVideoPath = _hardcodedVideoPath;

    log('✅ 비디오 경로 확보 (하드코딩): $actualVideoPath');

    try {
      // 💡 [5-2] 서버가 이미 로컬 경로에 접근 가능하다고 가정하고 경로만 전달
      // 주의: 실제 사용 시 TasApi는 이 경로를 기반으로 서버가 파일 처리를 시작해야 함.
      final newSessionId = await _tasApi.getSessionId(
        localVideoPath: actualVideoPath,
        serverModelPath: _modelPath,
      );
      _sessionId = newSessionId;
      print('✅ 세션 ID 발급 성공 후: $_sessionId');

      _currentPos = _trace!.pts.first;
      _currentKmh = 0.0;
      _startTime = DateTime.now();
      _elapsedTime = '00:00';

      _startTasPolling();

    } catch (e) {
      print('❌ 세션 ID 발급 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('세션 시작 실패: 서버 및 네트워크 오류 ($e)'), backgroundColor: Colors.red),
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

    await _updateCarAndCamera(_currentPos!, _currentKmh);
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
    _engine.clearAll();

    await _start();
  }

  // ⬅️ _resetAll 함수 수정 (상태 완전 초기화)
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
    _circles.clear();
    _car = null;
    _running = false;
    _selected = null;
    _trace = null;
    _currentPos = null;
    _currentKmh = 0.0;
    _elapsedTime = '00:00';
    _startTime = null;
    _engine.clearAll();

    setState(() {});
  }

  @override
  void dispose() {
    _stopTasPolling();
    _tasApi.close();
    super.dispose();
  }

  // =========================================================================
  // 🎨 UI 빌드 메서드 (변경 없음)
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
    final alertSt = _engine.state;

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
            circles: _circles,
            zoomControlsEnabled: false,
          ),
          // 상단 경고 배너
          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: AlertBanner(
                visible: alertSt.visible,
                alert: alertSt.current,
                curKmh: _currentKmh,
                playMs: 0,
                firstEnterPlayMs: 0,
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
    final hasError = !loading && trace == null;

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
    final color = s.warn == 1 ? Colors.red.shade700 : Colors.green.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '제한속도: ${s.maxSpd.toStringAsFixed(0)} km/h',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Text(
            '추천속도: ${s.rec.toStringAsFixed(0)} km/h',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Text(
            s.warn == 1 ? '⚠️ 감속 경고!' : '✅ 주행 정상',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}