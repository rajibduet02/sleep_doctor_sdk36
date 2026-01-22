import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Central debug logger that writes logs to a file
/// Works in both DEBUG and RELEASE builds
class DebugLogger {
  static DebugLogger? _instance;
  static Completer<void>? _initCompleter;
  
  File? _logFile;
  bool _initialized = false;
  final String _logFileName = 'sleepdoctor_debug.log';
  Completer<void>? _writeCompleter;
  
  DebugLogger._();
  
  /// Get singleton instance
  static DebugLogger get instance {
    _instance ??= DebugLogger._();
    return _instance!;
  }
  
  /// Initialize the logger - must be called before use
  static Future<void> init() async {
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
    
    _initCompleter = Completer<void>();
    
    try {
      if (instance._initialized) {
        _initCompleter!.complete();
        return;
      }
      
      final directory = await getApplicationDocumentsDirectory();
      final logFile = File('${directory.path}/${instance._logFileName}');
      
      // Create file if it doesn't exist
      if (!await logFile.exists()) {
        await logFile.create(recursive: true);
      }
      
      instance._logFile = logFile;
      instance._initialized = true;
      
      // Log initialization
      await instance._writeLog('I', 'DebugLogger initialized', null);
      
      _initCompleter!.complete();
    } catch (e) {
      // If initialization fails, logger will be safe (no crashes)
      instance._initialized = false;
      _initCompleter!.completeError(e);
      _initCompleter = null;
    }
  }
  
  /// Write log entry to file (thread-safe using queue)
  Future<void> _writeLog(String level, String message, [String? tag]) async {
    if (!_initialized || _logFile == null) {
      return; // Safe if not initialized
    }
    
    try {
      final timestamp = DateTime.now().toIso8601String();
      final tagStr = tag != null ? '[$tag]' : '';
      final logLine = '$timestamp [$level] $tagStr $message\n';
      
      // Queue writes to prevent interleaving
      final currentWrite = _writeCompleter;
      _writeCompleter = Completer<void>();
      
      if (currentWrite != null) {
        await currentWrite.future;
      }
      
      await _logFile!.writeAsString(logLine, mode: FileMode.append);
      _writeCompleter!.complete();
    } catch (e) {
      // Silently fail - don't crash app if logging fails
      _writeCompleter?.complete();
    }
  }
  
  /// Verbose log
  void v(String message, [String? tag]) {
    _writeLog('V', message, tag);
  }
  
  /// Debug log
  void d(String message, [String? tag]) {
    _writeLog('D', message, tag);
  }
  
  /// Info log
  void i(String message, [String? tag]) {
    _writeLog('I', message, tag);
  }
  
  /// Warning log
  void w(String message, [String? tag]) {
    _writeLog('W', message, tag);
  }
  
  /// Error log
  void e(String message, [Object? error, String? tag]) {
    final errorStr = error != null ? ' | Error: $error' : '';
    final stackTrace = error is Error ? ' | StackTrace: ${error.stackTrace}' : '';
    _writeLog('E', '$message$errorStr$stackTrace', tag);
  }
  
  /// Get log file path
  Future<String?> getLogFilePath() async {
    if (!_initialized || _logFile == null) {
      return null;
    }
    return _logFile!.path;
  }
  
  /// Check if logger is initialized
  bool get isInitialized => _initialized;
}
