/* api/tas_api.dart */
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'package:http_parser/http_parser.dart';
import 'package:tas_app/features/api/tas_status.dart';

/// 대용량 JSON 파싱을 별도 isolate로
Future<dynamic> _parseLargeJson(String responseBody) async {
  // Isolate.run은 SDK 3.8+ 에서 사용 가능. 낮은 버전이면 compute(...)로 대체
  return Future(() => jsonDecode(responseBody));
}

class TasApi {
  final String baseHost; // 예) "192.168.0.22:8000" 또는 "192.168.0.22"
  final HttpClient _httpClient;

  TasApi({required this.baseHost}) : _httpClient = HttpClient();

  String get _base {
    // 포트가 없으면 8000 기본
    if (baseHost.contains(':')) return 'http://$baseHost';
    return 'http://$baseHost:8000';
  }

  void close() => _httpClient.close(force: true);

  // ─────────────────────────────────────────────────────────────
  // ① 업로드 없이: 서버에 있는 파일 경로로 세션 시작
  //    POST /api/v1/start_video_session_by_path (x-www-form-urlencoded)
  // ─────────────────────────────────────────────────────────────
  Future<String> startByPath({
    required String serverVideoPath, // 서버 절대경로
    required String serverModelPath, // 서버 절대경로
    int imgSize = 224,
    double intervalSec = 1.0,
  }) async {
    final uri = Uri.parse('$_base/api/v1/start_video_session_by_path');

    final req = await _httpClient.postUrl(uri);
    final body = [
      'video_path=${Uri.encodeQueryComponent(serverVideoPath)}',
      'model_path=${Uri.encodeQueryComponent(serverModelPath)}',
      'img_size=$imgSize',
      'interval_sec=$intervalSec',
    ].join('&');

    req.headers.contentType =
        ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    req.write(body);

    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != 200) {
      throw Exception('startByPath 실패: ${resp.statusCode} $text');
    }
    final j = await _parseLargeJson(text);
    if (j is Map<String, dynamic> && j['session_id'] != null) {
      return j['session_id'] as String;
    }
    throw Exception('세션 ID 응답 형식 오류: $text');
  }

  // (옵션) 업로드 방식도 계속 쓰려면 유지. 서버 필드명은 "video_file"임에 주의!
  Future<String> startByUpload({
    required String localVideoPath,
    required String serverModelPath,
    int imgSize = 224,
    double intervalSec = 1.0,
  }) async {
    final uri = Uri.parse('$_base/api/v1/start_video_session');

    final file = File(localVideoPath);
    if (!await file.exists()) {
      throw Exception('Video not found: $localVideoPath');
    }

    final boundary = '----TasBoundary${DateTime.now().millisecondsSinceEpoch}';
    final req = await _httpClient.postUrl(uri);
    req.headers.contentType =
        ContentType.parse('multipart/form-data; boundary=$boundary');

    // model_path
    req.write('--$boundary\r\n');
    req.write('Content-Disposition: form-data; name="model_path"\r\n\r\n');
    req.write('$serverModelPath\r\n');

    // img_size
    req.write('--$boundary\r\n');
    req.write('Content-Disposition: form-data; name="img_size"\r\n\r\n');
    req.write('$imgSize\r\n');

    // interval_sec
    req.write('--$boundary\r\n');
    req.write('Content-Disposition: form-data; name="interval_sec"\r\n\r\n');
    req.write('$intervalSec\r\n');

    // video_file  ← 서버는 이 필드명을 기대함
    req.write('--$boundary\r\n');
    req.write(
        'Content-Disposition: form-data; name="video_file"; filename="${file.uri.pathSegments.last}"\r\n');
    req.write('Content-Type: ${MediaType('video', 'mp4')}\r\n\r\n');
    await req.addStream(file.openRead());
    req.write('\r\n--$boundary--\r\n');

    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != 200) {
      throw Exception('startByUpload 실패: ${resp.statusCode} $text');
    }
    final j = await _parseLargeJson(text);
    if (j is Map<String, dynamic> && j['session_id'] != null) {
      return j['session_id'] as String;
    }
    throw Exception('세션 ID 응답 형식 오류: $text');
  }

  // ─────────────────────────────────────────────────────────────
  // ② 상태 조회: GET /api/v1/current_status
  // ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> fetchCurrentStatusRaw({
    required String sessionId,
    required double spd,
    required double latitude,
    required double longitude,
  }) async {
    final qp = {
      'session_id': sessionId,
      'spd': spd.toStringAsFixed(2),
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
    };
    final uri = Uri.parse('$_base/api/v1/current_status')
        .replace(queryParameters: qp);

    final req = await _httpClient.getUrl(uri);
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();

    if (resp.statusCode != 200) {
      throw Exception('current_status 실패: ${resp.statusCode} $text');
    }
    final j = await _parseLargeJson(text);
    return j as Map<String, dynamic>;
  }

  // (편의) 앱 모델로 바로 파싱하려면 tas_status.dart의 TasStatus 사용
  Future<TasStatus> fetchCurrentStatus({
    required String sessionId,
    required double spd,
    required double latitude,
    required double longitude,
  }) async {
    final j = await fetchCurrentStatusRaw(
      sessionId: sessionId,
      spd: spd,
      latitude: latitude,
      longitude: longitude,
    );
    return TasStatus.fromJson(j);
  }

  // ─────────────────────────────────────────────────────────────
  // ③ 세션 종료: POST /api/v1/stop_video_session  (GET 아님!)
  // ─────────────────────────────────────────────────────────────
  Future<void> stopVideoSession({required String sessionId}) async {
    final uri = Uri.parse('$_base/api/v1/stop_video_session');

    final req = await _httpClient.postUrl(uri);
    req.headers.contentType =
        ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    req.write('session_id=${Uri.encodeQueryComponent(sessionId)}');

    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != 200) {
      throw Exception('stop_video_session 실패: ${resp.statusCode} $text');
    }
  }
}