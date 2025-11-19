import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../shared/config.dart';

class KrAddressService {
  /// 한국어 도로명 주소 우선 반환. 없으면 지번/기타로 폴백.
  static Future<String?> krRoadAddress(LatLng p) async {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=${p.latitude},${p.longitude}'
          '&language=eng'      // 영어
          '&region=KR'        // 한국 지역 편향
          '&result_type=street_address|route|political'
          '&key=${AppConfig.googleGeocodeKey}',
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) return null;

    final data = json.decode(res.body) as Map<String, dynamic>;
    final status = data['status'] as String? ?? 'UNKNOWN';

    if (status != 'OK') {
      // 필요시 로그용으로만 사용
      // debugPrint('[Geocode] status=$status, err=${data['error_message']}');
      return null;
    }

    final results = (data['results'] as List).cast<Map<String, dynamic>>();
    if (results.isEmpty) return null;

    // 첫 결과 사용 (도로명/POI를 우선 요청했음)
    final formatted = results.first['formatted_address'] as String;
    return _normalizeKo(formatted);
  }

  static String normalizeKo(String s) => _normalizeKo(s);

  static String _normalizeKo(String s) {
    var out = s;

    // 한글 + 바로 뒤에 붙은 숫자까지 제거 (예: "산56 ")
    out = out.replaceAll(RegExp(r'[\uac00-\ud7af]+\d*\s*'), '');

    // 공백 정리
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();

    return out;
  }
}
