import 'state.dart';
import 'storage.dart';
import 'permissions.dart';
import 'location_service.dart';
import 'polling_service.dart';

class Reconciler {
  final LocationService locationService;
  final PollingService pollingService;
  final void Function(String) onNotificationUpdate;

  Reconciler({
    required this.locationService,
    required this.pollingService,
    required this.onNotificationUpdate,
  });

  Future<void> reconcile() async {
    final hasPerms = await Permissions.checkAll();
    if (!hasPerms) {
      locationService.stop();
      pollingService.stop();
      onNotificationUpdate('Precise location required');
      return;
    }

    final state = await ReporterStorage.load();

    switch (state.approval) {
      case ApprovalStatus.removed:
        locationService.stop();
        pollingService.stop();
        onNotificationUpdate('Service stopped');
        return;

      case ApprovalStatus.pending:
        locationService.stop();
        pollingService.start();
        onNotificationUpdate('Waiting for setup...');
        return;

      case ApprovalStatus.approved:
        pollingService.stop();
        locationService.start(state);
        onNotificationUpdate('Location service active');
        return;
    }
  }
}
