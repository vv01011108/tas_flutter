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
          '&language=ko'      // 한국어
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

  /// "대한민국" 제거 + 공백 정리
  static String _normalizeKo(String s) {
    var out = s;
    // 뒤 또는 앞의 '대한민국' 제거
    out = out.replaceAll(RegExp(r'^\s*대한민국\s*,?\s*'), '');
    out = out.replaceAll(RegExp(r'\s*,?\s*대한민국\s*$'), '');
    // 쉼표 뒤 공백 정리
    out = out.replaceAll(', ', ', ');
    return out.trim();
  }
}
