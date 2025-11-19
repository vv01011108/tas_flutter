
/* SSE 클라이언트: /api/v1/stream_xlsx_video_frames 업로드 + 라인파싱 */

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

// SSE 클라이언트 (업로드형)
class TasSseClient {
  final String baseHost; // 예: '192.168.0.22:8000'
  http.Client? _client;
  StreamSubscription<String>? _sub;

  TasSseClient(this.baseHost);

  Future<void> start({
    required String xlsxPath,
    required String videoPath,
    required String modelPath,
    double fps = 1.0,
    int imgSize = 224,
    double intervalSec = 1.0,
    required void Function(Map<String, dynamic> meta) onStart,
    required void Function(Map<String, dynamic> tick) onTick,
    required void Function(Map<String, dynamic> endInfo) onEnd,
    required void Function(Object err) onError,
  }) async {
    _client = http.Client();
    final uri = Uri.parse('http://$baseHost/api/v1/stream_xlsx_video_frames');
    final req = http.MultipartRequest('POST', uri)
      ..fields['xlsx_path'] = xlsxPath
      ..fields['video_path'] = videoPath
      ..fields['model_path'] = modelPath
      ..fields['fps'] = fps.toString()
      ..fields['img_size'] = imgSize.toString()
      ..fields['interval_sec'] = intervalSec.toString()
      ..fields['backbone'] = 'convnext_tiny'
      ..fields['batch_size'] = '1';

    final res = await _client!.send(req);
    if (res.statusCode != 200) {
      throw Exception('SSE 연결 실패: ${res.statusCode}');
    }

    // text/event-stream 라인 단위 수신
    _sub = res.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.startsWith('data: ')) {
        final js = line.substring(6);
        try {
          final obj = jsonDecode(js) as Map<String, dynamic>;
          if (obj['meta'] != null) {
            onStart(obj);
          } else if (obj['done'] == true) {
            onEnd(obj);
          } else if (obj['row_index'] != null) {
            print("TICK EVENT: $obj");
            onTick(obj);
          }
        } catch (e) {
          onError(e);
        }
      }
    }, onError: (e) {
      onError(e);
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
  }
}
