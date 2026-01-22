import 'package:flutter/services.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/ble_logger.dart';

/// Controls Android foreground service for BLE sync
/// Ensures sync continues when app backgrounds on Android 12+
class ForegroundServiceController {
  static const MethodChannel _channel = MethodChannel('de.iptasys.sleepdoctor/ble_sync_service');
  
  /// Start foreground service to keep BLE sync alive
  /// This is REQUIRED for reliable sync on Android 12+ when app backgrounds
  static Future<bool> startService() async {
    try {
      final result = await _channel.invokeMethod<bool>('startForegroundService');
      if (result == true) {
        BLELogger.info('Foreground service started successfully', 'ForegroundServiceController');
        return true;
      } else {
        BLELogger.warning('Foreground service start returned false', 'ForegroundServiceController');
        return false;
      }
    } on PlatformException catch (e) {
      BLELogger.error('Failed to start foreground service', e, 'ForegroundServiceController');
      // Don't fail sync if service start fails - log and continue
      // This allows sync to work on older Android versions or if service fails
      return false;
    } catch (e) {
      BLELogger.error('Unexpected error starting foreground service', e, 'ForegroundServiceController');
      return false;
    }
  }
  
  /// Stop foreground service when sync completes
  static Future<bool> stopService() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopForegroundService');
      if (result == true) {
        BLELogger.info('Foreground service stopped successfully', 'ForegroundServiceController');
        return true;
      } else {
        BLELogger.warning('Foreground service stop returned false', 'ForegroundServiceController');
        return false;
      }
    } on PlatformException catch (e) {
      BLELogger.error('Failed to stop foreground service', e, 'ForegroundServiceController');
      // Best effort - service will stop when app terminates
      return false;
    } catch (e) {
      BLELogger.error('Unexpected error stopping foreground service', e, 'ForegroundServiceController');
      return false;
    }
  }
  
  /// Check if service is currently running
  static Future<bool> isServiceRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isServiceRunning');
      return result ?? false;
    } catch (e) {
      BLELogger.debug('Failed to check service status', 'ForegroundServiceController');
      return false;
    }
  }
}
