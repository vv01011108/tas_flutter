// lib/features/api/tas_api.dart
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'tas_status.dart';

/// TAS 백엔드 GET API 클라이언트
/// - 엔드포인트: GET /api/v1/current_status
/// - 쿼리: session_id, spd, latitude, longitude
class TasApi {
  final String baseHost; // 예: '10.0.2.2' (안드 에뮬), 'localhost' (iOS 시뮬/웹/데스크탑)
  final int port;
  final http.Client _client;

  TasApi({
    String? baseHost,
    int this.port = 8000,
    http.Client? client,
  })  : baseHost = baseHost ?? _resolveDefaultHost(),
        _client = client ?? http.Client();

  /// 플랫폼에 따라 기본 호스트 자동 판별
  static String _resolveDefaultHost() {
    if (kIsWeb) return 'localhost';
    try {
      if (Platform.isAndroid) return '10.0.2.2'; // Android 에뮬레이터 -> 호스트
      // iOS 시뮬 / 데스크탑 / 기타
      return 'localhost';
    } catch (_) {
      return 'localhost';
    }
  }

  Uri _buildUri(String path, Map<String, String> query) {
    return Uri(
      scheme: 'http',
      host: baseHost,
      port: port,
      path: path,
      queryParameters: query,
    );
  }

  Future<String> getSessionId({
    required String localVideoPath,
    required String serverModelPath, // 서버 모델 경로 (예: 'data/models/cnn_best.pth')
  }) async {
    // 1. URL 생성 (baseHost/port 사용)
    final uri = _buildUri('/api/v1/start_video_session', {}); // POST는 쿼리 없이

    // 2. MultipartRequest 생성 (http.Client 대신 독립적으로 request.send() 사용)
    var request = http.MultipartRequest('POST', uri)
      ..fields['model_path'] = serverModelPath
      ..fields['img_size'] = '224'
      ..fields['interval_sec'] = '1.0';

    // 3. 로컬 비디오 파일 첨부
    try {
      request.files.add(
        await http.MultipartFile.fromPath(
          'video_file',
          localVideoPath,
        ),
      );
    } catch (e) {
      throw Exception('로컬 비디오 파일 접근 실패: $e');
    }

    // 4. 요청 전송 및 응답 처리
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      final sessionId = data['session_id'] as String;
      print('✅ 세션 ID 발급 성공 (Host: $baseHost:$port): $sessionId');
      return sessionId;
    } else {
      print('❌ 세션 발급 실패 (Status: ${response.statusCode}): ${response.body}');
      throw Exception('Failed to start video session');
    }
  }

  /// GET /api/v1/current_status
  /// 반환 JSON에서 필요한 6개(+decel_class 옵션)만 모델로 매핑
  Future<TasStatus> fetchCurrentStatus({
    required String sessionId,
    required double spd,
    required double latitude,
    required double longitude,
  }) async {
    final uri = _buildUri('/api/v1/current_status', {
      'session_id': sessionId,
      'spd': spd.toString(),
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
    });

    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw Exception('API ${res.statusCode}: ${res.body}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return TasStatus.fromJson(map);
  }

  void close() => _client.close();
}
