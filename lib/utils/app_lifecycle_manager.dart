import 'package:flutter/widgets.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/ble_logger.dart';

/// Manages app lifecycle state for BLE operations
/// Prevents sync from being killed when app backgrounds or screen locks
class AppLifecycleManager extends WidgetsBindingObserver {
  static final AppLifecycleManager _instance = AppLifecycleManager._internal();
  factory AppLifecycleManager() => _instance;
  AppLifecycleManager._internal();

  AppLifecycleState _currentState = AppLifecycleState.resumed;
  bool _isPaused = false;
  
  // CRITICAL FIX: Callback to signal sync to stop when app lifecycle changes
  VoidCallback? _onSyncShouldStop;

  AppLifecycleState get currentState => _currentState;
  bool get isPaused => _isPaused;
  bool get isResumed => !_isPaused && _currentState == AppLifecycleState.resumed;
  
  /// Set callback to be called when sync should stop due to lifecycle changes
  void setSyncStopCallback(VoidCallback? callback) {
    _onSyncShouldStop = callback;
  }

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    BLELogger.info('App lifecycle manager initialized', 'AppLifecycleManager');
  }

  void dispose() {
    // CRITICAL FIX: Only dispose if sync is not in progress
    // This prevents lifecycle manager from being disposed during active BLE sync
    if (_onSyncShouldStop != null) {
      BLELogger.warning('App lifecycle manager dispose blocked - sync in progress', 'AppLifecycleManager');
      return; // Don't dispose if sync is active
    }
    
    WidgetsBinding.instance.removeObserver(this);
    BLELogger.info('App lifecycle manager disposed', 'AppLifecycleManager');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    final previousState = _currentState;
    _currentState = state;
    _isPaused = state != AppLifecycleState.resumed;

    BLELogger.info(
      'App lifecycle changed: $previousState -> $state',
      'AppLifecycleManager',
    );

    // Handle state transitions
    switch (state) {
      case AppLifecycleState.resumed:
        _handleResumed();
        break;
      case AppLifecycleState.paused:
        _handlePaused();
        break;
      case AppLifecycleState.inactive:
        _handleInactive();
        break;
      case AppLifecycleState.detached:
        _handleDetached();
        break;
      case AppLifecycleState.hidden:
        _handleHidden();
        break;
    }
  }

  void _handleResumed() {
    BLELogger.info('App resumed - BLE operations can continue', 'AppLifecycleManager');
  }

  void _handlePaused() {
    BLELogger.warning('App paused - BLE sync may be interrupted', 'AppLifecycleManager');
    // Note: We don't stop sync here because Android foreground service will keep it alive
    // But we log it for debugging
  }

  void _handleInactive() {
    BLELogger.debug('App inactive (transitioning)', 'AppLifecycleManager');
  }

  void _handleDetached() {
    BLELogger.warning('App detached - BLE sync will be interrupted', 'AppLifecycleManager');
    // PRODUCTION HARDENING: Signal sync to stop cleanly when app is detached
    // This prevents sync from continuing in background when app is killed
    // Use safe call operator to prevent null assertion exceptions
    if (_onSyncShouldStop != null) {
      BLELogger.info('Signaling sync to stop due to app detach', 'AppLifecycleManager');
      _onSyncShouldStop?.call(); // PRODUCTION HARDENING: Safe call instead of null assertion
    }
  }

  void _handleHidden() {
    BLELogger.debug('App hidden', 'AppLifecycleManager');
  }

  /// Check if BLE operations should continue
  /// Returns false if app is in a state that might interrupt BLE
  bool shouldContinueBLEOperations() {
    // Allow BLE to continue in resumed and paused states
    // Paused is OK because foreground service will keep it alive
    return _currentState == AppLifecycleState.resumed ||
           _currentState == AppLifecycleState.paused;
  }
}
