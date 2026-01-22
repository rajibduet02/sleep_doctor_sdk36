import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/ble_config.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/ble_logger.dart';
import 'package:permission_handler/permission_handler.dart';

/// Handles battery optimization settings for Android
/// Prevents system from killing BLE sync operations
class BatteryOptimizationHandler {
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) {
      return true; // Not applicable on iOS
    }

    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (e) {
      BLELogger.error('Error checking battery optimization status', e, 'BatteryOptimizationHandler');
      return false;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) {
      return true; // Not applicable on iOS
    }

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt < 23) {
        // Battery optimization API only available on Android 6.0+
        return true;
      }

      final status = await Permission.ignoreBatteryOptimizations.request();
      final granted = status.isGranted;
      
      if (granted) {
        BLELogger.info('Battery optimization exemption granted', 'BatteryOptimizationHandler');
      } else {
        BLELogger.warning('Battery optimization exemption denied - sync may be interrupted', 'BatteryOptimizationHandler');
      }
      
      return granted;
    } catch (e) {
      BLELogger.error('Error requesting battery optimization exemption', e, 'BatteryOptimizationHandler');
      return false;
    }
  }

  /// Check and request battery optimization exemption if needed
  /// Should be called before starting a long BLE sync
  static Future<bool> ensureBatteryOptimizationExempt() async {
    if (await isIgnoringBatteryOptimizations()) {
      return true;
    }

    BLELogger.info('Requesting battery optimization exemption for stable BLE sync', 'BatteryOptimizationHandler');
    return await requestIgnoreBatteryOptimizations();
  }
}
