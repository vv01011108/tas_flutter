/* 화면(구글맵, 카메라 적용) */
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../misc/about_page.dart';
import '../../shared/config.dart';
import '../../shared/geo.dart';
import '../../alerts/presentation/alert_banner.dart';
import '../../alerts/domain/alert_engine.dart';
import '../../navigation/domain/player_controller.dart';
import '../../navigation/domain/trace_models.dart';
import '../../navigation/domain/scenario_manager.dart';
import '../../navigation/presentation/widgets/preview_sheet.dart';
import '../../shared/geo_addr.dart';

// 일반 카드(시나리오/요약용)
import '../../navigation/presentation/widgets/start_end_card.dart' as card;

// HUD 유틸 (UI는 hud_basic.dart 그대로 사용)
import '../../navigation/presentation/hud_basic.dart' as hud;

// REST API & 매핑
import '../../api/tas_status.dart';
import '../../api/tas_api.dart';

import 'package:image_picker/image_picker.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final ScenarioManager _mgr = ScenarioManager();

  late final TasApi _tasApi;
  Timer? _timer;
  TasStatus? _tas; // 마지막 응답 보관
  String _sessionId = 'dev-local'; // 서버에서 세션 발급 받으면 그거로 교체

  static const String _serverIp = '192.168.0.22'; // 당신의 PC 사설 IP
  static const String _modelPath = 'data/models/cnn_best.pth'; // 서버 모델 경로

  late GoogleMapController _map;
  Completer<void>? _mapReady;

  DriveScenario? _selected;
  TraceData? _trace;
  AlertEngine? _engine;
  PlayerController? _player;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final Set<Circle> _circles = {};
  Marker? _car;
  BitmapDescriptor? _carIcon;

  bool _booting = true;
  bool _running = false;

  // 🗑️ REST 폴링 변수 삭제됨: _modelPoller, _lastGenMs

  @override
  void initState() {
    super.initState();
    _tasApi = TasApi(baseHost: _serverIp);
    // 🗑️ _modelApi 초기화 로직 삭제됨
    _initAll();
  }

  Future<void> _fetchTas(LatLng pos, double curKmh) async {
    try {
      final s = await _tasApi.fetchCurrentStatus(
        sessionId: _sessionId,
        spd: curKmh,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      _tas = s;

      // 경고 배너와 연동하고 싶다면:
      if (s.warn == 1) _engine?.showWarn('감속 필요: ${s.spd.toStringAsFixed(1)} > ${s.rec.toStringAsFixed(1)}');
      else _engine?.clearWarn();

    } catch (_) {
      // 네트워크 에러는 조용히 무시(원하면 로그)
    }
  }

  // TAS 상태를 0.5초(500ms)마다 조회하는 폴링 함수
  void _startTasPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_running || _player == null || _trace == null) {
        _timer?.cancel();
        return;
      }

      // 현재 플레이어의 위치와 속도
      final player = _player!;
      final tr = _trace!;
      final s = player.seg;

      if (s >= tr.pts.length - 1) return; // 주행 종료 시 스킵

      final t0 = tr.timeMs[s], t1 = tr.timeMs[s + 1];
      final tau = ((player.playMs - t0) / (t1 - t0)).clamp(0.0, 1.0);
      final pos = lerpLatLng(tr.pts[s], tr.pts[s + 1], tau);
      final curKmh = player.curKmh;

      // _sessionId가 발급되었는지 확인 후 호출
      if (_sessionId != 'dev-local') {
        _fetchTas(pos, curKmh);
      }
    });
  }

  // 주행 종료 시 타이머 정리
  void _stopTasPolling() {
    _timer?.cancel();
    _timer = null;
    _tas = null; // 상태 초기화
  }

  Future<String?> _pickVideoFromGallery() async {
    final picker = ImagePicker();
    // 비디오만 선택
    final XFile? video = await picker.pickVideo(source: ImageSource.gallery);

    return video?.path;
  }

  Future<void> _initAll() async {
    _carIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(),
      'assets/icons/car.png',
    );

    // 시나리오 프리로드(주소 포함)
    for (final s in _mgr.scenarios.keys) {
      _mgr.preload(s, KrAddressService.krRoadAddress).then((_) {
        if (mounted) setState(() {});
      });
    }
    setState(() => _booting = false);
  }

  // 🗑️ _startModelPolling(DriveScenario s) 함수 삭제됨

  // 🗑️ _stopModelPolling() 함수 삭제됨

  // 🗑️ _setupEngine(DriveScenario s) 함수 삭제됨

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

  Future<void> _start() async {
    if (_trace == null || _player == null) return;

    // ==========================================================
    // 🔑 1. 비디오 선택 및 세션 ID 발급 (POST 요청)
    // ==========================================================
    // 1. 갤러리에서 비디오 선택 시도
    final String? actualVideoPath = await _pickVideoFromGallery();

    if (actualVideoPath == null) {
      print("비디오 선택이 취소되었습니다. 주행을 시작하지 않습니다.");
      return;
    }

    try {
      // 2. POST 요청 실행
      final newSessionId = await _tasApi.getSessionId(
        localVideoPath: actualVideoPath,
        serverModelPath: _modelPath,
      );
      _sessionId = newSessionId;
      print('✅ 세션 ID 발급 성공 후: $_sessionId');

      // ✅ [추가] TAS 기능만 사용할 경우 AlertEngine 및 PlayerController 초기화
      // TAS는 모델과는 별개로 작동하므로, 여기서 AlertEngine 및 PlayerController를 초기화해야 합니다.
      _engine = AlertEngine([]); // 빈 AlertNode 리스트로 엔진 초기화
      _player = PlayerController(alertEngine: _engine); // 플레이어 연결
      _player!.attachData(_trace!);

      // ✅ [추가] 세션 발급 성공 후 TAS 폴링 시작
      _startTasPolling();

    } catch (e) {
      print('❌ 세션 ID 발급 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('세션 시작 실패: 서버 및 네트워크 오류 ($e)'), backgroundColor: Colors.red),
        );
      }
      return; // 실패 시 주행 중단
    }

    final tr = _trace!;
    final player = _player!;
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

    final mvIdx = player.firstMovingSeg(minMeters: 1.0);
    player.camBearingDeg = bearingDegBetween(tr.pts[mvIdx], tr.pts[mvIdx + 1]);

    _car = Marker(
      markerId: const MarkerId('car'),
      position: tr.pts.first,
      icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      anchor: const Offset(0.5, 0.5),
      rotation: 0.0,
      flat: false,
    );
    setState(() {});
    await _applyNavCamera(tr.pts.first, player.camBearingDeg);

    player.start(onTick: () async {
      final s = player.seg;
      if (s >= tr.pts.length - 1) {
        setState(() {});
        return;
      }

      final t0 = tr.timeMs[s], t1 = tr.timeMs[s + 1];
      final tau = ((player.playMs - t0) / (t1 - t0)).clamp(0.0, 1.0);
      final p = lerpLatLng(tr.pts[s], tr.pts[s + 1], tau);

      _car = _car?.copyWith(positionParam: p, rotationParam: 0.0);
      await _applyNavCamera(p, player.camBearingDeg);

      // _engine이 null이 아님 (위에서 초기화했으므로)
      _circles..clear()..addAll(_engine!.state.circles);
      setState(() {});
    });
  }

  void _pause() => _player?.stop();

  Future<void> _skip10s() async {
    if (_trace == null || _player == null) return;
    final tr = _trace!, player = _player!;
    player.seekBy(10000);

    final s = player.seg;
    final LatLng p = (s >= tr.pts.length - 1)
        ? tr.pts.last
        : lerpLatLng(
      tr.pts[s],
      tr.pts[s + 1],
      ((player.playMs - tr.timeMs[s]) /
          (tr.timeMs[s + 1] - tr.timeMs[s]))
          .clamp(0.0, 1.0),
    );

    _car = _car?.copyWith(positionParam: p, rotationParam: 0.0);
    await _applyNavCamera(p, player.camBearingDeg);
    _circles..clear()..addAll(_engine!.state.circles);
    setState(() {});
  }

  Future<void> _restart() async {
    if (_trace == null || _player == null) return;
    final tr = _trace!, player = _player!;
    player.reset();

    final mvIdx = player.firstMovingSeg(minMeters: 1.0);
    player.camBearingDeg = bearingDegBetween(tr.pts[mvIdx], tr.pts[mvIdx + 1]);

    _car = _car?.copyWith(positionParam: tr.pts.first, rotationParam: 0.0) ??
        Marker(
          markerId: const MarkerId('car'),
          position: tr.pts.first,
          icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          rotation: 0.0,
          flat: false,
        );

    _circles.clear();
    setState(() {});
    await _applyNavCamera(tr.pts.first, player.camBearingDeg);
    await _start();
  }

  Future<void> _resetAll() async {
    // 🗑️ _stopModelPolling() 호출 삭제됨
    _stopTasPolling(); // TAS 폴링 정리

    // 🔑 세션 종료 (POST 요청)
    if (_sessionId != 'dev-local') {
      try {
        await _tasApi.stopVideoSession(sessionId: _sessionId); // 👈 await 추가
      } catch (e) {
        print('세션 종료 실패: $e');
      }
      _sessionId = 'dev-local'; // 초기값으로 리셋
    }

    _player?.reset();
    _markers.clear();
    _polylines.clear();
    _circles.clear();
    _car = null;
    _running = false;
    _selected = null;
    _trace = null;
    _engine = null; // 엔진 초기화
    _player = null; // 플레이어 초기화
    setState(() {});
  }

  @override
  void dispose() {
    // 🗑️ _stopModelPolling() 호출 삭제됨
    _stopTasPolling();
    _player?.dispose();
    _tasApi.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 시나리오 선택 화면
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

    // 주행 전 상세
    if (!_running) {
      final slot = _mgr.scenarios[_selected]!;
      final tr = slot.trace!;
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
                  // 🗑️ _setupEngine(_selected!) 호출 삭제됨. _start()에서 처리
                  _trace = tr; // _trace는 여기서 설정
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

    // 지도 + 재생 화면
    final tr = _trace!;
    final alertSt = _engine!.state;

    return Scaffold(
      appBar: AppBar(
        title: Text('TAS · ${_scenarioTitle(_selected)}'),
        actions: [IconButton(onPressed: _resetAll, icon: const Icon(Icons.refresh))],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: tr.pts.first, zoom: 16),
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
                curKmh: _player!.curKmh,
                playMs: _player!.playMs,
                firstEnterPlayMs: alertSt.firstEnterPlayMs,
              ),
            ),
          ),

          // 속도: 나침반 아래(상단 좌측)
          if (_running)
            Positioned(
              top: 68,
              left: 12,
              child: hud.SpeedHud(kmh: _player!.curKmh),
            ),

          // 🔑 [수정] TAS 상태 HUD 위치 조정
          if (_running && _tas != null)
            Positioned(
              top: 140, // SpeedHud 아래에 위치
              left: 12,
              child: _buildTasStatusHud(_tas!),
            ),

          if (_running)
            Positioned(
              left: 12,
              bottom: 20,
              child: hud.CoordTimeHud(
                lat: _car?.position.latitude,
                lng: _car?.position.longitude,
                elapsed: _player!.fmtElapsed(),
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
            Expanded(child: ElevatedButton(onPressed: _skip10s, child: const Text('건너뛰기'))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(onPressed: _restart, child: const Text('재시작'))),
          ],
        ),
      ),
    );
  }

  // --- 보조 UI ---

  Widget _scenarioListCard({
    required String title,
    required String? startAddr,
    required String? endAddr,
    required TraceData? trace,
    required bool loading,
    required VoidCallback onTap,
  }) {
    if (loading) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: LinearProgressIndicator(minHeight: 6),
        ),
      );
    }
    if (trace == null) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('로딩 실패', style: TextStyle(color: Colors.red)),
        ),
      );
    }
    final tr = trace;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: card.StartEndCard(
            startAddr: startAddr ?? '주소 조회 실패',
            start: card.LatLngLite(tr.start.latitude, tr.start.longitude),
            endAddr: endAddr ?? '주소 조회 실패',
            end: card.LatLngLite(tr.end.latitude, tr.end.longitude),
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
          // 🗑️ _setupEngine(s) 호출 삭제됨
          _trace = tr; // _trace는 여기서 설정
          setState(() => _selected = s);
          // 🗑️ Future<void>.delayed 호출 삭제됨
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
    // 경고(warn=1) 시 배경색을 빨간색으로 변경
    final color = s.warn == 1 ? Colors.red.shade700 : Colors.green.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 4)],
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