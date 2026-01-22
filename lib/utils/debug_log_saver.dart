import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iptasys_sleep_doctor_flutter/core/debug/debug_logger.dart';

/// Save debug logs to Downloads/SleepDoctor/ using MediaStore
/// Saves to: Internal storage/Download/SleepDoctor/sleepdoctor_debug.txt
Future<String?> saveDebugLogs(BuildContext context) async {
  try {
    if (!context.mounted) {
      return null;
    }
    
    final sourceFilePath = await DebugLogger.instance.getLogFilePath();
    
    if (sourceFilePath == null) {
      return null;
    }
    
    const platform = MethodChannel('de.iptasys.sleepdoctor/debug_log_saver');
    
    final result = await platform.invokeMethod<String>('saveDebugLogs', {
      'sourcePath': sourceFilePath,
    });
    
    return result;
  } catch (e) {
    return null;
  }
}
