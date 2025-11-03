/* api/tas_api.dart */
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'package:http_parser/http_parser.dart';

// =========================================================================
// 모델
// =========================================================================
class TasStatus {
  final double spd;       // (현재 속도 - API에서 받아옴)
  final double maxSpd;
  final double rec;
  final int warn;
  final double latitude;  // ⬅️ 추가: 실시간 위도
  final double longitude; // ⬅️ 추가: 실시간 경도

  TasStatus({
    required this.spd,
    required this.maxSpd,
    required this.rec,
    required this.warn,
    required this.latitude,
    required this.longitude,
  });

  factory TasStatus.fromJson(Map<String, dynamic> json) {
    return TasStatus(
      spd: (json['spd'] as num).toDouble(),
      maxSpd: (json['max_spd'] as num).toDouble(),
      rec: (json['rec'] as num).toDouble(),
      warn: json['warn'] as int,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

// =========================================================================
// Isolate를 이용한 대용량 JSON 파싱 (백그라운드 스레드에서 실행)
// =========================================================================
Future<dynamic> _parseLargeJson(String responseBody) {
  return Isolate.run(() => jsonDecode(responseBody));
}

// =========================================================================
// TAS API 클라이언트
// =========================================================================
class TasApi {
  final String baseHost;
  final HttpClient _httpClient;

  TasApi({required this.baseHost})
      : _httpClient = HttpClient();

  void close() {
    _httpClient.close(force: true);
  }

  // 세션 시작 (비디오 업로드)
  Future<String> getSessionId({
    required String localVideoPath,
    required String serverModelPath,
  }) async {
    final uri = Uri.parse('http://$baseHost/api/session/start');

    final request = await _httpClient.postUrl(uri);
    final boundary = '----TasBoundary${DateTime.now().millisecondsSinceEpoch}';
    request.headers.contentType = ContentType.parse('multipart/form-data; boundary=$boundary');

    final file = File(localVideoPath);
    if (!await file.exists()) {
      throw Exception("Video file not found at $localVideoPath");
    }

    // 데이터 쓰기 (openWrite 대신 request 자체를 IOSink처럼 사용)
    request.write('--$boundary\r\n');
    request.write('Content-Disposition: form-data; name="model_path"\r\n\r\n');
    request.write('$serverModelPath\r\n');

    request.write('--$boundary\r\n');
    request.write('Content-Disposition: form-data; name="video"; filename="${file.path.split('/').last}"\r\n');
    request.write('Content-Type: ${MediaType('video', 'mp4')}\r\n\r\n');

    await request.addStream(file.openRead());

    request.write('\r\n--$boundary--\r\n');

    final response = await request.close();

    if (response.statusCode != 200) {
      final errorBody = await response.transform(utf8.decoder).join();
      throw Exception('Failed to start session: ${response.statusCode} - $errorBody');
    }

    final responseBody = await response.transform(utf8.decoder).join();
    final json = await _parseLargeJson(responseBody);

    if (json is Map<String, dynamic> && json.containsKey('session_id')) {
      return json['session_id'] as String;
    }
    throw Exception('Invalid session ID response format');
  }

  // 실시간 상태 업데이트 (폴링)
  Future<TasStatus> fetchCurrentStatus({
    required String sessionId,
    required double spd,
    required double latitude,
    required double longitude,
  }) async {
    final queryParams = {
      'session_id': sessionId,
      'spd': spd.toStringAsFixed(2),
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
    };
    final uri = Uri.parse('http://$baseHost/api/status').replace(queryParameters: queryParams);

    final request = await _httpClient.getUrl(uri);
    final response = await request.close();

    if (response.statusCode != 200) {
      final errorBody = await response.transform(utf8.decoder).join();
      throw Exception('Failed to fetch status: ${response.statusCode} - $errorBody');
    }

    final responseBody = await response.transform(utf8.decoder).join();
    final json = await _parseLargeJson(responseBody);

    return TasStatus.fromJson(json as Map<String, dynamic>);
  }

  // 세션 종료
  Future<void> stopVideoSession({required String sessionId}) async {
    final uri = Uri.parse('http://$baseHost/api/session/stop?session_id=$sessionId');

    final request = await _httpClient.getUrl(uri);
    await request.close();
  }
}