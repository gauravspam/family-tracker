import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class PermissionResult {
  final bool allGranted;
  final String? missing;

  const PermissionResult({required this.allGranted, this.missing});
}

class Permissions {
  static Future<PermissionResult> requestAll() async {
    // Step 1: Notification (Android 13+)
    final notif = await Permission.notification.request();
    if (!notif.isGranted) {
      return const PermissionResult(
        allGranted: false,
        missing: 'Notification permission required',
      );
    }

    // Step 2: Fine location
    final fine = await Permission.locationWhenInUse.request();
    if (!fine.isGranted) {
      return const PermissionResult(
        allGranted: false,
        missing: 'Location permission required',
      );
    }

    // Check precision level
    final accuracy = await Geolocator.getLocationAccuracy();
    if (accuracy != LocationAccuracyStatus.precise) {
      return const PermissionResult(
        allGranted: false,
        missing: 'Precise location required. Please enable in Settings.',
      );
    }

    // Step 3: Background location
    final bg = await Permission.locationAlways.request();
    if (!bg.isGranted) {
      return const PermissionResult(
        allGranted: false,
        missing: 'Background location required. Please enable in Settings.',
      );
    }

    // Step 4: Battery optimization
    final battery = await Permission.ignoreBatteryOptimizations.request();
    if (!battery.isGranted) {
      return const PermissionResult(
        allGranted: false,
        missing: 'Battery optimization exemption required',
      );
    }

    return const PermissionResult(allGranted: true);
  }

  static Future<bool> checkAll() async {
    final fine = await Permission.locationWhenInUse.isGranted;
    final bg = await Permission.locationAlways.isGranted;
    final notif = await Permission.notification.isGranted;
    final accuracy = await Geolocator.getLocationAccuracy();

    return fine && bg && notif && accuracy == LocationAccuracyStatus.precise;
  }
}
