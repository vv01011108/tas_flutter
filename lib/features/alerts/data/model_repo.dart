/* model.csv 로더 */
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../domain/alert_models.dart';

class ModelRepo {
  Future<List<AlertNode>> loadFromCsv(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final lines = raw.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    int startIdx = 0;
    if (lines.isNotEmpty) {
      final lower = lines.first.toLowerCase();
      if (lower.contains('rec_kmh') && lower.contains('lat')) startIdx = 1;
    }
    final out = <AlertNode>[];
    for (int i = startIdx; i < lines.length; i++) {
      final cols = lines[i].split(RegExp(r'[,\t;]')).map((s) => s.trim()).toList();
      if (cols.length < 4) continue;
      final rec  = double.tryParse(cols[0]);
      final lat  = double.tryParse(cols[1]);
      final lon  = double.tryParse(cols[2]);
      final surf = int.tryParse(cols[3]);
      if (rec == null || lat == null || lon == null || surf == null) continue;
      final s = switch (surf) { 2 => RoadSurface.icy, 1 => RoadSurface.wet, _ => RoadSurface.dry };
      out.add(AlertNode(LatLng(lat, lon), rec, s));
    }
    return out;
  }
}


