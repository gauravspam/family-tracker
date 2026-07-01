import 'package:tracker_core/models/command.dart';
import 'state.dart';
import 'storage.dart';

class FCMHandler {
  final Future<void> Function() onReconcile;

  FCMHandler({required this.onReconcile});

  Future<void> handleMessage(Map<String, dynamic> data) async {
    try {
      final command = ReporterCommand.fromJson(data);

      switch (command) {
        case ApprovedCommand(:final ingestToken, :final ingestUrl):
          final state = ReporterState(
            approval: ApprovalStatus.approved,
            mode: TrackingMode.idle,
            ingestToken: ingestToken,
            ingestUrl: ingestUrl,
          );
          await ReporterStorage.save(state);

        case LiveModeCommand(:final expiresAt):
          final current = await ReporterStorage.load();
          final state = current.copyWith(
            mode: TrackingMode.live,
            liveExpiresAt: DateTime.parse(expiresAt),
          );
          await ReporterStorage.save(state);

        case IdleModeCommand():
          final current = await ReporterStorage.load();
          final state = current.copyWith(
            mode: TrackingMode.idle,
            clearExpiry: true,
          );
          await ReporterStorage.save(state);

        case RemovedCommand():
          const state = ReporterState(approval: ApprovalStatus.removed);
          await ReporterStorage.save(state);
      }

      await onReconcile();
    } catch (_) {
      // Malformed command — ignore
    }
  }
}
