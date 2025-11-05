import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LatLngLite {
  final double latitude;
  final double longitude;
  const LatLngLite(this.latitude, this.longitude);
}

class StartEndCard extends StatelessWidget {
  final String startAddr;
  final LatLngLite start;
  final String endAddr;
  final LatLngLite end;

  /// ✅ 추가: 카드를 탭했을 때 실행할 콜백 (미리보기 열기 등)
  final VoidCallback? onTap;

  /// ✅ 추가(옵션): 하단에 "탭하여 미리보기"
  final bool showTapHint;

  const StartEndCard({
    super.key,
    required this.startAddr,
    required this.start,
    required this.endAddr,
    required this.end,
    this.onTap,
    this.showTapHint = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _addrBlock('출발', startAddr, start),
          const SizedBox(height: 8),
          const Divider(thickness: 1, color: Colors.black12),
          const SizedBox(height: 8),
          _addrBlock('도착', endAddr, end),

          if (showTapHint) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.map, size: 16, color: Colors.black54),
                SizedBox(width: 6),
                Text('탭하여 미리보기', style: TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ],
        ],
      ),
    );

    // ✅ onTap이 있으면 InkWell 랩핑해서 카드 전체가 탭을 받도록
    final body = onTap == null
        ? content
        : InkWell(onTap: onTap, child: content);

    return Card(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }

  Widget _addrBlock(String label, String addr, LatLngLite pos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(label == '출발' ? Icons.trip_origin : Icons.flag,
                size: 18, color: Colors.blueGrey),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(addr, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        const SizedBox(height: 4),
        Text(
          '위도 ${pos.latitude.toStringAsFixed(6)} | 경도 ${pos.longitude.toStringAsFixed(6)}',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}