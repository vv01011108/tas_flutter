/* 경로 미리보기/안내 버튼 */
// features/navigation/presentation/widgets/preview_sheet.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../domain/trace_models.dart';
import '../../../shared/geo.dart';

typedef OnStartPressed = Future<void> Function();

class PreviewSheet extends StatelessWidget {
  const PreviewSheet({
    super.key,
    required this.title,
    required this.trace,
    required this.onStart,
  });
  final String title;
  final TraceData trace;
  final OnStartPressed onStart;

  @override
  Widget build(BuildContext context) {
    final tr = trace;
    final poly = Polyline(
      polylineId: const PolylineId('csv'),
      points: tr.pts,
      width: 5,
      color: Colors.blueAccent,
    );
    final markers = <Marker>{
      Marker(markerId: const MarkerId('s'),
          position: tr.start,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
      Marker(markerId: const MarkerId('e'),
          position: tr.end,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
    };

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.45,
      maxChildSize: 0.9,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.black26,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                Text(title, style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GoogleMap(
                      initialCameraPosition:
                      CameraPosition(target: tr.start, zoom: 15),
                      markers: markers,
                      polylines: {poly},
                      compassEnabled: false,
                      rotateGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      zoomControlsEnabled: false,
                      onMapCreated: (c) async {
                        try {
                          await Future.delayed(const Duration(milliseconds: 250));
                          await c.animateCamera(
                            CameraUpdate.newLatLngBounds(boundsFrom(tr.pts), 48),
                          );
                        } catch (_) {}
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          // 이미 미리보기 상태라 별도 동작 불필요. 필요시 상세정보 토글 등 배치.
                          Navigator.of(context).maybePop();
                        },
                        label: const Text('닫기'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onStart,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('안내 시작'),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }
}
