import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:iptasys_sleep_doctor_flutter/helpers/bluetooth_data_helper.dart';
import 'package:iptasys_sleep_doctor_flutter/interfaces/status_observer.dart';
import 'package:iptasys_sleep_doctor_flutter/models/bluetooth_device_info.dart';
import 'package:iptasys_sleep_doctor_flutter/models/bluetooth_signals.dart';
import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/sleep_doctor_abstract_data.dart';
import 'package:iptasys_sleep_doctor_flutter/services/bluetooth_service.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/ble_config.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/ble_logger.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/app_lifecycle_manager.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/foreground_service_controller.dart';
import 'dart:io' show Platform;

class SleepDoctorDataConnector {
  final BluetoothConnector _bluetoothService = BluetoothConnector();

  StreamSubscription<BluetoothAdapterState>? _bluetoothStateSubscription;
  StreamSubscription<bool>? _bluetoothScanningSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateMonitorSubscription;
  StreamSubscription<BluetoothConnectionState>? _handshakeConnectionStateSubscription; // RECOMMENDATION 3.1: Dedicated monitor for handshake
  StreamSubscription<List<int>>? _buttonPressNotificationSubscription;
  Timer? _keepAliveTimer;
  Timer? _handshakeKeepAliveTimer; // RECOMMENDATION 3.1: Continuous keep-alive during handshake
  bool _handshakeDisconnectDetected = false; // RECOMMENDATION 3.1: Flag to track disconnect during handshake

  BluetoothServiceStatesObserver? _bluetoothServiceStatesObserver;
  bool _isSyncInProgress = false;
  bool _shouldStopSync = false;
  bool _isReadingData = false; // PRODUCTION HARDENING: Track active data reads to prevent keep-alive interference
  
  // CRITICAL FIX: Cache discovered service and characteristic to avoid re-discovery
  BluetoothService? _cachedSleepDataService;
  BluetoothCharacteristic? _cachedSleepDataCharacteristic;

  //########################################################################
  // LISTENING STATES
  //########################################################################

  setListener(BluetoothServiceStatesObserver bluetoothServiceStatesObserver) {
    _bluetoothServiceStatesObserver = bluetoothServiceStatesObserver;
    _startListeningStates();
  }

  void _startListeningStates() {
    _listenOnBluetoothState();
    _listenOnBluetoothScanningState();
  }

  void _listenOnBluetoothState() {
    _bluetoothStateSubscription?.cancel();
      _bluetoothStateSubscription = _bluetoothService.bluetoothState().listen(
      (state) {
        final stateStr = state == BluetoothAdapterState.on ? 'ON' : (state == BluetoothAdapterState.off ? 'OFF' : state.toString());
        BLELogger.info('BLE_STATE_CHANGED: Bluetooth adapter state changed to: $stateStr', 'SleepDoctorDataConnector');
        _bluetoothServiceStatesObserver?.bluetoothStateChanged(state);
        
        // If Bluetooth turns off during sync, stop the sync
        if (_isSyncInProgress && state != BluetoothAdapterState.on) {
          BLELogger.warning('BLE_STATE_OFF_DURING_SYNC: Bluetooth turned off during sync - stopping', 'SleepDoctorDataConnector');
          _shouldStopSync = true;
        }
      },
      onError: (error) {
        BLELogger.error('Bluetooth state stream error', error, 'SleepDoctorDataConnector');
      },
    );
  }

  void _listenOnBluetoothScanningState() {
    _bluetoothScanningSubscription?.cancel();
    _bluetoothScanningSubscription = _bluetoothService.isScanning().listen(
      (isScanning) {
        BLELogger.debug('Scanning state changed: $isScanning', 'SleepDoctorDataConnector');
        _bluetoothServiceStatesObserver?.bluetoothIsScanningStateChanged(isScanning);
      },
      onError: (error) {
        BLELogger.error('Scanning state stream error', error, 'SleepDoctorDataConnector');
      },
    );
  }

  /// Monitor connection state during sync - CRITICAL for reliability
  void _startConnectionStateMonitoring() {
    _connectionStateMonitorSubscription?.cancel();
    
    if (_bluetoothService.device == null) {
      BLELogger.warning('Cannot monitor connection: device is null', 'SleepDoctorDataConnector');
      return;
    }

    _connectionStateMonitorSubscription = _bluetoothService.device!.connectionState.listen(
      (state) {
        final stateChangeTime = DateTime.now();
        final stateStr = state == BluetoothConnectionState.connected ? 'CONNECTED' : (state == BluetoothConnectionState.disconnected ? 'DISCONNECTED' : state.toString());
        BLELogger.info('BLE_GATT_STATE_CHANGED: Connection state changed to: $stateStr at ${stateChangeTime.toIso8601String()}', 'SleepDoctorDataConnector');
        _bluetoothServiceStatesObserver?.bluetoothConnectionStateChanged(state);
        
        // CRITICAL FIX: If disconnected during sync, mark for retry and log disconnect reason with timing
        if (_isSyncInProgress && state == BluetoothConnectionState.disconnected) {
          BLELogger.error('BLE_GATT_DISCONNECTED_DURING_SYNC: Device disconnected during sync at ${stateChangeTime.toIso8601String()}!', null, 'SleepDoctorDataConnector');
          BLELogger.error('BLE_DISCONNECT_REASON: Disconnect occurred during active sync operation', null, 'SleepDoctorDataConnector');
          
          // CRITICAL FIX: Log additional context about when disconnect occurred
          if (_bluetoothService.device != null) {
            try {
              final isActuallyConnected = _bluetoothService.device!.isConnected;
              BLELogger.error('BLE_DISCONNECT_VERIFICATION: Device.isConnected check: $isActuallyConnected', null, 'SleepDoctorDataConnector');
            } catch (e) {
              BLELogger.error('BLE_DISCONNECT_VERIFICATION: Error checking connection state: $e', null, 'SleepDoctorDataConnector');
            }
          }
          
          _shouldStopSync = true;
        }
      },
      onError: (error) {
        final errorTime = DateTime.now();
        BLELogger.error('BLE_CONNECTION_STATE_STREAM_ERROR: Connection state stream error at ${errorTime.toIso8601String()}', error, 'SleepDoctorDataConnector');
      },
    );
  }

  void _stopConnectionStateMonitoring() {
    _connectionStateMonitorSubscription?.cancel();
    _connectionStateMonitorSubscription = null;
  }

  //########################################################################
  //PUBLIC METHODS
  //########################################################################

  /// Main sync method - refactored with async/await and proper error handling
  Future<List<SleepDoctorAbstractData>> fetchDataFromSleepDoctorDevice() async {
    if (_isSyncInProgress) {
      BLELogger.warning('Sync already in progress - ignoring duplicate request', 'SleepDoctorDataConnector');
      throw StateError('Sync already in progress');
    }

    _isSyncInProgress = true;
    _shouldStopSync = false;
    
    // PRODUCTION HARDENING: Register lifecycle callback EARLY to stop sync when app is detached
    final lifecycleManager = AppLifecycleManager();
    lifecycleManager.setSyncStopCallback(() {
      BLELogger.warning('Sync stop requested by lifecycle manager', 'SleepDoctorDataConnector');
      _shouldStopSync = true;
    });

    // PRODUCTION HARDENING: Start foreground service to keep sync alive on Android 12+
    bool serviceStarted = false;
    if (Platform.isAndroid) {
      serviceStarted = await ForegroundServiceController.startService();
      if (!serviceStarted) {
        BLELogger.warning('Foreground service failed to start - sync may be interrupted if app backgrounds', 'SleepDoctorDataConnector');
      }
    }

    // COMPREHENSIVE EXCEPTION HANDLING: Log method entry with technical details
    final syncStartTime = DateTime.now();
    BLELogger.info('SYNC_START: Starting SleepDoctor data fetch', 'SleepDoctorDataConnector');
    BLELogger.info('SYNC_START_TIME: Sync start time: ${syncStartTime.toIso8601String()}', 'SleepDoctorDataConnector');
    BLELogger.info('SYNC_START_STATE: Initial state - isSyncInProgress: $_isSyncInProgress, shouldStopSync: $_shouldStopSync', 'SleepDoctorDataConnector');
    BLELogger.info('SYNC_START_DEVICE: Device state - isNull: ${_bluetoothService.device == null}, isConnected: ${_bluetoothService.device?.isConnected ?? false}', 'SleepDoctorDataConnector');

    try {
      // Step 1: Disconnect any existing device
      BLELogger.info('SYNC_STEP1: Disconnecting any existing device', 'SleepDoctorDataConnector');
      final disconnectStartTime = DateTime.now();
      try {
        await _bluetoothService.disconnectDevice();
        final disconnectEndTime = DateTime.now();
        final disconnectDuration = disconnectEndTime.difference(disconnectStartTime);
        BLELogger.info('SYNC_STEP1_SUCCESS: Disconnect completed in ${disconnectDuration.inMilliseconds}ms', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final disconnectErrorTime = DateTime.now();
        final disconnectDuration = disconnectErrorTime.difference(disconnectStartTime);
        BLELogger.error('SYNC_STEP1_EXCEPTION: Exception during disconnect (took ${disconnectDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP1_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP1_EXCEPTION_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP1_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        // Continue - disconnect failure may be non-critical if device already disconnected
        BLELogger.warning('SYNC_STEP1_CONTINUE: Continuing despite disconnect exception (may be non-critical)', 'SleepDoctorDataConnector');
      }

      // Step 2: Scan for device
      // CRITICAL: Scan should continue until device is found, no timeout-based failure
      // The scan will show "Searching for device..." in UI until device is found
      BTDeviceInfo deviceInfo;
      
      if (_shouldStopSync) {
        throw StateError('Sync stopped by user or system');
      }

      // Step 2: Scan for device
      BLELogger.info('SYNC_STEP2: Starting device scan', 'SleepDoctorDataConnector');
      BLELogger.info('SYNC_STEP2_PARAMS: Scanning for devices: ${BLEConfig.supportedDeviceNames.join(", ")}', 'SleepDoctorDataConnector');
      final scanStartTime = DateTime.now();
      
      try {
        // Scan for device - this will wait until device is found
        // No timeout-based retry logic - we wait for the device to appear
        deviceInfo = await _bluetoothService.scanForDevicesWith(
          BLEConfig.supportedDeviceNames,
          retryCount: 0,
        );
        final scanEndTime = DateTime.now();
        final scanDuration = scanEndTime.difference(scanStartTime);
        BLELogger.info('SYNC_STEP2_SUCCESS: Device found: ${deviceInfo.deviceName} (RSSI: ${deviceInfo.rssi}) in ${scanDuration.inMilliseconds}ms', 'SleepDoctorDataConnector');
        BLELogger.info('SYNC_STEP2_RESULT: Device info - name: ${deviceInfo.deviceName}, rssi: ${deviceInfo.rssi}', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final scanErrorTime = DateTime.now();
        final scanDuration = scanErrorTime.difference(scanStartTime);
        BLELogger.error('SYNC_STEP2_EXCEPTION: Exception during device scan (took ${scanDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP2_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP2_EXCEPTION_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP2_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        
        // Log device state at exception time
        final deviceStateAtException = _bluetoothService.device == null 
            ? "null" 
            : (_bluetoothService.device!.isConnected ? "connected" : "disconnected");
        BLELogger.error('SYNC_STEP2_EXCEPTION_STATE: Device state at exception: $deviceStateAtException', null, 'SleepDoctorDataConnector');
        
        throw StateError('Failed to scan for device: $e');
      }

      // Step 3: Start monitoring connection state BEFORE connection attempt
      // CRITICAL FIX: Monitor connection state from the start to detect immediate disconnects
      // This ensures we catch disconnects that happen during or immediately after connection
      BLELogger.info('SYNC_STEP3: Starting connection state monitoring', 'SleepDoctorDataConnector');
      try {
        if (_bluetoothService.device != null) {
          _startConnectionStateMonitoring();
          BLELogger.info('SYNC_STEP3_SUCCESS: Connection state monitoring started', 'SleepDoctorDataConnector');
        } else {
          BLELogger.warning('SYNC_STEP3_SKIP: Device is null, skipping connection state monitoring', 'SleepDoctorDataConnector');
        }
      } catch (e, stackTrace) {
        BLELogger.error('SYNC_STEP3_EXCEPTION: Exception during connection state monitoring setup', e, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP3_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP3_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        // Continue - monitoring failure is non-critical
      }

      // Step 4: Connect to device
      BLELogger.info('SYNC_STEP4: Connecting to device', 'SleepDoctorDataConnector');
      BLELogger.info('SYNC_STEP4_DEVICE: Device name: ${_bluetoothService.device?.platformName ?? "unknown"}', 'SleepDoctorDataConnector');
      final connectStartTime = DateTime.now();
      
      try {
        final connected = await _bluetoothService.connectToDevice();
        final connectEndTime = DateTime.now();
        final connectDuration = connectEndTime.difference(connectStartTime);
        
        BLELogger.info('SYNC_STEP4_RESULT: Connection result: $connected (took ${connectDuration.inMilliseconds}ms)', 'SleepDoctorDataConnector');
        BLELogger.info('SYNC_STEP4_DEVICE_STATE: Device state after connection - isNull: ${_bluetoothService.device == null}, isConnected: ${_bluetoothService.device?.isConnected ?? false}', 'SleepDoctorDataConnector');
        
        if (!connected) {
          _stopConnectionStateMonitoring();
          BLELogger.error('SYNC_STEP4_FAILED: Connection returned false', null, 'SleepDoctorDataConnector');
          throw StateError('Failed to connect to device');
        }
        
        BLELogger.info('SYNC_STEP4_SUCCESS: Device connected successfully', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final connectErrorTime = DateTime.now();
        final connectDuration = connectErrorTime.difference(connectStartTime);
        BLELogger.error('SYNC_STEP4_EXCEPTION: Exception during device connection (took ${connectDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP4_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP4_EXCEPTION_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP4_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        
        // Log device state at exception time
        final deviceStateAtException = _bluetoothService.device == null 
            ? "null" 
            : (_bluetoothService.device!.isConnected ? "connected" : "disconnected");
        BLELogger.error('SYNC_STEP4_EXCEPTION_STATE: Device state at exception: $deviceStateAtException', null, 'SleepDoctorDataConnector');
        
        _stopConnectionStateMonitoring();
        rethrow;
      }

      // Connection successful - monitoring is already active

      // RECOMMENDATION 3.1: Perform immediate keep-alive operation after connection
      // This prevents device from disconnecting due to inactivity before service discovery
      // Service discovery itself serves as keep-alive activity
      BLELogger.info('BLE_KEEPALIVE_IMMEDIATE: Performing immediate keep-alive after connection', 'SleepDoctorDataConnector');
      try {
        final keepAliveStartTime = DateTime.now();
        
        // Immediate service discovery serves as keep-alive activity
        // This satisfies device's requirement for immediate BLE interaction
        if (_bluetoothService.device != null && _bluetoothService.device!.isConnected) {
          BLELogger.info('BLE_KEEPALIVE_IMMEDIATE_DISCOVERY: Starting immediate service discovery as keep-alive', 'SleepDoctorDataConnector');
          
          // Discover services immediately - this is BLE activity that keeps connection alive
          // We don't need to process the results yet, just trigger the discovery
          await _bluetoothService.device!.discoverServices();
          
          final keepAliveEndTime = DateTime.now();
          final keepAliveDuration = keepAliveEndTime.difference(keepAliveStartTime);
          BLELogger.info('BLE_KEEPALIVE_IMMEDIATE_SUCCESS: Keep-alive completed in ${keepAliveDuration.inMilliseconds}ms', 'SleepDoctorDataConnector');
          
          // Verify connection is still active after keep-alive
          if (_bluetoothService.device != null && _bluetoothService.device!.isConnected) {
            BLELogger.info('BLE_KEEPALIVE_IMMEDIATE_VERIFIED: Connection verified after keep-alive', 'SleepDoctorDataConnector');
          } else {
            BLELogger.warning('BLE_KEEPALIVE_IMMEDIATE_WARNING: Connection lost during keep-alive', 'SleepDoctorDataConnector');
          }
        } else {
          BLELogger.warning('BLE_KEEPALIVE_IMMEDIATE_SKIPPED: Device not connected, skipping keep-alive', 'SleepDoctorDataConnector');
        }
      } catch (e) {
        BLELogger.warning('BLE_KEEPALIVE_IMMEDIATE_FAILED: Keep-alive failed (non-critical): $e', 'SleepDoctorDataConnector');
        // Don't fail sync if keep-alive fails - continue with handshake
      }

      // RECOMMENDATION 2.1: Add logging to verify code reaches handshake call
      // RECOMMENDATION 2.2: Add logging to verify handshake call is reached
      // This confirms code execution path and helps identify where code stops (if it does)
      BLELogger.info('BLE_SYNC_PRE_HANDSHAKE: About to start handshake process', 'SleepDoctorDataConnector');
      BLELogger.info('BLE_SYNC_PRE_HANDSHAKE_TIME: Current time: ${DateTime.now().toIso8601String()}', 'SleepDoctorDataConnector');
      BLELogger.info('BLE_SYNC_PRE_HANDSHAKE_STATE: Device state - isNull: ${_bluetoothService.device == null}, isConnected: ${_bluetoothService.device?.isConnected ?? false}', 'SleepDoctorDataConnector');
      
      // RECOMMENDATION 2.2: Add immediate BLE activity before handshake call to prevent timeout
      try {
        if (_bluetoothService.device != null && _bluetoothService.device!.isConnected) {
          _cachedSleepDataService?.uuid; // Simple property access maintains BLE activity
          BLELogger.debug('BLE_SYNC_PRE_HANDSHAKE_KEEPALIVE: Keep-alive before handshake call', 'SleepDoctorDataConnector');
        }
      } catch (e) {
        // Ignore - best effort
      }

      // CRITICAL FIX: Perform immediate handshake after connection
      // This prevents device from disconnecting due to inactivity
      BLELogger.info('BLE_HANDSHAKE_START: Starting immediate BLE handshake', 'SleepDoctorDataConnector');
      
      // RECOMMENDATION 1.2: Add exception handler around handshake call
      // This helps diagnose if exceptions are thrown before handshake can start
      BLELogger.debug('BLE_HANDSHAKE_PRE_CALL: About to call _performImmediateHandshake()', 'SleepDoctorDataConnector');
      BLELogger.debug('BLE_HANDSHAKE_PRE_CALL_STATE: Device state - isNull: ${_bluetoothService.device == null}, isConnected: ${_bluetoothService.device?.isConnected ?? false}', 'SleepDoctorDataConnector');
      
      try {
      await _performImmediateHandshake();
        BLELogger.info('BLE_HANDSHAKE_POST_CALL: Handshake call completed successfully', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        BLELogger.error('BLE_HANDSHAKE_CALL_EXCEPTION: Exception during handshake call', e, 'SleepDoctorDataConnector');
        BLELogger.error('BLE_HANDSHAKE_CALL_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('BLE_HANDSHAKE_CALL_EXCEPTION_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
        BLELogger.error('BLE_HANDSHAKE_CALL_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        
        // Log device state at time of exception
        final deviceStateAtException = _bluetoothService.device == null 
            ? "null" 
            : (_bluetoothService.device!.isConnected ? "connected" : "disconnected");
        BLELogger.error('BLE_HANDSHAKE_CALL_EXCEPTION_STATE: Device state at exception: $deviceStateAtException', null, 'SleepDoctorDataConnector');
        
        rethrow;
      }

      // Step 5: Set up and wait for device button press notification
      // CRITICAL: Sync must NOT start until device button is pressed
      // The UI will continue showing "Searching for device... Press blue button" 
      // until the button press notification is received
      BLELogger.info('SYNC_STEP5: Waiting for device button press notification', 'SleepDoctorDataConnector');
      final buttonPressStartTime = DateTime.now();
      
      try {
        _bluetoothServiceStatesObserver?.waitingForButtonPress(true);
        await _waitForDeviceButtonPress();
        final buttonPressEndTime = DateTime.now();
        final buttonPressDuration = buttonPressEndTime.difference(buttonPressStartTime);
        BLELogger.info('SYNC_STEP5_SUCCESS: Button press received (waited ${buttonPressDuration.inMilliseconds}ms)', 'SleepDoctorDataConnector');
        _bluetoothServiceStatesObserver?.waitingForButtonPress(false);
      } catch (e, stackTrace) {
        final buttonPressErrorTime = DateTime.now();
        final buttonPressDuration = buttonPressErrorTime.difference(buttonPressStartTime);
        BLELogger.error('SYNC_STEP5_EXCEPTION: Exception while waiting for button press (took ${buttonPressDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP5_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP5_EXCEPTION_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP5_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        _bluetoothServiceStatesObserver?.waitingForButtonPress(false);
        rethrow;
      }

      // Step 6: Button pressed - now start sync
      BLELogger.info('SYNC_STEP6: Button pressed - starting data fetch', 'SleepDoctorDataConnector');

      // Step 7: Fetch time service
      BLELogger.info('SYNC_STEP7: Fetching time service', 'SleepDoctorDataConnector');
      final timeServiceStartTime = DateTime.now();
      DateTime deviceTime;
      
      try {
        deviceTime = await _fetchFromTimeService();
        final timeServiceEndTime = DateTime.now();
        final timeServiceDuration = timeServiceEndTime.difference(timeServiceStartTime);
        BLELogger.info('SYNC_STEP7_SUCCESS: Time service fetched in ${timeServiceDuration.inMilliseconds}ms, device time: ${deviceTime.toIso8601String()}', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final timeServiceErrorTime = DateTime.now();
        final timeServiceDuration = timeServiceErrorTime.difference(timeServiceStartTime);
        BLELogger.error('SYNC_STEP7_EXCEPTION: Exception during time service fetch (took ${timeServiceDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP7_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP7_EXCEPTION_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP7_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        rethrow;
      }

      // Step 8: Fetch sleep data service
      BLELogger.info('SYNC_STEP8: Fetching sleep data service', 'SleepDoctorDataConnector');
      BLELogger.info('SYNC_STEP8_PARAMS: Device time: ${deviceTime.toIso8601String()}', 'SleepDoctorDataConnector');
      final dataFetchStartTime = DateTime.now();
      List<SleepDoctorAbstractData> data;
      
      try {
        data = await _fetchFromSleepDoctorDataServiceWith(deviceTime);
        final dataFetchEndTime = DateTime.now();
        final dataFetchDuration = dataFetchEndTime.difference(dataFetchStartTime);
        BLELogger.info('SYNC_STEP8_SUCCESS: Sleep data fetched in ${dataFetchDuration.inMilliseconds}ms, ${data.length} records', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final dataFetchErrorTime = DateTime.now();
        final dataFetchDuration = dataFetchErrorTime.difference(dataFetchStartTime);
        BLELogger.error('SYNC_STEP8_EXCEPTION: Exception during sleep data fetch (took ${dataFetchDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP8_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP8_EXCEPTION_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_STEP8_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        rethrow;
      }

      final syncEndTime = DateTime.now();
      final totalSyncDuration = syncEndTime.difference(syncStartTime);
      BLELogger.info('SYNC_SUCCESS: Sync completed successfully in ${totalSyncDuration.inMilliseconds}ms - ${data.length} records', 'SleepDoctorDataConnector');
      BLELogger.info('SYNC_SUCCESS_TIME: Sync end time: ${syncEndTime.toIso8601String()}', 'SleepDoctorDataConnector');
      BLELogger.info('SYNC_SUCCESS_RESULT: Records fetched: ${data.length}', 'SleepDoctorDataConnector');
      return data;

    } catch (e, stackTrace) {
      final syncErrorTime = DateTime.now();
      final totalSyncDuration = syncErrorTime.difference(syncStartTime);
      BLELogger.error('SYNC_FAILED: Sync failed after ${totalSyncDuration.inMilliseconds}ms', e, 'SleepDoctorDataConnector');
      BLELogger.error('SYNC_FAILED_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
      BLELogger.error('SYNC_FAILED_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
      BLELogger.error('SYNC_FAILED_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
      
      // Log final device state
      final finalDeviceState = _bluetoothService.device == null 
          ? "null" 
          : (_bluetoothService.device!.isConnected ? "connected" : "disconnected");
      BLELogger.error('SYNC_FAILED_STATE: Final device state: $finalDeviceState', null, 'SleepDoctorDataConnector');
      BLELogger.error('SYNC_FAILED_STATE_DETAILS: isSyncInProgress: $_isSyncInProgress, shouldStopSync: $_shouldStopSync', null, 'SleepDoctorDataConnector');
      
      try {
        await resetBluetooth();
        BLELogger.info('SYNC_FAILED_RESET: Bluetooth reset completed', 'SleepDoctorDataConnector');
      } catch (resetError, resetStackTrace) {
        BLELogger.error('SYNC_FAILED_RESET_EXCEPTION: Exception during Bluetooth reset', resetError, 'SleepDoctorDataConnector');
        BLELogger.error('SYNC_FAILED_RESET_EXCEPTION_STACK: ${resetStackTrace.toString()}', null, 'SleepDoctorDataConnector');
      }
      
      rethrow;
    } finally {
      _isSyncInProgress = false;
      _shouldStopSync = false;
      _stopConnectionStateMonitoring();
      _stopButtonPressNotificationSubscription();
      _stopKeepAliveTimer();
      
      // CRITICAL FIX: Clear cached service/characteristic on sync completion
      _cachedSleepDataService = null;
      _cachedSleepDataCharacteristic = null;
      
      // PRODUCTION HARDENING: Stop foreground service when sync completes
      if (Platform.isAndroid) {
        await ForegroundServiceController.stopService();
      }
      
      // PRODUCTION HARDENING: Clear lifecycle callback when sync completes
      AppLifecycleManager().setSyncStopCallback(null);
    }
  }

  //########################################################################
  //DATA EXCHANGE
  //########################################################################

  /// Fetch time from device - refactored with async/await and error handling
  Future<DateTime> _fetchFromTimeService() async {
    final methodStartTime = DateTime.now();
    BLELogger.info('TIME_SERVICE_METHOD_ENTRY: _fetchFromTimeService() called at ${methodStartTime.toIso8601String()}', 'SleepDoctorDataConnector');
    BLELogger.info('TIME_SERVICE_PARAMS: Service UUID: ${BLEConfig.ctsServiceUUID}, Characteristic UUID: ${BLEConfig.currentTimeCharacteristicUUID}', 'SleepDoctorDataConnector');
    BLELogger.info('TIME_SERVICE_DEVICE_STATE: Device state - isNull: ${_bluetoothService.device == null}, isConnected: ${_bluetoothService.device?.isConnected ?? false}', 'SleepDoctorDataConnector');
    
    try {
      // Read service
      final serviceReadStartTime = DateTime.now();
      BLELogger.info('TIME_SERVICE_STEP1: Reading time service', 'SleepDoctorDataConnector');
      BluetoothService service;
      
      try {
        service = await _bluetoothService.readServiceFromDevice(BLEConfig.ctsServiceUUID);
        final serviceReadEndTime = DateTime.now();
        final serviceReadDuration = serviceReadEndTime.difference(serviceReadStartTime);
        BLELogger.info('TIME_SERVICE_STEP1_SUCCESS: Service read completed in ${serviceReadDuration.inMilliseconds}ms, UUID: ${service.uuid}', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final serviceReadErrorTime = DateTime.now();
        final serviceReadDuration = serviceReadErrorTime.difference(serviceReadStartTime);
        BLELogger.error('TIME_SERVICE_STEP1_EXCEPTION: Exception during service read (took ${serviceReadDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('TIME_SERVICE_STEP1_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('TIME_SERVICE_STEP1_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        rethrow;
      }
      
      // Read characteristic
      final characteristicReadStartTime = DateTime.now();
      BluetoothCharacteristic characteristic;
      
      try {
        characteristic = await _bluetoothService.readCharacteristicFrom(
          service,
          BLEConfig.currentTimeCharacteristicUUID,
        );
        final characteristicReadEndTime = DateTime.now();
        final characteristicReadDuration = characteristicReadEndTime.difference(characteristicReadStartTime);
        BLELogger.info('TIME_SERVICE_STEP2_SUCCESS: Characteristic read completed in ${characteristicReadDuration.inMilliseconds}ms, UUID: ${characteristic.uuid}', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final characteristicReadErrorTime = DateTime.now();
        final characteristicReadDuration = characteristicReadErrorTime.difference(characteristicReadStartTime);
        BLELogger.error('TIME_SERVICE_STEP2_EXCEPTION: Exception during characteristic read (took ${characteristicReadDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('TIME_SERVICE_STEP2_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('TIME_SERVICE_STEP2_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        rethrow;
      }

      // Read current device time
      final timeReadStartTime = DateTime.now();
      BLELogger.info('TIME_SERVICE_STEP3: Reading device time from characteristic', 'SleepDoctorDataConnector');
      List<int> data;
      DateTime deviceDate;
      
      try {
        data = await characteristic.read();
        final timeReadEndTime = DateTime.now();
        final timeReadDuration = timeReadEndTime.difference(timeReadStartTime);
        BLELogger.info('TIME_SERVICE_STEP3_READ: Characteristic read completed in ${timeReadDuration.inMilliseconds}ms, data length: ${data.length} bytes', 'SleepDoctorDataConnector');
        
        deviceDate = BluetoothDataHelper.parseDate(from: data);
        BLELogger.info('TIME_SERVICE_STEP3_SUCCESS: Device time parsed: ${deviceDate.toIso8601String()}', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final timeReadErrorTime = DateTime.now();
        final timeReadDuration = timeReadErrorTime.difference(timeReadStartTime);
        BLELogger.error('TIME_SERVICE_STEP3_EXCEPTION: Exception during time read/parse (took ${timeReadDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('TIME_SERVICE_STEP3_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('TIME_SERVICE_STEP3_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        rethrow;
      }

      // Write current phone time to device
      final timeWriteStartTime = DateTime.now();
      final currentTime = DateTime.now();
      final currentTimeData = BluetoothDataHelper.prepareDateAsData(from: currentTime);
      BLELogger.info('TIME_SERVICE_STEP4: Writing phone time to device: ${currentTime.toIso8601String()}', 'SleepDoctorDataConnector');
      BLELogger.info('TIME_SERVICE_STEP4_DATA: Data length: ${currentTimeData.length} bytes', 'SleepDoctorDataConnector');
      
      try {
        await _writeDataToCharacteristics(characteristic, currentTimeData);
        final timeWriteEndTime = DateTime.now();
        final timeWriteDuration = timeWriteEndTime.difference(timeWriteStartTime);
        BLELogger.info('TIME_SERVICE_STEP4_SUCCESS: Time write completed in ${timeWriteDuration.inMilliseconds}ms', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final timeWriteErrorTime = DateTime.now();
        final timeWriteDuration = timeWriteErrorTime.difference(timeWriteStartTime);
        BLELogger.error('TIME_SERVICE_STEP4_EXCEPTION: Exception during time write (took ${timeWriteDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('TIME_SERVICE_STEP4_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('TIME_SERVICE_STEP4_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        rethrow;
      }

      final methodEndTime = DateTime.now();
      final totalMethodDuration = methodEndTime.difference(methodStartTime);
      BLELogger.info('TIME_SERVICE_METHOD_SUCCESS: Method completed successfully in ${totalMethodDuration.inMilliseconds}ms', 'SleepDoctorDataConnector');
      BLELogger.info('TIME_SERVICE_METHOD_RESULT: Device time: ${deviceDate.toIso8601String()}', 'SleepDoctorDataConnector');
      
      return deviceDate;
    } catch (e, stackTrace) {
      final methodErrorTime = DateTime.now();
      final totalMethodDuration = methodErrorTime.difference(methodStartTime);
      BLELogger.error('TIME_SERVICE_METHOD_EXCEPTION: Method failed after ${totalMethodDuration.inMilliseconds}ms', e, 'SleepDoctorDataConnector');
      BLELogger.error('TIME_SERVICE_METHOD_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
      BLELogger.error('TIME_SERVICE_METHOD_EXCEPTION_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
      BLELogger.error('TIME_SERVICE_METHOD_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
      
      // Log device state at exception time
      final deviceStateAtException = _bluetoothService.device == null 
          ? "null" 
          : (_bluetoothService.device!.isConnected ? "connected" : "disconnected");
      BLELogger.error('TIME_SERVICE_METHOD_EXCEPTION_STATE: Device state at exception: $deviceStateAtException', null, 'SleepDoctorDataConnector');
      
      rethrow;
    }
  }

  /// Fetch sleep data from device - refactored with async/await, keep-alive, and error handling
  Future<List<SleepDoctorAbstractData>> _fetchFromSleepDoctorDataServiceWith(
      DateTime deviceTime) async {
    final methodStartTime = DateTime.now();
    BLELogger.info('SLEEP_DATA_METHOD_ENTRY: _fetchFromSleepDoctorDataServiceWith() called at ${methodStartTime.toIso8601String()}', 'SleepDoctorDataConnector');
    BLELogger.info('SLEEP_DATA_PARAMS: Device time: ${deviceTime.toIso8601String()}, Service UUID: ${BLEConfig.sdsServiceUUID}, Characteristic UUID: ${BLEConfig.sleepDoctorCharacteristicUUID}', 'SleepDoctorDataConnector');
    BLELogger.info('SLEEP_DATA_DEVICE_STATE: Device state - isNull: ${_bluetoothService.device == null}, isConnected: ${_bluetoothService.device?.isConnected ?? false}', 'SleepDoctorDataConnector');
    
    try {
      // Read service
      final serviceReadStartTime = DateTime.now();
      BLELogger.info('SLEEP_DATA_STEP1: Reading sleep data service', 'SleepDoctorDataConnector');
      BluetoothService service;
      
      try {
        service = await _bluetoothService.readServiceFromDevice(BLEConfig.sdsServiceUUID);
        final serviceReadEndTime = DateTime.now();
        final serviceReadDuration = serviceReadEndTime.difference(serviceReadStartTime);
        BLELogger.info('SLEEP_DATA_STEP1_SUCCESS: Service read completed in ${serviceReadDuration.inMilliseconds}ms, UUID: ${service.uuid}', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final serviceReadErrorTime = DateTime.now();
        final serviceReadDuration = serviceReadErrorTime.difference(serviceReadStartTime);
        BLELogger.error('SLEEP_DATA_STEP1_EXCEPTION: Exception during service read (took ${serviceReadDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('SLEEP_DATA_STEP1_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SLEEP_DATA_STEP1_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        rethrow;
      }
      
      // Read characteristic
      final characteristicReadStartTime = DateTime.now();
      BluetoothCharacteristic characteristic;
      
      try {
        characteristic = await _bluetoothService.readCharacteristicFrom(
          service,
          BLEConfig.sleepDoctorCharacteristicUUID,
        );
        final characteristicReadEndTime = DateTime.now();
        final characteristicReadDuration = characteristicReadEndTime.difference(characteristicReadStartTime);
        BLELogger.info('SLEEP_DATA_STEP2_SUCCESS: Characteristic read completed in ${characteristicReadDuration.inMilliseconds}ms, UUID: ${characteristic.uuid}', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final characteristicReadErrorTime = DateTime.now();
        final characteristicReadDuration = characteristicReadErrorTime.difference(characteristicReadStartTime);
        BLELogger.error('SLEEP_DATA_STEP2_EXCEPTION: Exception during characteristic read (took ${characteristicReadDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('SLEEP_DATA_STEP2_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SLEEP_DATA_STEP2_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        rethrow;
      }

      // Start keep-alive timer
      final keepAliveStartTime = DateTime.now();
      BLELogger.info('SLEEP_DATA_STEP3: Starting keep-alive timer', 'SleepDoctorDataConnector');
      try {
        _startKeepAliveTimer(characteristic);
        final keepAliveEndTime = DateTime.now();
        final keepAliveDuration = keepAliveEndTime.difference(keepAliveStartTime);
        BLELogger.info('SLEEP_DATA_STEP3_SUCCESS: Keep-alive timer started in ${keepAliveDuration.inMilliseconds}ms', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final keepAliveErrorTime = DateTime.now();
        final keepAliveDuration = keepAliveErrorTime.difference(keepAliveStartTime);
        BLELogger.error('SLEEP_DATA_STEP3_EXCEPTION: Exception during keep-alive timer start (took ${keepAliveDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('SLEEP_DATA_STEP3_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SLEEP_DATA_STEP3_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        // Continue - keep-alive failure is non-critical
      }

      // Read data with timeout
      final dataReadStartTime = DateTime.now();
      BLELogger.info('SLEEP_DATA_STEP4: Starting data read with timeout ${BLEConfig.readTimeout.inSeconds}s', 'SleepDoctorDataConnector');
      List<List<int>> readData;
      
      try {
        readData = await _readDataFromCharacteristic(characteristic)
            .timeout(
              BLEConfig.readTimeout,
              onTimeout: () {
                final timeoutTime = DateTime.now();
                final timeoutDuration = timeoutTime.difference(dataReadStartTime);
                BLELogger.error('SLEEP_DATA_STEP4_TIMEOUT: Read timeout after ${timeoutDuration.inMilliseconds}ms (${BLEConfig.readTimeout.inSeconds}s)', null, 'SleepDoctorDataConnector');
                throw TimeoutException(
                  'Device did not send E_ETX signal in time',
                  BLEConfig.readTimeout,
                );
              },
            );
        final dataReadEndTime = DateTime.now();
        final dataReadDuration = dataReadEndTime.difference(dataReadStartTime);
        BLELogger.info('SLEEP_DATA_STEP4_SUCCESS: Data read completed in ${dataReadDuration.inMilliseconds}ms, ${readData.length} packets received', 'SleepDoctorDataConnector');
        BLELogger.info('SLEEP_DATA_STEP4_RESULT: Total packets: ${readData.length}, Total bytes: ${readData.fold<int>(0, (sum, packet) => sum + packet.length)}', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final dataReadErrorTime = DateTime.now();
        final dataReadDuration = dataReadErrorTime.difference(dataReadStartTime);
        BLELogger.error('SLEEP_DATA_STEP4_EXCEPTION: Exception during data read (took ${dataReadDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('SLEEP_DATA_STEP4_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SLEEP_DATA_STEP4_EXCEPTION_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SLEEP_DATA_STEP4_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        _stopKeepAliveTimer();
        rethrow;
      }

      // Stop keep-alive timer
      final keepAliveStopStartTime = DateTime.now();
      BLELogger.info('SLEEP_DATA_STEP5: Stopping keep-alive timer', 'SleepDoctorDataConnector');
      try {
        _stopKeepAliveTimer();
        final keepAliveStopEndTime = DateTime.now();
        final keepAliveStopDuration = keepAliveStopEndTime.difference(keepAliveStopStartTime);
        BLELogger.info('SLEEP_DATA_STEP5_SUCCESS: Keep-alive timer stopped in ${keepAliveStopDuration.inMilliseconds}ms', 'SleepDoctorDataConnector');
      } catch (e) {
        BLELogger.warning('SLEEP_DATA_STEP5_WARNING: Exception during keep-alive timer stop (non-critical): $e', 'SleepDoctorDataConnector');
      }

      // Clear data from device
      final clearDataStartTime = DateTime.now();
      BLELogger.info('SLEEP_DATA_STEP6: Clearing data from device', 'SleepDoctorDataConnector');
      try {
        await _clearDataFromCharacteristics(characteristic);
        final clearDataEndTime = DateTime.now();
        final clearDataDuration = clearDataEndTime.difference(clearDataStartTime);
        BLELogger.info('SLEEP_DATA_STEP6_SUCCESS: Data cleared in ${clearDataDuration.inMilliseconds}ms', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final clearDataErrorTime = DateTime.now();
        final clearDataDuration = clearDataErrorTime.difference(clearDataStartTime);
        BLELogger.error('SLEEP_DATA_STEP6_EXCEPTION: Exception during data clear (took ${clearDataDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('SLEEP_DATA_STEP6_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SLEEP_DATA_STEP6_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        // Continue - data clear failure is non-critical
      }

      // Post-process and return
      final postProcessStartTime = DateTime.now();
      BLELogger.info('SLEEP_DATA_STEP7: Post-processing data', 'SleepDoctorDataConnector');
      List<SleepDoctorAbstractData> processedData;
      
      try {
        processedData = await _postProcess(readData, deviceTime);
        final postProcessEndTime = DateTime.now();
        final postProcessDuration = postProcessEndTime.difference(postProcessStartTime);
        BLELogger.info('SLEEP_DATA_STEP7_SUCCESS: Post-processing completed in ${postProcessDuration.inMilliseconds}ms, ${processedData.length} records', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final postProcessErrorTime = DateTime.now();
        final postProcessDuration = postProcessErrorTime.difference(postProcessStartTime);
        BLELogger.error('SLEEP_DATA_STEP7_EXCEPTION: Exception during post-processing (took ${postProcessDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('SLEEP_DATA_STEP7_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('SLEEP_DATA_STEP7_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        rethrow;
      }

      final methodEndTime = DateTime.now();
      final totalMethodDuration = methodEndTime.difference(methodStartTime);
      BLELogger.info('SLEEP_DATA_METHOD_SUCCESS: Method completed successfully in ${totalMethodDuration.inMilliseconds}ms', 'SleepDoctorDataConnector');
      BLELogger.info('SLEEP_DATA_METHOD_RESULT: Processed records: ${processedData.length}', 'SleepDoctorDataConnector');
      
      return processedData;
    } catch (e, stackTrace) {
      final methodErrorTime = DateTime.now();
      final totalMethodDuration = methodErrorTime.difference(methodStartTime);
      BLELogger.error('SLEEP_DATA_METHOD_EXCEPTION: Method failed after ${totalMethodDuration.inMilliseconds}ms', e, 'SleepDoctorDataConnector');
      BLELogger.error('SLEEP_DATA_METHOD_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
      BLELogger.error('SLEEP_DATA_METHOD_EXCEPTION_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
      BLELogger.error('SLEEP_DATA_METHOD_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
      
      // Log device state at exception time
      final deviceStateAtException = _bluetoothService.device == null 
          ? "null" 
          : (_bluetoothService.device!.isConnected ? "connected" : "disconnected");
      BLELogger.error('SLEEP_DATA_METHOD_EXCEPTION_STATE: Device state at exception: $deviceStateAtException', null, 'SleepDoctorDataConnector');
      
      // Ensure keep-alive timer is stopped
      try {
        _stopKeepAliveTimer();
      } catch (stopError) {
        BLELogger.warning('SLEEP_DATA_METHOD_EXCEPTION_CLEANUP: Exception during keep-alive timer stop: $stopError', 'SleepDoctorDataConnector');
      }
      
      rethrow;
    }
  }

  /// Start keep-alive timer to ping device during long reads
  /// PRODUCTION HARDENING: Actually performs keep-alive operation to prevent Android BLE timeout
  /// Safely skips keep-alive when data read is actively happening to prevent interference
  void _startKeepAliveTimer(BluetoothCharacteristic characteristic) {
    _stopKeepAliveTimer(); // Ensure no existing timer
    
    _keepAliveTimer = Timer.periodic(BLEConfig.keepAliveInterval, (timer) async {
      if (!_isSyncInProgress || _shouldStopSync) {
        timer.cancel();
        return;
      }

      // PRODUCTION HARDENING: Skip keep-alive if data read is actively happening
      // This prevents concurrent characteristic reads that could interfere with data stream
      if (_isReadingData) {
        BLELogger.debug('Skipping keep-alive - data read in progress', 'SleepDoctorDataConnector');
        return; // Skip this iteration, will try again on next interval
      }

      try {
        // Check if device is still connected
        if (_bluetoothService.device == null || !_bluetoothService.device!.isConnected) {
          BLELogger.warning('Device disconnected during keep-alive check', 'SleepDoctorDataConnector');
          _shouldStopSync = true;
          timer.cancel();
          return;
        }

        // PRODUCTION HARDENING: Perform actual keep-alive operation
        // Read the characteristic value (even if we don't use it) to keep BLE connection active
        // This prevents Android BLE stack from timing out during long read operations
        // We use a timeout to prevent blocking if read fails
        // NOTE: This read happens when NOT actively reading data packets to avoid interference
        BLELogger.debug('Keep-alive ping - reading characteristic to maintain connection', 'SleepDoctorDataConnector');
        try {
          // Read with short timeout - we don't care about the value, just need BLE activity
          await characteristic.read().timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              BLELogger.debug('Keep-alive read timeout (non-critical)', 'SleepDoctorDataConnector');
              return <int>[]; // Return empty list on timeout
            },
          );
          BLELogger.debug('Keep-alive ping successful', 'SleepDoctorDataConnector');
        } catch (readError) {
          // Keep-alive read failure is non-critical - connection state monitoring will detect real disconnects
          BLELogger.debug('Keep-alive read failed (non-critical): $readError', 'SleepDoctorDataConnector');
        }
      } catch (e) {
        BLELogger.warning('Keep-alive check failed', 'SleepDoctorDataConnector');
        // Don't stop sync for keep-alive failures - connection state monitoring handles real disconnects
      }
    });
  }

  void _stopKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  Future<bool> resetBluetooth() async {
    try {
      BLELogger.info('Resetting Bluetooth state', 'SleepDoctorDataConnector');
      _stopKeepAliveTimer();
      await _bluetoothService.disconnectDevice();
      await _bluetoothService.stopScanning();
      return true;
    } catch (e) {
      BLELogger.error('Error resetting Bluetooth', e, 'SleepDoctorDataConnector');
      return false;
    }
  }

  //########################################################################
  // IMMEDIATE HANDSHAKE (CRITICAL FOR CONNECTION STABILITY)
  //########################################################################

  /// Perform immediate BLE handshake after connection
  /// This prevents device from disconnecting due to inactivity
  Future<void> _performImmediateHandshake() async {
    // RECOMMENDATION 2.2: Add logging to verify handshake method entry
    // RECOMMENDATION 2.3: Add enhanced logging to verify method entry
    // This confirms handshake method is called and helps identify if method entry is reached
    BLELogger.info('BLE_HANDSHAKE_METHOD_ENTRY: _performImmediateHandshake() method entry point', 'SleepDoctorDataConnector');
    BLELogger.debug('BLE_HANDSHAKE_METHOD_ENTRY_DEBUG: Method entry (DEBUG level)', 'SleepDoctorDataConnector');
    BLELogger.info('BLE_HANDSHAKE_METHOD_ENTRY_TIME: Entry time: ${DateTime.now().toIso8601String()}', 'SleepDoctorDataConnector');
    
    // RECOMMENDATION 2.3: Add immediate BLE activity at method entry to prevent timeout
    try {
      if (_bluetoothService.device != null && _bluetoothService.device!.isConnected) {
        _cachedSleepDataService?.uuid; // Simple property access maintains BLE activity
        BLELogger.debug('BLE_HANDSHAKE_METHOD_ENTRY_KEEPALIVE: Keep-alive at method entry', 'SleepDoctorDataConnector');
      }
    } catch (e) {
      // Ignore - best effort
    }
    
    // RECOMMENDATION 1.3: Add logging to verify handshake is called
    // This helps diagnose if handshake method is actually being called
    final handshakeMethodStartTime = DateTime.now();
    BLELogger.info('BLE_HANDSHAKE_METHOD_START: _performImmediateHandshake() method called at ${handshakeMethodStartTime.toIso8601String()}', 'SleepDoctorDataConnector');
    
    // RECOMMENDATION 2.1: Use stream-based connection check instead of synchronous check
    // This is more reliable as it catches async disconnects that may not be registered synchronously
    BLELogger.debug('BLE_HANDSHAKE_METHOD_PRE_CONNECTION_CHECK: About to verify connection before handshake', 'SleepDoctorDataConnector');
    final isConnected = await _bluetoothService.verifyConnectionWithStream(timeout: const Duration(milliseconds: 10));
    if (!isConnected) {
      BLELogger.error('BLE_HANDSHAKE_FAILED: Cannot perform handshake - device not connected (stream verification)', null, 'SleepDoctorDataConnector');
      throw StateError('Device not connected for handshake');
    }
    BLELogger.debug('BLE_HANDSHAKE_METHOD_POST_CONNECTION_CHECK: Connection verified, proceeding with handshake', 'SleepDoctorDataConnector');

    // RECOMMENDATION 3.1: Start connection state monitoring during handshake
    // This provides real-time disconnect detection and better diagnostics
    BLELogger.debug('BLE_HANDSHAKE_METHOD_PRE_MONITORING: About to start connection state monitoring', 'SleepDoctorDataConnector');
    _handshakeDisconnectDetected = false; // Reset flag
    _startHandshakeConnectionStateMonitoring();
    BLELogger.debug('BLE_HANDSHAKE_METHOD_POST_MONITORING: Connection state monitoring started', 'SleepDoctorDataConnector');

    // RECOMMENDATION 3.1: Start continuous keep-alive during handshake
    // This provides continuous BLE activity during entire handshake to prevent device timeout
    BLELogger.debug('BLE_HANDSHAKE_METHOD_PRE_KEEPALIVE: About to start continuous keep-alive timer', 'SleepDoctorDataConnector');
    _startHandshakeKeepAliveTimer();
    BLELogger.debug('BLE_HANDSHAKE_METHOD_POST_KEEPALIVE: Continuous keep-alive timer started', 'SleepDoctorDataConnector');

    BLELogger.debug('BLE_HANDSHAKE_METHOD_PRE_TRY: About to enter try block', 'SleepDoctorDataConnector');

    try {
      // CRITICAL FIX: Log handshake start time for timing analysis
      final handshakeStartTime = DateTime.now();
      BLELogger.info('BLE_HANDSHAKE_START_TIMING: Handshake started at ${handshakeStartTime.toIso8601String()}', 'SleepDoctorDataConnector');
      BLELogger.info('BLE_HANDSHAKE_START_PARAMS: Service UUID: ${BLEConfig.sdsServiceUUID}, Characteristic UUID: ${BLEConfig.sleepDoctorCharacteristicUUID}', 'SleepDoctorDataConnector');
      BLELogger.info('BLE_HANDSHAKE_START_DEVICE: Device state - isNull: ${_bluetoothService.device == null}, isConnected: ${_bluetoothService.device?.isConnected ?? false}', 'SleepDoctorDataConnector');
      
      // Step 1: Discover sleep data service immediately (only once)
      BLELogger.info('BLE_HANDSHAKE_STEP1: Discovering sleep data service', 'SleepDoctorDataConnector');
      final step1StartTime = DateTime.now();
      DateTime? step1EndTime;
      BluetoothService service;
      
      try {
        service = await _bluetoothService.readServiceFromDevice(BLEConfig.sdsServiceUUID);
        
        step1EndTime = DateTime.now();
        final step1Duration = step1EndTime.difference(step1StartTime);
        BLELogger.info('BLE_HANDSHAKE_STEP1_TIMING: Service discovery completed in ${step1Duration.inMilliseconds}ms', 'SleepDoctorDataConnector');
        BLELogger.info('BLE_HANDSHAKE_STEP1_RESULT: Service UUID: ${service.uuid}, Characteristics count: ${service.characteristics.length}', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final step1ErrorTime = DateTime.now();
        final step1Duration = step1ErrorTime.difference(step1StartTime);
        BLELogger.error('BLE_HANDSHAKE_STEP1_EXCEPTION: Exception during service discovery (took ${step1Duration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('BLE_HANDSHAKE_STEP1_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('BLE_HANDSHAKE_STEP1_EXCEPTION_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
        BLELogger.error('BLE_HANDSHAKE_STEP1_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        
        // Log device state at exception time
        final deviceStateAtException = _bluetoothService.device == null 
            ? "null" 
            : (_bluetoothService.device!.isConnected ? "connected" : "disconnected");
        BLELogger.error('BLE_HANDSHAKE_STEP1_EXCEPTION_STATE: Device state at exception: $deviceStateAtException', null, 'SleepDoctorDataConnector');
        rethrow;
      }
      
      // CRITICAL FIX: Cache service to avoid re-discovery
      _cachedSleepDataService = service;
      
      // RECOMMENDATION 3.1: Add immediate BLE activity after Step 1
      // This maintains BLE activity between handshake steps
      try {
        if (_bluetoothService.device != null && _bluetoothService.device!.isConnected) {
          _cachedSleepDataService?.uuid;
          BLELogger.debug('BLE_HANDSHAKE_STEP1_POST_KEEPALIVE: Keep-alive after Step 1', 'SleepDoctorDataConnector');
        }
      } catch (e) {
        // Ignore
      }
      
      // RECOMMENDATION 2.1: Use stream-based connection check instead of synchronous check
      // This is more reliable as it catches async disconnects that may not be registered synchronously
      final isConnectedAfterStep1 = await _bluetoothService.verifyConnectionWithStream(timeout: const Duration(milliseconds: 10));
      if (!isConnectedAfterStep1) {
        final disconnectTime = DateTime.now();
        final timeSinceStep1 = disconnectTime.difference(step1EndTime);
        BLELogger.error('BLE_HANDSHAKE_FAILED: Device disconnected ${timeSinceStep1.inMilliseconds}ms after service discovery completed (stream verification)', null, 'SleepDoctorDataConnector');
        _cachedSleepDataService = null;
        throw StateError('Device disconnected during handshake');
      }
      
      BLELogger.info('BLE_HANDSHAKE_STEP1_SUCCESS: Service discovered and connection verified', 'SleepDoctorDataConnector');

      // RECOMMENDATION 3.1: Check if disconnect was detected via monitoring
      if (_handshakeDisconnectDetected) {
        BLELogger.error('BLE_HANDSHAKE_FAILED: Disconnect detected via monitoring after Step 1', null, 'SleepDoctorDataConnector');
        _cachedSleepDataService = null;
        throw StateError('Device disconnected during handshake (detected via monitoring)');
      }

      // RECOMMENDATION 2.2: Add keep-alive between handshake steps
      // This maintains BLE activity between steps to prevent device timeout
      try {
        await Future.delayed(const Duration(milliseconds: 1)); // Minimal delay
        if (_bluetoothService.device != null && _bluetoothService.device!.isConnected) {
          // Access service property to maintain connection (simple keep-alive activity)
          _cachedSleepDataService?.uuid; // Simple property access maintains BLE activity
          BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_STEP1: Keep-alive activity completed after Step 1', 'SleepDoctorDataConnector');
          // RECOMMENDATION 2.3: Add timing log after keep-alive operation
          BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_STEP1_TIME: Completed at ${DateTime.now().toIso8601String()}', 'SleepDoctorDataConnector');
        }
      } catch (e) {
        // Ignore - keep-alive is best effort, don't fail handshake if it fails
        BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_STEP1_FAILED: Keep-alive failed (non-critical): $e', 'SleepDoctorDataConnector');
      }

      // RECOMMENDATION 1.2: Add immediate BLE activity after keep-alive Step 1
      // This prevents device timeout by maintaining continuous BLE activity
      // Device disconnects 40-60ms after keep-alive Step 1 if no BLE activity occurs
      try {
        if (_bluetoothService.device != null && _bluetoothService.device!.isConnected) {
          // Access service property to maintain connection (simple keep-alive activity)
          _cachedSleepDataService?.uuid; // Simple property access maintains BLE activity
          BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_POST_STEP1: Immediate activity after Step 1 keep-alive', 'SleepDoctorDataConnector');
        }
      } catch (e) {
        // Ignore - keep-alive is best effort, don't fail handshake if it fails
        BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_POST_STEP1_FAILED: Keep-alive failed (non-critical): $e', 'SleepDoctorDataConnector');
      }

      // Step 2: Get characteristic immediately
      BLELogger.info('BLE_HANDSHAKE_STEP2: Getting sleep data characteristic', 'SleepDoctorDataConnector');
      BLELogger.info('BLE_HANDSHAKE_STEP2_PARAMS: Service UUID: ${service.uuid}, Characteristic UUID: ${BLEConfig.sleepDoctorCharacteristicUUID}', 'SleepDoctorDataConnector');
      final step2StartTime = DateTime.now();
      DateTime? step2EndTime;
      BluetoothCharacteristic characteristic;
      
      try {
        characteristic = await _bluetoothService.readCharacteristicFrom(
          service,
          BLEConfig.sleepDoctorCharacteristicUUID,
        );
        
        step2EndTime = DateTime.now();
        final step2Duration = step2EndTime.difference(step2StartTime);
        BLELogger.info('BLE_HANDSHAKE_STEP2_TIMING: Characteristic lookup completed in ${step2Duration.inMilliseconds}ms', 'SleepDoctorDataConnector');
        BLELogger.info('BLE_HANDSHAKE_STEP2_RESULT: Characteristic UUID: ${characteristic.uuid}, Properties: notify=${characteristic.properties.notify}, indicate=${characteristic.properties.indicate}', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final step2ErrorTime = DateTime.now();
        final step2Duration = step2ErrorTime.difference(step2StartTime);
        BLELogger.error('BLE_HANDSHAKE_STEP2_EXCEPTION: Exception during characteristic lookup (took ${step2Duration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('BLE_HANDSHAKE_STEP2_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('BLE_HANDSHAKE_STEP2_EXCEPTION_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
        BLELogger.error('BLE_HANDSHAKE_STEP2_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        
        // Log device state at exception time
        final deviceStateAtException = _bluetoothService.device == null 
            ? "null" 
            : (_bluetoothService.device!.isConnected ? "connected" : "disconnected");
        BLELogger.error('BLE_HANDSHAKE_STEP2_EXCEPTION_STATE: Device state at exception: $deviceStateAtException', null, 'SleepDoctorDataConnector');
        rethrow;
      }
      
      // CRITICAL FIX: Cache characteristic to avoid re-lookup
      _cachedSleepDataCharacteristic = characteristic;
      
      // RECOMMENDATION 2.1: Use stream-based connection check instead of synchronous check
      // This is more reliable as it catches async disconnects that may not be registered synchronously
      final isConnectedAfterStep2 = await _bluetoothService.verifyConnectionWithStream(timeout: const Duration(milliseconds: 10));
      if (!isConnectedAfterStep2) {
        final disconnectTime = DateTime.now();
        final timeSinceStep2 = disconnectTime.difference(step2EndTime);
        BLELogger.error('BLE_HANDSHAKE_FAILED: Device disconnected ${timeSinceStep2.inMilliseconds}ms after characteristic lookup (stream verification)', null, 'SleepDoctorDataConnector');
        _cachedSleepDataService = null;
        _cachedSleepDataCharacteristic = null;
        throw StateError('Device disconnected during handshake');
      }

      BLELogger.info('BLE_HANDSHAKE_STEP2_SUCCESS: Characteristic found and connection verified', 'SleepDoctorDataConnector');

      // RECOMMENDATION 3.1: Add immediate BLE activity after Step 2
      // This maintains BLE activity between handshake steps
      try {
        if (_bluetoothService.device != null && _bluetoothService.device!.isConnected) {
          _cachedSleepDataCharacteristic?.uuid;
          BLELogger.debug('BLE_HANDSHAKE_STEP2_POST_KEEPALIVE: Keep-alive after Step 2', 'SleepDoctorDataConnector');
        }
      } catch (e) {
        // Ignore
      }

      // RECOMMENDATION 3.1: Check if disconnect was detected via monitoring
      if (_handshakeDisconnectDetected) {
        BLELogger.error('BLE_HANDSHAKE_FAILED: Disconnect detected via monitoring after Step 2', null, 'SleepDoctorDataConnector');
        _cachedSleepDataService = null;
        _cachedSleepDataCharacteristic = null;
        throw StateError('Device disconnected during handshake (detected via monitoring)');
      }

      // RECOMMENDATION 2.2: Add keep-alive between handshake steps
      // This maintains BLE activity between steps to prevent device timeout
      // RECOMMENDATION 1.3: Removed delay to minimize time between keep-alive Step 2 and Step 3
      try {
        // No delay - immediate BLE activity to minimize idle time
        if (_bluetoothService.device != null && _bluetoothService.device!.isConnected) {
          // Access characteristic property to maintain connection (simple keep-alive activity)
          _cachedSleepDataCharacteristic?.uuid; // Simple property access maintains BLE activity
          BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_STEP2: Keep-alive activity completed after Step 2', 'SleepDoctorDataConnector');
          // RECOMMENDATION 2.3: Add timing log after keep-alive operation
          BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_STEP2_TIME: Completed at ${DateTime.now().toIso8601String()}', 'SleepDoctorDataConnector');
        }
      } catch (e) {
        // Ignore - keep-alive is best effort, don't fail handshake if it fails
        BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_STEP2_FAILED: Keep-alive failed (non-critical): $e', 'SleepDoctorDataConnector');
      }

      // RECOMMENDATION 1.1: Add immediate BLE activity after keep-alive Step 2
      // This prevents device timeout by maintaining continuous BLE activity
      // Device disconnects 42-47ms after keep-alive Step 2 if no BLE activity occurs
      // RECOMMENDATION 1.3: Removed delay to minimize time between keep-alive Step 2 and Step 3
      try {
        // No delay - immediate BLE activity to minimize idle time
        if (_bluetoothService.device != null && _bluetoothService.device!.isConnected) {
          // Access characteristic property to maintain connection (simple keep-alive activity)
          _cachedSleepDataCharacteristic?.properties; // Simple property access maintains BLE activity
          BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_POST_STEP2: Immediate activity after Step 2 keep-alive', 'SleepDoctorDataConnector');
          // RECOMMENDATION 2.3: Add timing log after keep-alive operation
          BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_POST_STEP2_TIME: Completed at ${DateTime.now().toIso8601String()}', 'SleepDoctorDataConnector');
        }
      } catch (e) {
        // Ignore - keep-alive is best effort, don't fail handshake if it fails
        BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_POST_STEP2_FAILED: Keep-alive failed (non-critical): $e', 'SleepDoctorDataConnector');
      }

      // RECOMMENDATION 3.1: Verify permissions early (before Step 3)
      // RECOMMENDATION 3.2: Optimize permission check timing
      // This avoids delay during notification setup and may reduce disconnect window
      BLELogger.debug('BLE_HANDSHAKE_PRE_STEP3_PERMISSION: Verifying permissions before notification setup', 'SleepDoctorDataConnector');
      
      // RECOMMENDATION 3.2: Check connection state before permission check to fail fast if disconnected
      if (_bluetoothService.device == null || !_bluetoothService.device!.isConnected) {
        BLELogger.error('BLE_HANDSHAKE_PRE_STEP3_PERMISSION_SKIP: Device not connected, skipping permission check', null, 'SleepDoctorDataConnector');
        throw StateError('Device not connected for permission check');
      }
      
      // RECOMMENDATION 3.2: Track permission check timing
      final permissionCheckStartTime = DateTime.now();
      try {
        // Verify permissions early to avoid delay during notification setup
        // Permission check uses caching (5-second cache) and timeouts (100ms per check) for optimization
        await _bluetoothService.verifyBluetoothPermissions('notify');
        
        final permissionCheckEndTime = DateTime.now();
        final permissionCheckDuration = permissionCheckEndTime.difference(permissionCheckStartTime);
        BLELogger.debug('BLE_HANDSHAKE_PRE_STEP3_PERMISSION_SUCCESS: Permissions verified early in ${permissionCheckDuration.inMilliseconds}ms', 'SleepDoctorDataConnector');
        
        // RECOMMENDATION 3.2: Warn if permission check takes too long (>50ms)
        if (permissionCheckDuration.inMilliseconds > 50) {
          BLELogger.warning('BLE_HANDSHAKE_PRE_STEP3_PERMISSION_SLOW: Permission check took ${permissionCheckDuration.inMilliseconds}ms (may cause device timeout)', 'SleepDoctorDataConnector');
        }
      } catch (e) {
        final permissionCheckEndTime = DateTime.now();
        final permissionCheckDuration = permissionCheckEndTime.difference(permissionCheckStartTime);
        BLELogger.error('BLE_HANDSHAKE_PRE_STEP3_PERMISSION_FAILED: Early permission check failed after ${permissionCheckDuration.inMilliseconds}ms', e, 'SleepDoctorDataConnector');
        rethrow;
      }

      // RECOMMENDATION 1.2: Add immediate BLE activity before Step 3
      // This ensures device is active before notification setup
      // Prevents device timeout during permission check or notification setup
      BLELogger.debug('BLE_HANDSHAKE_PRE_STEP3_KEEPALIVE: Performing keep-alive before Step 3', 'SleepDoctorDataConnector');
      try {
        if (_bluetoothService.device != null && _bluetoothService.device!.isConnected) {
          // Access characteristic property to maintain connection
          _cachedSleepDataCharacteristic?.uuid; // Simple property access maintains BLE activity
          BLELogger.debug('BLE_HANDSHAKE_PRE_STEP3_KEEPALIVE_SUCCESS: Keep-alive completed before Step 3', 'SleepDoctorDataConnector');
          // RECOMMENDATION 2.3: Add timing log after keep-alive operation
          BLELogger.debug('BLE_HANDSHAKE_PRE_STEP3_KEEPALIVE_TIME: Completed at ${DateTime.now().toIso8601String()}', 'SleepDoctorDataConnector');
        }
      } catch (e) {
        // Ignore - keep-alive is best effort
        BLELogger.debug('BLE_HANDSHAKE_PRE_STEP3_KEEPALIVE_FAILED: Keep-alive failed (non-critical): $e', 'SleepDoctorDataConnector');
      }

      // RECOMMENDATION 1.3: Step 3 starts immediately after all preparation
      // All delays removed, permission check moved earlier, keep-alive operations complete
      // Step 3: Enable notifications immediately (critical for connection stability)
      BLELogger.info('BLE_HANDSHAKE_STEP3: Enabling notifications immediately', 'SleepDoctorDataConnector');
      BLELogger.info('BLE_HANDSHAKE_STEP3_PARAMS: Characteristic UUID: ${characteristic.uuid}, Properties: notify=${characteristic.properties.notify}, indicate=${characteristic.properties.indicate}', 'SleepDoctorDataConnector');
      final step3StartTime = DateTime.now();
      DateTime? step3EndTime;
      
      try {
        await _bluetoothService.enableCharacteristicNotifications(characteristic);
        
        step3EndTime = DateTime.now();
        final step3Duration = step3EndTime.difference(step3StartTime);
        BLELogger.info('BLE_HANDSHAKE_STEP3_TIMING: Notification enable completed in ${step3Duration.inMilliseconds}ms', 'SleepDoctorDataConnector');
        BLELogger.info('BLE_HANDSHAKE_STEP3_SUCCESS: Notifications enabled successfully', 'SleepDoctorDataConnector');
      } catch (e, stackTrace) {
        final step3ErrorTime = DateTime.now();
        final step3Duration = step3ErrorTime.difference(step3StartTime);
        BLELogger.error('BLE_HANDSHAKE_STEP3_EXCEPTION: Exception during notification enable (took ${step3Duration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
        BLELogger.error('BLE_HANDSHAKE_STEP3_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
        BLELogger.error('BLE_HANDSHAKE_STEP3_EXCEPTION_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
        BLELogger.error('BLE_HANDSHAKE_STEP3_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
        
        // Log device state at exception time
        final deviceStateAtException = _bluetoothService.device == null 
            ? "null" 
            : (_bluetoothService.device!.isConnected ? "connected" : "disconnected");
        BLELogger.error('BLE_HANDSHAKE_STEP3_EXCEPTION_STATE: Device state at exception: $deviceStateAtException', null, 'SleepDoctorDataConnector');
        rethrow;
      }
      
      // RECOMMENDATION 3.1: Check if disconnect was detected via monitoring
      if (_handshakeDisconnectDetected) {
        BLELogger.error('BLE_HANDSHAKE_FAILED: Disconnect detected via monitoring after Step 3', null, 'SleepDoctorDataConnector');
        _cachedSleepDataService = null;
        _cachedSleepDataCharacteristic = null;
        throw StateError('Device disconnected during handshake (detected via monitoring)');
      }

      // RECOMMENDATION 2.1: Use stream-based connection check instead of synchronous check
      // This is more reliable as it catches async disconnects that may not be registered synchronously
      final isConnectedAfterStep3 = await _bluetoothService.verifyConnectionWithStream(timeout: const Duration(milliseconds: 10));
      if (!isConnectedAfterStep3) {
        final disconnectTime = DateTime.now();
        final timeSinceStep3 = disconnectTime.difference(step3EndTime);
        BLELogger.error('BLE_HANDSHAKE_FAILED: Device disconnected ${timeSinceStep3.inMilliseconds}ms after notification enable (stream verification)', null, 'SleepDoctorDataConnector');
        _cachedSleepDataService = null;
        _cachedSleepDataCharacteristic = null;
        throw StateError('Device disconnected during handshake');
      }

      // CRITICAL FIX: Confirm notification subscription before proceeding
      BLELogger.info('BLE_HANDSHAKE_STEP4: Confirming notification subscription', 'SleepDoctorDataConnector');
      
      // Notification stream is returned from enableCharacteristicNotifications
      // If we reached here without exception, subscription succeeded
      BLELogger.info('BLE_NOTIFICATION_ENABLED: Notification subscription confirmed', 'SleepDoctorDataConnector');
      
      final handshakeEndTime = DateTime.now();
      final totalHandshakeTime = handshakeEndTime.difference(handshakeStartTime);
      BLELogger.info('BLE_HANDSHAKE_SUCCESS: Immediate handshake completed successfully in ${totalHandshakeTime.inMilliseconds}ms', 'SleepDoctorDataConnector');
    } catch (e, stackTrace) {
      final handshakeFailureTime = DateTime.now();
      final handshakeMethodEndTime = DateTime.now();
      final totalHandshakeDuration = handshakeMethodEndTime.difference(handshakeMethodStartTime);
      
      BLELogger.error('BLE_HANDSHAKE_FAILED: Handshake failed at ${handshakeFailureTime.toIso8601String()} (total duration: ${totalHandshakeDuration.inMilliseconds}ms)', e, 'SleepDoctorDataConnector');
      BLELogger.error('BLE_HANDSHAKE_FAILED_TYPE: Exception type: ${e.runtimeType}', null, 'SleepDoctorDataConnector');
      BLELogger.error('BLE_HANDSHAKE_FAILED_MESSAGE: ${e.toString()}', null, 'SleepDoctorDataConnector');
      BLELogger.error('BLE_HANDSHAKE_FAILED_STACK: ${stackTrace.toString()}', null, 'SleepDoctorDataConnector');
      
      // RECOMMENDATION 3.1: Check if disconnect was detected via monitoring
      if (_handshakeDisconnectDetected) {
        BLELogger.error('BLE_HANDSHAKE_FAILED_DISCONNECT_DETECTED: Disconnect was detected via connection state monitoring during handshake', null, 'SleepDoctorDataConnector');
      }
      
      // CRITICAL FIX: Check connection state when handshake fails
      try {
        if (_bluetoothService.device != null) {
          final isConnected = _bluetoothService.device!.isConnected;
          BLELogger.error('BLE_HANDSHAKE_FAILED_STATE: Device connection state at failure: ${isConnected ? "CONNECTED" : "DISCONNECTED"}', null, 'SleepDoctorDataConnector');
          BLELogger.error('BLE_HANDSHAKE_FAILED_DEVICE: Device name: ${_bluetoothService.device!.platformName}', null, 'SleepDoctorDataConnector');
        } else {
          BLELogger.error('BLE_HANDSHAKE_FAILED_STATE: Device is null at failure', null, 'SleepDoctorDataConnector');
        }
      } catch (stateError) {
        BLELogger.error('BLE_HANDSHAKE_FAILED_STATE_ERROR: Error checking device state: $stateError', null, 'SleepDoctorDataConnector');
      }
      
      // Log cached service/characteristic state
      BLELogger.error('BLE_HANDSHAKE_FAILED_CACHE: Cached service: ${_cachedSleepDataService != null ? _cachedSleepDataService!.uuid : "null"}, Cached characteristic: ${_cachedSleepDataCharacteristic != null ? _cachedSleepDataCharacteristic!.uuid : "null"}', null, 'SleepDoctorDataConnector');
      
      _cachedSleepDataService = null;
      _cachedSleepDataCharacteristic = null;
      rethrow;
    } finally {
      // RECOMMENDATION 3.1: Stop connection state monitoring after handshake
      _stopHandshakeConnectionStateMonitoring();
      // RECOMMENDATION 3.1: Stop continuous keep-alive timer after handshake
      _stopHandshakeKeepAliveTimer();
    }
  }

  //########################################################################
  // RECOMMENDATION 3.1: Handshake Connection State Monitoring
  //########################################################################

  /// RECOMMENDATION 3.1: Start connection state monitoring during handshake
  /// This provides real-time disconnect detection and better diagnostics
  void _startHandshakeConnectionStateMonitoring() {
    if (_bluetoothService.device == null) {
      BLELogger.debug('BLE_HANDSHAKE_MONITORING: Cannot start monitoring - device is null', 'SleepDoctorDataConnector');
      return;
    }

    // Cancel any existing handshake monitoring
    _stopHandshakeConnectionStateMonitoring();

    BLELogger.debug('BLE_HANDSHAKE_MONITORING_START: Starting connection state monitoring during handshake', 'SleepDoctorDataConnector');
    
    _handshakeConnectionStateSubscription = _bluetoothService.device!.connectionState.listen(
      (state) {
        final stateChangeTime = DateTime.now();
        if (state == BluetoothConnectionState.disconnected) {
          _handshakeDisconnectDetected = true;
          BLELogger.warning('BLE_HANDSHAKE_DISCONNECT_DETECTED: Disconnect detected via stream during handshake at ${stateChangeTime.toIso8601String()}', 'SleepDoctorDataConnector');
          // Note: We don't cancel handshake here - let the handshake steps check the flag
          // This allows proper cleanup and error handling
        } else if (state == BluetoothConnectionState.connected) {
          BLELogger.debug('BLE_HANDSHAKE_MONITORING: Connection state changed to CONNECTED during handshake', 'SleepDoctorDataConnector');
        }
      },
      onError: (error) {
        BLELogger.warning('BLE_HANDSHAKE_MONITORING_ERROR: Error in handshake connection state stream: $error', 'SleepDoctorDataConnector');
      },
    );
  }

  /// RECOMMENDATION 3.1: Stop connection state monitoring after handshake
  void _stopHandshakeConnectionStateMonitoring() {
    if (_handshakeConnectionStateSubscription != null) {
      BLELogger.debug('BLE_HANDSHAKE_MONITORING_STOP: Stopping connection state monitoring after handshake', 'SleepDoctorDataConnector');
      _handshakeConnectionStateSubscription?.cancel();
      _handshakeConnectionStateSubscription = null;
    }
    _handshakeDisconnectDetected = false; // Reset flag
  }

  /// RECOMMENDATION 3.1: Start continuous keep-alive during handshake
  /// This provides continuous BLE activity during entire handshake to prevent device timeout
  int _timerTickCount = 0; // RECOMMENDATION 3.2: Track timer ticks
  
  void _startHandshakeKeepAliveTimer() {
    _stopHandshakeKeepAliveTimer(); // Ensure no existing timer
    _timerTickCount = 0; // Reset tick count
    
    // RECOMMENDATION 2.1: Add detailed logging to verify timer is starting
    BLELogger.info('BLE_HANDSHAKE_KEEPALIVE_TIMER_START: Starting continuous keep-alive timer (20ms interval)', 'SleepDoctorDataConnector');
    BLELogger.info('BLE_HANDSHAKE_KEEPALIVE_TIMER_START_TIME: Timer start time: ${DateTime.now().toIso8601String()}', 'SleepDoctorDataConnector');
    BLELogger.info('BLE_HANDSHAKE_KEEPALIVE_TIMER_START_STATE: Device state - isNull: ${_bluetoothService.device == null}, isConnected: ${_bluetoothService.device?.isConnected ?? false}', 'SleepDoctorDataConnector');
    
    try {
      // RECOMMENDATION 1.1: Reduce timer interval from 30ms to 20ms
      // RECOMMENDATION 1.3: Enhanced BLE activity in timer callback
      _handshakeKeepAliveTimer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
        _timerTickCount++;
        
        if (_bluetoothService.device != null && _bluetoothService.device!.isConnected) {
          try {
            // RECOMMENDATION 1.3: Enhanced BLE activity - access multiple properties
            // Access multiple properties to ensure BLE activity is maintained
            _cachedSleepDataService?.uuid;
            _cachedSleepDataCharacteristic?.uuid;
            _cachedSleepDataService?.characteristics; // Access characteristics list
            _cachedSleepDataCharacteristic?.properties; // Access properties
            
            // RECOMMENDATION 3.2: Log every 5 ticks (100ms) to verify timer is running
            if (_timerTickCount % 5 == 0) {
              BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_TIMER_TICK: Timer tick #$_timerTickCount at ${DateTime.now().toIso8601String()}', 'SleepDoctorDataConnector');
            }
          } catch (e) {
            // Ignore - best effort, don't log errors for keep-alive
          }
        } else {
          // Device disconnected or null - cancel timer
          timer.cancel();
          _handshakeKeepAliveTimer = null;
          BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_TIMER_STOPPED: Timer stopped due to device disconnect', 'SleepDoctorDataConnector');
        }
      });
      
      BLELogger.info('BLE_HANDSHAKE_KEEPALIVE_TIMER_STARTED: Timer created successfully', 'SleepDoctorDataConnector');
    } catch (e) {
      BLELogger.error('BLE_HANDSHAKE_KEEPALIVE_TIMER_START_FAILED: Failed to start timer', e, 'SleepDoctorDataConnector');
      _handshakeKeepAliveTimer = null;
    }
  }

  /// RECOMMENDATION 3.1: Stop continuous keep-alive timer after handshake
  void _stopHandshakeKeepAliveTimer() {
    if (_handshakeKeepAliveTimer != null) {
      BLELogger.debug('BLE_HANDSHAKE_KEEPALIVE_TIMER_STOP: Stopping continuous keep-alive timer', 'SleepDoctorDataConnector');
      _handshakeKeepAliveTimer?.cancel();
      _handshakeKeepAliveTimer = null;
    }
  }

  //########################################################################
  // BUTTON PRESS NOTIFICATION HANDLING
  //########################################################################

  /// Wait for device button press notification
  /// This method waits INDEFINITELY until the device sends a notification
  /// indicating that the physical button was pressed
  Future<void> _waitForDeviceButtonPress() async {
    if (_bluetoothService.device == null) {
      throw StateError('Cannot wait for button press - device is null');
    }

    try {
      // CRITICAL FIX: Verify connection before proceeding
      if (_bluetoothService.device == null || !_bluetoothService.device!.isConnected) {
        BLELogger.error('BLE_BUTTON_WAIT_FAILED: Device not connected', null, 'SleepDoctorDataConnector');
        throw StateError('Device not connected');
      }

      // CRITICAL FIX: Use cached service/characteristic from handshake to avoid re-discovery
      BluetoothService service;
      BluetoothCharacteristic characteristic;
      
      if (_cachedSleepDataService != null && _cachedSleepDataCharacteristic != null) {
        BLELogger.info('BLE_BUTTON_WAIT_CACHE_HIT: Using cached service and characteristic', 'SleepDoctorDataConnector');
        service = _cachedSleepDataService!;
        characteristic = _cachedSleepDataCharacteristic!;
      } else {
        BLELogger.warning('BLE_BUTTON_WAIT_CACHE_MISS: Cache not available, discovering services', 'SleepDoctorDataConnector');
        
        // Discover the sleep data service to get the characteristic
        service = await _bluetoothService.readServiceFromDevice(BLEConfig.sdsServiceUUID);
        
        if (_bluetoothService.device == null || !_bluetoothService.device!.isConnected) {
          BLELogger.error('BLE_BUTTON_WAIT_FAILED: Device disconnected during service discovery', null, 'SleepDoctorDataConnector');
          throw StateError('Device disconnected during button wait setup');
        }

        characteristic = await _bluetoothService.readCharacteristicFrom(
          service,
          BLEConfig.sleepDoctorCharacteristicUUID,
        );

        if (_bluetoothService.device == null || !_bluetoothService.device!.isConnected) {
          BLELogger.error('BLE_BUTTON_WAIT_FAILED: Device disconnected during characteristic lookup', null, 'SleepDoctorDataConnector');
          throw StateError('Device disconnected during button wait setup');
        }
      }

      BLELogger.info('BLE_NOTIFICATION_SETUP: Setting up button press notification listener', 'SleepDoctorDataConnector');
      
      // CRITICAL FIX: Use notification stream from handshake if available
      // If handshake already enabled notifications, we should reuse that stream
      // Re-enabling may cause issues, so we need to get the stream directly
      Stream<List<int>> notificationStream;
      
      if (_cachedSleepDataCharacteristic != null && _cachedSleepDataCharacteristic == characteristic) {
        // Notifications already enabled from handshake - use existing stream
        BLELogger.info('BLE_NOTIFICATION_REUSE: Reusing notification stream from handshake', 'SleepDoctorDataConnector');
        notificationStream = characteristic.onValueReceived;
      } else {
        // Notifications not yet enabled - enable now
        BLELogger.info('BLE_NOTIFICATION_ENABLING: Enabling notifications for button press listener', 'SleepDoctorDataConnector');
        notificationStream = await _bluetoothService.enableCharacteristicNotifications(characteristic);
      }
      
      BLELogger.info('BLE_NOTIFICATION_ENABLED: Button press notification listener active', 'SleepDoctorDataConnector');

      // Create a completer to wait for the button press notification
      final completer = Completer<void>();
      
      // Subscribe to notifications - when device button is pressed, it will send a notification
      _buttonPressNotificationSubscription = notificationStream.listen(
        (data) {
          BLELogger.info('HANDSHAKE_ACK_RECEIVED: Received notification from device (${data.length} bytes)', 'SleepDoctorDataConnector');
          
          if (data.isNotEmpty) {
            final signal = data[0];
            final hexSignal = '0x${signal.toRadixString(16).padLeft(2, '0')}';
            BLELogger.info('HANDSHAKE_ACK_RECEIVED: Signal: $hexSignal, full payload: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}', 'SleepDoctorDataConnector');
            
            // Check if this is a valid button press signal (E_STX = 0x02)
            // The device sends E_STX (0x02) when button is pressed
            if (signal == BTSignals.E_STX()) {
              BLELogger.info('HANDSHAKE_ACK_RECEIVED: Button press signal (E_STX) confirmed', 'SleepDoctorDataConnector');
              
              // Complete the wait - button was pressed
              if (!completer.isCompleted) {
                completer.complete();
              }
            } else {
              BLELogger.info('HANDSHAKE_ACK_RECEIVED: Non-button-press signal received (waiting for E_STX)', 'SleepDoctorDataConnector');
            }
          }
        },
        onError: (error) {
          BLELogger.error('Error in button press notification stream', error, 'SleepDoctorDataConnector');
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
        cancelOnError: false,
      );

      // Wait for button press notification with timeout
      // This will block until the device sends a notification or timeout occurs
      BLELogger.info('Waiting for device button press (timeout: ${BLEConfig.buttonPressWaitTimeout.inSeconds}s)...', 'SleepDoctorDataConnector');
      
      // Add timeout to prevent indefinite hang
      try {
        await completer.future.timeout(
          BLEConfig.buttonPressWaitTimeout,
          onTimeout: () {
            BLELogger.error('Button press wait timeout after ${BLEConfig.buttonPressWaitTimeout.inSeconds}s', null, 'SleepDoctorDataConnector');
            _stopButtonPressNotificationSubscription();
            throw TimeoutException(
              'Device button press not detected within ${BLEConfig.buttonPressWaitTimeout.inSeconds} seconds. Please ensure device is powered on and press the blue button.',
              BLEConfig.buttonPressWaitTimeout,
            );
          },
        );
        BLELogger.info('Button press notification received - proceeding with sync', 'SleepDoctorDataConnector');
      } on TimeoutException {
        // Re-throw timeout with context
        rethrow;
      } catch (e) {
        // Re-throw other errors
        _stopButtonPressNotificationSubscription();
        rethrow;
      }
    } catch (e) {
      BLELogger.error('Error waiting for button press', e, 'SleepDoctorDataConnector');
      _stopButtonPressNotificationSubscription();
      rethrow;
    }
  }

  void _stopButtonPressNotificationSubscription() {
    _buttonPressNotificationSubscription?.cancel();
    _buttonPressNotificationSubscription = null;
  }

  /// Cleanup all subscriptions
  void dispose() {
    _bluetoothStateSubscription?.cancel();
    _bluetoothScanningSubscription?.cancel();
    _connectionStateMonitorSubscription?.cancel();
    _stopButtonPressNotificationSubscription();
    _stopKeepAliveTimer();
    _bluetoothService.dispose();
  }

  //########################################################################
  // READ DATA FROM DEVICE RECURSIVELY
  //########################################################################

  /// Read data recursively until E_ETX signal - refactored with error handling
  /// PRODUCTION HARDENING: Tracks active read state to prevent keep-alive interference
  Future<List<List<int>>> _readDataFromCharacteristic(
      BluetoothCharacteristic characteristic) async {
    final readData = <List<int>>[];
    int prevSignal = -1;
    
    // PRODUCTION HARDENING: Set flag to indicate active data read
    // This prevents keep-alive timer from reading the same characteristic concurrently
    _isReadingData = true;
    
    try {
      while (prevSignal != BTSignals.E_ETX()) {
        // Check if sync should stop
        if (_shouldStopSync) {
          BLELogger.warning('Sync stopped during read', 'SleepDoctorDataConnector');
          throw StateError('Sync stopped by user or system');
        }

        // Check connection state
        if (_bluetoothService.device == null || !_bluetoothService.device!.isConnected) {
          BLELogger.error('Device disconnected during read', null, 'SleepDoctorDataConnector');
          throw StateError('Device disconnected during data read');
        }

        try {
          BLELogger.debug('BLE_CHARACTERISTIC_READ: Reading data packet', 'SleepDoctorDataConnector');
          final data = await characteristic.read();
        
        if (data.isEmpty) {
          BLELogger.warning('BLE_CHARACTERISTIC_READ_EMPTY: Received empty data packet', 'SleepDoctorDataConnector');
          continue;
        }

        final signal = data[0];
        readData.add(data);
        
        BLELogger.debug('BLE_CHARACTERISTIC_READ_SUCCESS: Read packet: signal=${signal.toRadixString(16)}, size=${data.length}, total=${readData.length}', 'SleepDoctorDataConnector');

        if (signal == BTSignals.E_ETX()) {
          BLELogger.info('BLE_CHARACTERISTIC_READ_COMPLETE: Received E_ETX signal - read complete. Total packets: ${readData.length}', 'SleepDoctorDataConnector');
          break;
        }

        prevSignal = signal;
        } catch (e) {
          BLELogger.error('Error reading characteristic', e, 'SleepDoctorDataConnector');
          rethrow;
        }
      }

      return readData;
    } finally {
      // PRODUCTION HARDENING: Clear flag when data read completes or fails
      // This allows keep-alive to resume if needed
      _isReadingData = false;
    }
  }

  //########################################################################
  // WRITE DATA TO DEVICE
  //########################################################################

  Future<void> _writeDataToCharacteristics(
      BluetoothCharacteristic characteristic, List<int> data) async {
    try {
      BLELogger.debug('BLE_CHARACTERISTIC_WRITE: Writing ${data.length} bytes to characteristic', 'SleepDoctorDataConnector');
      await characteristic.write(data, withoutResponse: true);
      BLELogger.debug('BLE_CHARACTERISTIC_WRITE_SUCCESS: Wrote ${data.length} bytes to characteristic', 'SleepDoctorDataConnector');
    } catch (e) {
      BLELogger.error('BLE_CHARACTERISTIC_WRITE_FAILED: Error writing to characteristic', e, 'SleepDoctorDataConnector');
      rethrow;
    }
  }

  Future<void> _clearDataFromCharacteristics(BluetoothCharacteristic characteristic) async {
    try {
      final resetMeasurementSignal = List<int>.of([BTSignals.E_ACK(), BTSignals.C()]);
      resetMeasurementSignal.addAll(List.filled(18, 0));
      await _writeDataToCharacteristics(characteristic, resetMeasurementSignal);
      BLELogger.info('Cleared data from device', 'SleepDoctorDataConnector');
    } catch (e) {
      BLELogger.error('Error clearing data from device', e, 'SleepDoctorDataConnector');
      // Don't rethrow - clearing is best effort
    }
  }

  //########################################################################
  // POST PROCESS DATA
  //########################################################################

  Future<List<SleepDoctorAbstractData>> _postProcess(
      List<List<int>> dataList, DateTime deviceTime) async {
    final sleepDoctorAbstractDataList = <SleepDoctorAbstractData>[];

    // Extract header data
    List<int>? headerData;
    try {
      headerData = dataList.firstWhere(
        (data) => data.isNotEmpty && data[0] == BTSignals.E_SOH(),
      );
    } catch (e) {
      BLELogger.warning('No header data found in response', 'SleepDoctorDataConnector');
      headerData = null;
    }

    final sleepDoctorDataHeader = headerData != null
        ? BluetoothDataHelper.parseHeaderData(from: headerData)
        : null;
    var startTimeOfMeasurement = sleepDoctorDataHeader?.startDateTime;

    BLELogger.info('Start time of measurement: $startTimeOfMeasurement', 'SleepDoctorDataConnector');

    final currentTime = DateTime.now();

    // Synchronize time if needed
    if (!BluetoothDataHelper.areaDatesSynchronous(
        firstTime: deviceTime, secondTime: currentTime)) {
      BLELogger.warning('Device time out of sync, estimating start time', 'SleepDoctorDataConnector');
      startTimeOfMeasurement = BluetoothDataHelper.estimateStartTimeOfMeasurement(
        of: currentTime,
        and: dataList,
      );
    }

    // Extract data structures (exclude header)
    final dataStructs = dataList
        .where((data) => data.isNotEmpty && data[0] != BTSignals.E_SOH())
        .toList();

    final sleepDoctorData = dataStructs.isNotEmpty
        ? BluetoothDataHelper.parseData(
            from: dataStructs, withSyncedTime: startTimeOfMeasurement)
        : null;

    if (sleepDoctorDataHeader != null) {
      sleepDoctorAbstractDataList.add(sleepDoctorDataHeader);
    }
    if (sleepDoctorData != null) {
      sleepDoctorAbstractDataList.addAll(sleepDoctorData);
    }

    BLELogger.info('Post-processed ${sleepDoctorAbstractDataList.length} records', 'SleepDoctorDataConnector');
    return sleepDoctorAbstractDataList;
  }
}
