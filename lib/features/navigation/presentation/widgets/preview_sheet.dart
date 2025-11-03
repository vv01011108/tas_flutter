/* 경로 미리보기/안내 버튼 */
// features/navigation/presentation/widgets/preview_sheet.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../domain/trace_models.dart';
// 🗑️ import '../../../shared/geo.dart'; 삭제
import '../../../shared/geo.dart'; // boundsFrom 사용을 위해 geo.dart의 다른 import 경로 유지
import '../widgets/start_end_card.dart';

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
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _buildHandle(context),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      // 지도를 포함한 카드 (onTap 없음, 힌트 없음)
                      StartEndCard(
                        startAddr: '출발 지점',
                        start: LatLngLite(trace.start.latitude, trace.start.longitude),
                        endAddr: '도착 지점',
                        end: LatLngLite(trace.end.latitude, trace.end.longitude),
                        showTapHint: false,
                        onTap: null, // 미리보기에서는 탭 비활성화
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 250,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: GoogleMap(
                            initialCameraPosition: CameraPosition(target: trace.pts.first, zoom: 16),
                            onMapCreated: (controller) {
                              final bounds = boundsFrom(trace.pts);
                              controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
                            },
                            markers: {
                              Marker(
                                markerId: const MarkerId('start'),
                                position: trace.start,
                                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                              ),
                              Marker(
                                markerId: const MarkerId('end'),
                                position: trace.end,
                                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                              ),
                            },
                            polylines: {
                              Polyline(
                                polylineId: const PolylineId('route'),
                                points: trace.pts,
                                color: Colors.blueAccent,
                                width: 6,
                              )
                            },
                            zoomControlsEnabled: false,
                            scrollGesturesEnabled: false,
                            zoomGesturesEnabled: false,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: onStart,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('안내 시작'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHandle(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      width: double.infinity,
      alignment: Alignment.center,
      child: Container(
        width: 40,
        height: 5,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}