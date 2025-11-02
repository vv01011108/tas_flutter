/* 상수 - 반경, 브리지 ms, 임계값 */
class AppConfig {
  // CSV 자원 경로
  static const String kTraceCsv = 'assets/rain_trace_test.csv';
  static const String? kTraceCsvRain = 'assets/rain_trace.csv';
  static const String? kTraceCsvSnow = 'assets/snow_trace.csv';
  static const String kModelCsvRain = 'assets/model_rain.csv';
  static const String kModelCsvSnow = 'assets/model_snow.csv';

  // 타이머 주기(5Hz)
  static const int tickMs = 200;

  // 속도 표시 0 스냅 임계
  static const double zeroSpeedEps = 0.5;

  // 큰 갭(기록 공백) 처리
  static const int gapMs = 60000;   // 1분 이상이면 갭으로 간주
  static const int bridgeMs = 4000; // 화면상 4초로 연결

  // 알림(권고/경고) 근접 파라미터
  static const double alertEnterM = 30.0;
  static const double alertExitM  = 45.0;
  static const int alertLingerMs  = 3000;
  static const int alertFlashMs   = 400;

  // 카메라(네비게이션) 기본
  static const double camZoom = 18.5;
  static const double camTilt = 50.0;

  static const String kGoogleApiKey = 'AIzaSyDgSThN1sHSyB4JZM9Z24qIFsslfFX5Qt4';
  static const String googleGeocodeKey = 'AIzaSyDUNpeJOEWaeuwk3J_OJ64F96MNweO2Nn0';
}
