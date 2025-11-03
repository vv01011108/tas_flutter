/* features/navigation/domain/scenario_manager.dart */
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../alerts/domain/alert_engine.dart';
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

  Future<void> preload(DriveScenario s,
      Future<String?> Function(LatLng) krAddr) async {
    final csv = csvFor(s);
    final tr = await TraceRepo().loadFromCsv(csv);
    final start = await krAddr(tr.start);
    final end = await krAddr(tr.end);
    final slot = scenarios[s]!;
    slot.trace = tr;

    // String? norm(String? v) => v == null ? null : KrAddressService.normalizeKo(v); // 🗑️ 사용하지 않으므로 제거

    slot.startAddrKr = start ?? tr.startAddr;
    slot.endAddrKr = end ?? tr.endAddr;
    slot.loading = false;
  }
}