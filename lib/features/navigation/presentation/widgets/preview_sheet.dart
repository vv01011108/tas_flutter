/* 경로 미리보기/안내 버튼 */
// features/navigation/presentation/widgets/preview_sheet.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../domain/trace_models.dart';
import '../../../shared/geo.dart'; // boundsFrom 사용을 위해 geo.dart의 다른 import 경로 유지
import '../widgets/start_end_card.dart';

typedef OnStartPressed = Future<void> Function();

class PreviewSheet extends StatelessWidget {

  final String title;
  final TraceData trace;
  final OnStartPressed onStart;

  // 주소 파라미터
  final String startAddr;
  final String endAddr;

  const PreviewSheet({
    super.key,
    required this.title,
    required this.trace,
    required this.onStart,
    required this.startAddr,
    required this.endAddr,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.75,
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
                        startAddr: startAddr,
                        start: LatLngLite(trace.start.latitude, trace.start.longitude),
                        endAddr: endAddr,
                        end: LatLngLite(trace.end.latitude, trace.end.longitude),
                        showTapHint: false,
                        onTap: null,
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
                      ElevatedButton(
                        onPressed: onStart,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2C2C2C),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          elevation: 2,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.directions_car_rounded, size: 22),
                            SizedBox(width: 8),
                            Text('Start Guidance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
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