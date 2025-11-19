/* 시나리오 리스트 카드 */
// features/navigation/presentation/widgets/scenario_list.dart
import 'package:flutter/material.dart';
import '../../domain/trace_models.dart';
import '../widgets/start_end_card.dart'; // LatLngLite 포함


class ScenarioListCard extends StatelessWidget {
  const ScenarioListCard({
    super.key,
    required this.title,
    required this.startAddr,
    required this.endAddr,
    required this.trace,
    required this.onTap,
    this.loading = false,
  });

  final String title;
  final String? startAddr;
  final String? endAddr;
  final TraceData? trace;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: loading || trace == null ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: loading ? const _Loading() : _Body(
            startAddr: startAddr ?? 'Address lookup failed',
            endAddr: endAddr ?? 'Address lookup failed',
            trace: trace!,
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(height: 4),
      LinearProgressIndicator(minHeight: 6),
      SizedBox(height: 6),
      Text('Loading route...', style: TextStyle(fontSize: 12, color: Colors.black54)),
    ],
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.startAddr, required this.endAddr, required this.trace});
  final String startAddr;
  final String endAddr;
  final TraceData trace;

  @override
  Widget build(BuildContext context) {
    return StartEndCard(
      startAddr: startAddr,
      start: LatLngLite(trace.start.latitude, trace.start.longitude),
      endAddr: endAddr,
      end: LatLngLite(trace.end.latitude, trace.end.longitude),
    );
  }
}