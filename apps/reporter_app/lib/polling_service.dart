import 'dart:async';
import 'package:dio/dio.dart';
import 'state.dart';
import 'storage.dart';

class PollingService {
  Timer? _timer;
  final Dio _dio;
  final String relayBaseUrl;
  final void Function(ReporterState) onApproved;

  PollingService({
    required this.relayBaseUrl,
    required this.onApproved,
  }) : _dio = Dio(BaseOptions(baseUrl: relayBaseUrl));

  void start() {
    stop();
    _timer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _poll(),
    );
    _poll(); // immediate first poll
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    try {
      final androidId = await ReporterStorage.getAndroidId();
      if (androidId == null) return;

      final resp = await _dio.get(
        '/api/device/status',
        queryParameters: {'androidId': androidId},
      );

      final data = resp.data as Map<String, dynamic>;
      final status = data['status'] as String?;

      if (status == 'approved') {
        final token = data['ingestToken'] as String?;
        final url = data['ingestUrl'] as String?;
        if (token != null && url != null) {
          final newState = ReporterState(
            approval: ApprovalStatus.approved,
            mode: TrackingMode.idle,
            ingestToken: token,
            ingestUrl: url,
          );
          await ReporterStorage.save(newState);
          stop();
          onApproved(newState);
        }
      } else if (status == 'removed') {
        final newState = const ReporterState(approval: ApprovalStatus.removed);
        await ReporterStorage.save(newState);
        stop();
      }
    } catch (_) {
      // Retry on next poll cycle
    }
  }
}
