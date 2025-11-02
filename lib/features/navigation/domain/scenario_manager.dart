/* 분기/모델 로드 */
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../alerts/data/model_repo.dart';
import '../../alerts/domain/alert_engine.dart';
import '../../alerts/domain/alert_models.dart';
import '../../navigation/data/trace_repo.dart';
import '../../navigation/domain/trace_models.dart';
import '../../shared/config.dart';
import '../../shared/geo_addr.dart';

enum DriveScenario { rain, snow }

class ScenarioData {
  ScenarioData(this.scenario);
  final DriveScenario scenario;
  TraceData? trace;
  String? startAddrKr;
  String? endAddrKr;
  bool loading = false;
}

class ScenarioManager {
  final Map<DriveScenario, ScenarioData> scenarios = {
    DriveScenario.rain: ScenarioData(DriveScenario.rain)..loading = true,
    DriveScenario.snow: ScenarioData(DriveScenario.snow)..loading = true,
  };

  String csvFor(DriveScenario s) => s == DriveScenario.rain
      ? AppConfig.kTraceCsvRain!
      : AppConfig.kTraceCsvSnow!;

  String modelFor(DriveScenario s) => s == DriveScenario.rain
      ? AppConfig.kModelCsvRain
      : AppConfig.kModelCsvSnow;

  Future<void> preload(DriveScenario s,
      Future<String?> Function(LatLng) krAddr) async {
    final csv = csvFor(s);
    final tr = await TraceRepo().loadFromCsv(csv);
    final start = await krAddr(tr.start);
    final end = await krAddr(tr.end);
    final slot = scenarios[s]!;
    slot.trace = tr;

    String? norm(String? v) => v == null ? null : KrAddressService.normalizeKo(v);

    slot.startAddrKr = start ?? tr.startAddr;
    slot.endAddrKr = end ?? tr.endAddr;
    slot.loading = false;
  }

  Future<AlertEngine> loadEngine(DriveScenario s) async {
    final modelCsv = modelFor(s);
    final nodes = await ModelRepo().loadFromCsv(modelCsv);
    return AlertEngine(nodes);
  }
}
