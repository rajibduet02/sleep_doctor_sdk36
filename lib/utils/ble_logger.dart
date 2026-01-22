import 'package:iptasys_sleep_doctor_flutter/core/debug/debug_logger.dart';

/// Structured logging utility for BLE operations
/// Replaces print() statements with proper logging levels
/// Also writes to DebugLogger for file-based logging
class BLELogger {
  static const String _tag = '[BLE]';
  
  static void info(String message, [String? context]) {
    final contextStr = context != null ? '[$context]' : '';
    print('$_tag INFO $contextStr $message');
    DebugLogger.instance.i('BLE_INFO: $message', context);
  }
  
  static void warning(String message, [String? context]) {
    final contextStr = context != null ? '[$context]' : '';
    print('$_tag WARNING $contextStr $message');
    DebugLogger.instance.w('BLE_WARNING: $message', context);
  }
  
  static void error(String message, [Object? error, String? context]) {
    final contextStr = context != null ? '[$context]' : '';
    final errorStr = error != null ? ' | Error: $error' : '';
    print('$_tag ERROR $contextStr $message$errorStr');
    DebugLogger.instance.e('BLE_ERROR: $message', error, context);
  }
  
  static void debug(String message, [String? context]) {
    // Only log in debug mode
    assert(() {
      final contextStr = context != null ? '[$context]' : '';
      print('$_tag DEBUG $contextStr $message');
      DebugLogger.instance.d('BLE_DEBUG: $message', context);
      return true;
    }());
  }
}
