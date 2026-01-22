import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:iptasys_sleep_doctor_flutter/models/bluetooth_device_info.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/ble_config.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/ble_logger.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothConnector {
  BluetoothDevice? device;
  StreamSubscription<List<ScanResult>>? deviceScanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  
  // CRITICAL FIX: Cache discovered services to avoid re-discovery
  List<BluetoothService>? _cachedServices;
  bool _servicesDiscovered = false;

  // RECOMMENDATION 2.1: Cache permission status to avoid re-verification
  bool? _cachedScanPermission;
  bool? _cachedConnectPermission;
  DateTime? _permissionCacheTime;

  BluetoothConnector();

  //########################################################################
  //SCANNING FOR DEVICE
  //########################################################################

  /// Scan for devices - waits indefinitely until device is found
  /// CRITICAL: No timeout-based auto-completion to prevent auto-starting sync
  Future<BTDeviceInfo> scanForDevicesWith(List<String> deviceNames, {int retryCount = 0}) async {
    BLELogger.info('BLE_SCAN_STARTED: Searching for devices: $deviceNames', 'BluetoothConnector');
    
    // CRITICAL FIX: Verify permissions immediately before scan (SDK 36 requirement)
    await _verifyBluetoothPermissions('scan');
    
    try {
      // Cancel any existing scan subscription
      await deviceScanSubscription?.cancel();
      
      // Start scan with a long timeout (but we won't use it to auto-complete)
      // The timeout is just for FlutterBluePlus internal use
      await FlutterBluePlus.startScan(timeout: const Duration(minutes: 10));
      BLELogger.info('BLE_SCAN_STARTED: Scan initiated successfully', 'BluetoothConnector');

      final completer = Completer<BTDeviceInfo>();
      bool deviceFound = false;

      deviceScanSubscription = FlutterBluePlus.scanResults.listen(
        (results) async {
          if (deviceFound) return; // Prevent multiple completions
          
          for (ScanResult scanResult in results) {
            try {
              // PRODUCTION HARDENING: Safe device name access to prevent OEM crashes
              // Some OEM BLE implementations may have issues with device name access
              final deviceName = scanResult.device.platformName;
              if (deviceName.isEmpty) {
                BLELogger.debug('Skipping device with empty name', 'BluetoothConnector');
                continue;
              }
              
              final isMatch = deviceNames.any((name) => deviceName == name);

              if (isMatch) {
                // PRODUCTION HARDENING: Make scan completion atomic to prevent race conditions
                // Set flag and complete completer BEFORE stopping scan
                // This ensures completer always completes even if stopScanning() fails
                deviceFound = true;
                BLELogger.info('BLE_DEVICE_FOUND: $deviceName (RSSI: ${scanResult.rssi})', 'BluetoothConnector');
                device = scanResult.device;
                
                // PRODUCTION HARDENING: Null-safe platformName access
                final finalDeviceName = device?.platformName ?? deviceName;
                
                // Complete completer first (atomic operation)
                if (!completer.isCompleted) {
                  completer.complete(BTDeviceInfo(
                    deviceName: finalDeviceName,
                    rssi: scanResult.rssi,
                  ));
                }
                
                // Then stop scanning (best effort - don't await to prevent blocking)
                // If stopScanning fails, completer is already completed, so no deadlock
                stopScanning().catchError((error) {
                  BLELogger.warning('Error stopping scan after device found (non-critical)', 'BluetoothConnector');
                });
                
                break;
              }
            } catch (e) {
              // PRODUCTION HARDENING: Catch and log any exceptions from scan result processing
              // Prevents scan crashes from propagating and killing the sync
              BLELogger.warning('Error processing scan result (skipping): $e', 'BluetoothConnector');
              continue; // Skip this result and continue scanning
            }
          }
        },
        onError: (error) {
          BLELogger.error('BLE_SCAN_ERROR: Scan error occurred', error, 'BluetoothConnector');
          stopScanning(); // Don't await in callback
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
        cancelOnError: false,
      );

      // CRITICAL FIX: NO TIMEOUT-BASED AUTO-COMPLETION
      // The scan will continue indefinitely until:
      // 1. Device is found (completer.complete() called above)
      // 2. User cancels (stopScanning() called externally)
      // 3. Error occurs (completer.completeError() called above)
      //
      // This prevents the regression where sync would auto-start after 20-30 seconds
      // The original behavior was to wait indefinitely for device to appear

      return completer.future;
    } catch (e) {
      BLELogger.error('Scan failed', e, 'BluetoothConnector');
      await stopScanning();
      rethrow;
    }
  }

  Future<void> stopScanning() async {
    try {
      await deviceScanSubscription?.cancel();
      deviceScanSubscription = null;
      await FlutterBluePlus.stopScan();
      BLELogger.info('BLE_SCAN_STOPPED: Scanning stopped', 'BluetoothConnector');
    } catch (e) {
      BLELogger.warning('BLE_SCAN_STOP_ERROR: Error stopping scan', 'BluetoothConnector');
      // Don't rethrow - best effort cleanup
    }
  }
  
  /// Clean up all subscriptions
  void dispose() {
    deviceScanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    deviceScanSubscription = null;
    _connectionStateSubscription = null;
    _adapterStateSubscription = null;
    _cachedServices = null;
    _servicesDiscovered = false;
  }
  
  /// Clear service cache (call on disconnect)
  void _clearServiceCache() {
    _cachedServices = null;
    _servicesDiscovered = false;
  }

  //########################################################################
  //STATES
  //########################################################################

  Stream<bool> isScanning() {
    return FlutterBluePlus.isScanning;
  }

  Stream<BluetoothAdapterState> bluetoothState() {
    return FlutterBluePlus.adapterState;
  }
  
  /// Get current adapter state synchronously
  Future<BluetoothAdapterState> getCurrentAdapterState() async {
    return await FlutterBluePlus.adapterState.first;
  }

  Future<bool> isConnected() async {
    var connectedDevices = FlutterBluePlus.connectedDevices;
    return connectedDevices.isNotEmpty;
  }

  Future<bool> _isAbleToConnectToDevice() async {
    if (device == null) {
      return false;
    }

    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  Future<bool> _isAbleToDiscoverDevice() async {
    if (device == null) {
      return false;
    }
    return device!.isConnected;
  }

  /// RECOMMENDATION 2.2: Verify connection using connection state stream
  /// This is more reliable than synchronous check as it catches async disconnects
  /// Returns true if connected and no disconnect detected within timeout period
  Future<bool> _verifyConnectionWithStream({Duration timeout = const Duration(milliseconds: 10)}) async {
    if (device == null) {
      BLELogger.debug('BLE_CONNECTION_STREAM_VERIFY: Device is null', 'BluetoothConnector');
      return false;
    }

    try {
      // Get current connection state
      final currentState = await device!.connectionState.first.timeout(
        const Duration(milliseconds: 100),
        onTimeout: () {
          BLELogger.warning('BLE_CONNECTION_STREAM_VERIFY: Timeout getting current state', 'BluetoothConnector');
          return BluetoothConnectionState.disconnected;
        },
      );

      if (currentState != BluetoothConnectionState.connected) {
        BLELogger.debug('BLE_CONNECTION_STREAM_VERIFY: Current state is not connected: $currentState', 'BluetoothConnector');
        return false;
      }

      // Listen for state changes with timeout to catch async disconnects
      final completer = Completer<bool>();
      StreamSubscription<BluetoothConnectionState>? subscription;
      Timer? timeoutTimer;

      subscription = device!.connectionState.listen(
        (state) {
          if (state == BluetoothConnectionState.disconnected) {
            BLELogger.debug('BLE_CONNECTION_STREAM_VERIFY: Disconnect detected via stream', 'BluetoothConnector');
            if (!completer.isCompleted) {
              completer.complete(false);
            }
            subscription?.cancel();
            timeoutTimer?.cancel();
          }
        },
        onError: (error) {
          BLELogger.warning('BLE_CONNECTION_STREAM_VERIFY: Stream error: $error', 'BluetoothConnector');
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          subscription?.cancel();
          timeoutTimer?.cancel();
        },
      );

      // Set timeout - if no disconnect detected within timeout, assume still connected
      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          BLELogger.debug('BLE_CONNECTION_STREAM_VERIFY: No disconnect detected within ${timeout.inMilliseconds}ms, connection verified', 'BluetoothConnector');
          completer.complete(true);
        }
        subscription?.cancel();
      });

      final result = await completer.future;
      subscription.cancel();
      timeoutTimer.cancel();

      return result;
    } catch (e) {
      BLELogger.warning('BLE_CONNECTION_STREAM_VERIFY: Error during stream verification: $e', 'BluetoothConnector');
      // Fallback to synchronous check on error
      try {
        return device != null && device!.isConnected;
      } catch (_) {
        return false;
      }
    }
  }

  //########################################################################
  //CONNECTIONS
  //########################################################################

  /// Connect to device with timeout and retry logic
  Future<bool> connectToDevice({int retryCount = 0}) async {
    final methodStartTime = DateTime.now();
    BLELogger.info('CONNECT_METHOD_ENTRY: connectToDevice() called at ${methodStartTime.toIso8601String()}', 'BluetoothConnector');
    BLELogger.info('CONNECT_METHOD_PARAMS: retryCount: $retryCount', 'BluetoothConnector');
    BLELogger.info('CONNECT_METHOD_DEVICE_STATE: Device state - isNull: ${device == null}', 'BluetoothConnector');
    
    if (device == null) {
      BLELogger.error('CONNECT_METHOD_FAILED: Cannot connect: device is null', null, 'BluetoothConnector');
      return false;
    }

    final adapterCheckStartTime = DateTime.now();
    try {
      if (!await _isAbleToConnectToDevice()) {
        final adapterCheckEndTime = DateTime.now();
        final adapterCheckDuration = adapterCheckEndTime.difference(adapterCheckStartTime);
        BLELogger.warning('CONNECT_METHOD_ADAPTER_OFF: Bluetooth adapter is not ON (check took ${adapterCheckDuration.inMilliseconds}ms)', 'BluetoothConnector');
        return false;
      }
      final adapterCheckEndTime = DateTime.now();
      final adapterCheckDuration = adapterCheckEndTime.difference(adapterCheckStartTime);
      BLELogger.debug('CONNECT_METHOD_ADAPTER_CHECK: Adapter check completed in ${adapterCheckDuration.inMilliseconds}ms', 'BluetoothConnector');
    } catch (e, stackTrace) {
      final adapterCheckErrorTime = DateTime.now();
      final adapterCheckDuration = adapterCheckErrorTime.difference(adapterCheckStartTime);
      BLELogger.error('CONNECT_METHOD_ADAPTER_CHECK_EXCEPTION: Exception during adapter check (took ${adapterCheckDuration.inMilliseconds}ms)', e, 'BluetoothConnector');
      BLELogger.error('CONNECT_METHOD_ADAPTER_CHECK_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'BluetoothConnector');
      return false;
    }

    // CRITICAL FIX: Verify permissions immediately before connect (SDK 36 requirement)
    final permissionCheckStartTime = DateTime.now();
    try {
      await _verifyBluetoothPermissions('connect');
      final permissionCheckEndTime = DateTime.now();
      final permissionCheckDuration = permissionCheckEndTime.difference(permissionCheckStartTime);
      BLELogger.debug('CONNECT_METHOD_PERMISSION_CHECK: Permission check completed in ${permissionCheckDuration.inMilliseconds}ms', 'BluetoothConnector');
    } catch (e, stackTrace) {
      final permissionCheckErrorTime = DateTime.now();
      final permissionCheckDuration = permissionCheckErrorTime.difference(permissionCheckStartTime);
      BLELogger.error('CONNECT_METHOD_PERMISSION_CHECK_EXCEPTION: Exception during permission check (took ${permissionCheckDuration.inMilliseconds}ms)', e, 'BluetoothConnector');
      BLELogger.error('CONNECT_METHOD_PERMISSION_CHECK_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'BluetoothConnector');
      return false;
    }

    BLELogger.info('CONNECT_METHOD_ATTEMPT: Connecting to device: ${device!.platformName}', 'BluetoothConnector');
    BLELogger.info('CONNECT_METHOD_TIMEOUT: Connection timeout: ${BLEConfig.connectionTimeout.inSeconds}s', 'BluetoothConnector');
    
    try {
      // Set connection timeout
      final connectStartTime = DateTime.now();
      BLELogger.info('CONNECT_METHOD_CONNECT_START: Starting device.connect() at ${connectStartTime.toIso8601String()}', 'BluetoothConnector');
      
      try {
        await device!.connect(
          timeout: BLEConfig.connectionTimeout,
          autoConnect: false,
        ).timeout(
          BLEConfig.connectionTimeout,
          onTimeout: () {
            final timeoutTime = DateTime.now();
            final timeoutDuration = timeoutTime.difference(connectStartTime);
            BLELogger.warning('CONNECT_METHOD_TIMEOUT: Connection timeout after ${timeoutDuration.inMilliseconds}ms (${BLEConfig.connectionTimeout.inSeconds}s)', 'BluetoothConnector');
            throw TimeoutException('Connection timeout', BLEConfig.connectionTimeout);
          },
        );
        
        final connectEndTime = DateTime.now();
        final connectDuration = connectEndTime.difference(connectStartTime);
        BLELogger.info('CONNECT_METHOD_CONNECT_SUCCESS: device.connect() completed in ${connectDuration.inMilliseconds}ms', 'BluetoothConnector');
      } catch (e, stackTrace) {
        final connectErrorTime = DateTime.now();
        final connectDuration = connectErrorTime.difference(connectStartTime);
        BLELogger.error('CONNECT_METHOD_CONNECT_EXCEPTION: Exception during device.connect() (took ${connectDuration.inMilliseconds}ms)', e, 'BluetoothConnector');
        BLELogger.error('CONNECT_METHOD_CONNECT_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'BluetoothConnector');
        BLELogger.error('CONNECT_METHOD_CONNECT_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'BluetoothConnector');
        rethrow;
      }
      
      // Verify connection
      final verifyStartTime = DateTime.now();
      BLELogger.debug('CONNECT_METHOD_VERIFY: Waiting 500ms for connection to establish', 'BluetoothConnector');
      await Future.delayed(const Duration(milliseconds: 500)); // Give time for connection to establish
      
      final verifyCheckTime = DateTime.now();
      final verifyWaitDuration = verifyCheckTime.difference(verifyStartTime);
      BLELogger.debug('CONNECT_METHOD_VERIFY_WAIT: Verification wait completed in ${verifyWaitDuration.inMilliseconds}ms', 'BluetoothConnector');
      
      try {
        if (device!.isConnected) {
          final verifyEndTime = DateTime.now();
          final verifyDuration = verifyEndTime.difference(verifyStartTime);
          BLELogger.info('CONNECT_METHOD_VERIFY_SUCCESS: Connection verified in ${verifyDuration.inMilliseconds}ms', 'BluetoothConnector');
          BLELogger.info('CONNECT_METHOD_CONNECTED: Successfully connected to device: ${device!.platformName}', 'BluetoothConnector');
          
          // CRITICAL FIX: Request MTU and connection priority immediately after connection
          final mtuPriorityStartTime = DateTime.now();
          BLELogger.info('CONNECT_METHOD_MTU_PRIORITY: Requesting MTU and connection priority', 'BluetoothConnector');
          try {
            await _requestMtuAndPriority();
            final mtuPriorityEndTime = DateTime.now();
            final mtuPriorityDuration = mtuPriorityEndTime.difference(mtuPriorityStartTime);
            BLELogger.info('CONNECT_METHOD_MTU_PRIORITY_SUCCESS: MTU and priority set in ${mtuPriorityDuration.inMilliseconds}ms', 'BluetoothConnector');
          } catch (e, stackTrace) {
            final mtuPriorityErrorTime = DateTime.now();
            final mtuPriorityDuration = mtuPriorityErrorTime.difference(mtuPriorityStartTime);
            BLELogger.warning('CONNECT_METHOD_MTU_PRIORITY_EXCEPTION: Failed to set MTU/priority (non-critical, took ${mtuPriorityDuration.inMilliseconds}ms)', 'BluetoothConnector');
            BLELogger.warning('CONNECT_METHOD_MTU_PRIORITY_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', 'BluetoothConnector');
            BLELogger.warning('CONNECT_METHOD_MTU_PRIORITY_EXCEPTION_STACK: ${stackTrace.toString()}', 'BluetoothConnector');
          }
        
        // RECOMMENDATION 3.3: Pre-discover services immediately after connection
        // This serves multiple purposes:
        // 1. Provides immediate BLE activity to prevent device timeout
        // 2. Caches services for faster access during handshake
        // 3. Satisfies device's requirement for immediate interaction
        try {
          BLELogger.info('BLE_PREDISCOVERY: Pre-discovering services after connection', 'BluetoothConnector');
          final prediscoveryStartTime = DateTime.now();
          
          // Discover services and cache them immediately
          final services = await device!.discoverServices();
          
          final prediscoveryEndTime = DateTime.now();
          final prediscoveryDuration = prediscoveryEndTime.difference(prediscoveryStartTime);
          
          // CRITICAL: Cache the discovered services for later use
          _cachedServices = services;
          _servicesDiscovered = true;
          
          BLELogger.info('BLE_PREDISCOVERY_SUCCESS: Services pre-discovered and cached (${services.length} services in ${prediscoveryDuration.inMilliseconds}ms)', 'BluetoothConnector');
          
          // Log discovered service UUIDs for debugging
          final serviceUuids = services.map((s) => s.uuid.toString().toLowerCase()).toList();
          BLELogger.debug('BLE_PREDISCOVERY_DETAIL: Pre-discovered service UUIDs: ${serviceUuids.join(", ")}', 'BluetoothConnector');
          
          // Verify connection is still active after pre-discovery
          if (device!.isConnected) {
            BLELogger.info('BLE_PREDISCOVERY_VERIFIED: Connection verified after pre-discovery', 'BluetoothConnector');
          } else {
            BLELogger.warning('BLE_PREDISCOVERY_WARNING: Connection lost during pre-discovery', 'BluetoothConnector');
            // Clear cache if connection lost
            _cachedServices = null;
            _servicesDiscovered = false;
          }
        } catch (e) {
          BLELogger.warning('BLE_PREDISCOVERY_FAILED: Pre-discovery failed (non-critical): $e', 'BluetoothConnector');
          // Clear cache on failure
          _cachedServices = null;
          _servicesDiscovered = false;
          // Don't fail connection if pre-discovery fails - continue anyway
        }
        
          final methodEndTime = DateTime.now();
          final totalMethodDuration = methodEndTime.difference(methodStartTime);
          BLELogger.info('CONNECT_METHOD_SUCCESS: Connection method completed successfully in ${totalMethodDuration.inMilliseconds}ms', 'BluetoothConnector');
          BLELogger.info('CONNECT_METHOD_RESULT: Connection result: true', 'BluetoothConnector');
          
          return true;
        } else {
          final verifyEndTime = DateTime.now();
          final verifyDuration = verifyEndTime.difference(verifyStartTime);
          BLELogger.warning('CONNECT_METHOD_VERIFY_FAILED: Connection completed but device not connected (verification took ${verifyDuration.inMilliseconds}ms)', 'BluetoothConnector');
          BLELogger.warning('CONNECT_METHOD_VERIFY_FAILED_STATE: Device isConnected: ${device!.isConnected}', 'BluetoothConnector');
          return false;
        }
      } catch (stateError) {
        final verifyErrorTime = DateTime.now();
        final verifyDuration = verifyErrorTime.difference(verifyStartTime);
        BLELogger.error('CONNECT_METHOD_VERIFY_EXCEPTION: Exception during connection verification (took ${verifyDuration.inMilliseconds}ms)', stateError, 'BluetoothConnector');
        BLELogger.error('CONNECT_METHOD_VERIFY_EXCEPTION_STACK: ${stateError.toString()}', null, 'BluetoothConnector');
        return false;
      }
    } catch (e, stackTrace) {
      final methodErrorTime = DateTime.now();
      final totalMethodDuration = methodErrorTime.difference(methodStartTime);
      BLELogger.error('CONNECT_METHOD_EXCEPTION: Connection method failed after ${totalMethodDuration.inMilliseconds}ms', e, 'BluetoothConnector');
      BLELogger.error('CONNECT_METHOD_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'BluetoothConnector');
      BLELogger.error('CONNECT_METHOD_EXCEPTION_MESSAGE: ${e.toString()}', null, 'BluetoothConnector');
      BLELogger.error('CONNECT_METHOD_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'BluetoothConnector');
      
      // Log device state at exception time
      final deviceStateAtException = device == null 
          ? "null" 
          : (device!.isConnected ? "connected" : "disconnected");
      BLELogger.error('CONNECT_METHOD_EXCEPTION_STATE: Device state at exception: $deviceStateAtException', null, 'BluetoothConnector');
      
      // Retry logic
      if (retryCount < BLEConfig.maxConnectionRetries && e is TimeoutException) {
        final retryDelay = BLEConfig.connectionRetryDelay;
        BLELogger.info('CONNECT_METHOD_RETRY: Retrying connection (attempt ${retryCount + 1}/${BLEConfig.maxConnectionRetries}) after ${retryDelay.inMilliseconds}ms', 'BluetoothConnector');
        await Future.delayed(retryDelay);
        return connectToDevice(retryCount: retryCount + 1);
      }
      
      BLELogger.error('CONNECT_METHOD_RETRY_EXHAUSTED: All retry attempts exhausted or non-retryable exception', null, 'BluetoothConnector');
      return false;
    }
  }

  Future<bool> disconnectDevice() async {
    if (device == null) {
      BLELogger.debug('No device to disconnect', 'BluetoothConnector');
      return true;
    }

    try {
      BLELogger.info('BLE_GATT_DISCONNECTING: Disconnecting from device', 'BluetoothConnector');
      await device!.disconnect();
      await Future.delayed(const Duration(milliseconds: 500)); // Give time for disconnection
      BLELogger.info('BLE_GATT_DISCONNECTED: Device disconnected', 'BluetoothConnector');
      
      // CRITICAL FIX: Clear service cache on disconnect
      _clearServiceCache();
      
      return true;
    } catch (error) {
      BLELogger.warning('BLE_DISCONNECT_ERROR: Error during disconnect (may already be disconnected)', 'BluetoothConnector');
      _clearServiceCache();
      // Don't throw - device may already be disconnected
      return true;
    }
  }
  
  /// Monitor connection state changes
  Stream<BluetoothConnectionState>? getConnectionStateStream() {
    if (device == null) return null;
    return device!.connectionState;
  }
  
  /// Monitor adapter state changes
  Stream<BluetoothAdapterState> getAdapterStateStream() {
    return FlutterBluePlus.adapterState;
  }

  /// RECOMMENDATION 2.1: Public method to verify connection using stream-based check
  /// This is more reliable than synchronous check as it catches async disconnects
  /// Returns true if connected and no disconnect detected within timeout period
  Future<bool> verifyConnectionWithStream({Duration timeout = const Duration(milliseconds: 10)}) async {
    return await _verifyConnectionWithStream(timeout: timeout);
  }

  //########################################################################
  //EXPLORING THE DEVICE
  //########################################################################

  Future<BluetoothService> readServiceFromDevice(String serviceUUID) async {
    if (!await _isAbleToDiscoverDevice()) {
      throw StateError('Cannot discover device - not connected');
    }

    // CRITICAL FIX: Verify permissions immediately before service discovery (SDK 36 requirement)
    await _verifyBluetoothPermissions('discover');

    // CRITICAL FIX: Use cached services if already discovered to avoid re-discovery
    if (_servicesDiscovered && _cachedServices != null) {
      BLELogger.info('BLE_SERVICE_CACHE_HIT: Using cached services for UUID: $serviceUUID', 'BluetoothConnector');
      
      for (var service in _cachedServices!) {
        if (service.uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
          BLELogger.info('BLE_SERVICE_FOUND_CACHED: Service found in cache: $serviceUUID', 'BluetoothConnector');
          return service;
        }
      }
      
      BLELogger.error('BLE_SERVICE_NOT_FOUND_CACHED: Service not found in cache: $serviceUUID', null, 'BluetoothConnector');
      throw StateError('Service not found in cache: $serviceUUID');
    }

    BLELogger.info('BLE_SERVICE_DISCOVERY_START: Discovering services for UUID: $serviceUUID', 'BluetoothConnector');
    
    try {
      // CRITICAL FIX: Verify connection before discovery
      if (!device!.isConnected) {
        BLELogger.error('BLE_SERVICE_DISCOVERY_FAILED: Device disconnected before discovery', null, 'BluetoothConnector');
        throw StateError('Device disconnected before service discovery');
      }

      // CRITICAL FIX: Log timestamp before service discovery to track timing
      final discoveryStartTime = DateTime.now();
      BLELogger.debug('BLE_SERVICE_DISCOVERY_TIMING: Starting discoverServices() at ${discoveryStartTime.toIso8601String()}', 'BluetoothConnector');
      
      // RECOMMENDATION 3.2: Start discovery and process immediately when results arrive
      // This minimizes time between discovery completion and service access
      List<BluetoothService> services = await device!.discoverServices();
      
      final discoveryEndTime = DateTime.now();
      final discoveryDuration = discoveryEndTime.difference(discoveryStartTime);
      BLELogger.debug('BLE_SERVICE_DISCOVERY_TIMING: discoverServices() completed in ${discoveryDuration.inMilliseconds}ms at ${discoveryEndTime.toIso8601String()}', 'BluetoothConnector');
      
      // RECOMMENDATION 1.2: Log service count IMMEDIATELY after discovery (before any other processing)
      // This confirms services are actually discovered before disconnect occurs
      BLELogger.info('BLE_SERVICE_DISCOVERY_PROGRESS: Found ${services.length} services', 'BluetoothConnector');
      
      // RECOMMENDATION 3.2: Process services IMMEDIATELY - find target service FIRST (before any delays or checks)
      // This is the absolute fastest way to access the service after discovery
      // Some BLE devices require immediate interaction after service discovery
      final processingStartTime = DateTime.now();
      BluetoothService? targetService;
      
      // Find target service IMMEDIATELY - no delays, no connection checks in loop (minimize time)
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
          targetService = service;
          break; // Found it - exit immediately
        }
      }
      
      final processingEndTime = DateTime.now();
      final processingDuration = processingEndTime.difference(processingStartTime);
      BLELogger.debug('BLE_SERVICE_DISCOVERY_PROCESSING: Service lookup completed in ${processingDuration.inMilliseconds}ms', 'BluetoothConnector');
      
      // RECOMMENDATION 2.1: Add small delay AFTER finding service (if found) to allow async events
      // This helps catch async disconnects that may not be registered immediately
      BLELogger.debug('BLE_SERVICE_DISCOVERY_DELAY: Waiting 5ms for async connection state events to process', 'BluetoothConnector');
      await Future.delayed(const Duration(milliseconds: 5));
      final afterDelayTime = DateTime.now();
      final delayDuration = afterDelayTime.difference(discoveryEndTime);
      BLELogger.debug('BLE_SERVICE_DISCOVERY_DELAY_COMPLETE: Delay completed in ${delayDuration.inMilliseconds}ms', 'BluetoothConnector');
      
      // RECOMMENDATION 2.2: Use connection state stream instead of synchronous check
      // This is more reliable as it catches async disconnects that may not be registered synchronously
      BLELogger.debug('BLE_SERVICE_DISCOVERY_CONNECTION_VERIFY: Verifying connection using stream-based check', 'BluetoothConnector');
      final streamVerifyStartTime = DateTime.now();
      
      final isConnectedCheck = await _verifyConnectionWithStream(timeout: const Duration(milliseconds: 10));
      
      final streamVerifyEndTime = DateTime.now();
      final streamVerifyDuration = streamVerifyEndTime.difference(streamVerifyStartTime);
      
      // RECOMMENDATION 1.1: Add connection state logging to show if check passes or fails
      // This will help diagnose if connection check is working correctly
      final synchronousCheck = device != null && device!.isConnected;
      final deviceStatus = device == null ? "null" : (device!.isConnected ? "connected" : "disconnected");
      BLELogger.info('BLE_SERVICE_DISCOVERY_CONNECTION_CHECK: Stream check=$isConnectedCheck, Sync check=$synchronousCheck, device=$deviceStatus (stream check took ${streamVerifyDuration.inMilliseconds}ms)', 'BluetoothConnector');
      
      // CRITICAL FIX: Check connection after delay to allow async disconnect events to register
      // Some devices disconnect immediately after service discovery if not acted upon quickly
      if (!isConnectedCheck) {
        final disconnectCheckTime = DateTime.now();
        final timeSinceDiscovery = disconnectCheckTime.difference(discoveryEndTime);
        BLELogger.error('BLE_SERVICE_DISCOVERY_FAILED: Device disconnected detected via stream check (${timeSinceDiscovery.inMilliseconds}ms after discovery completion)', null, 'BluetoothConnector');
        _servicesDiscovered = false;
        _cachedServices = null;
        throw StateError('Device disconnected immediately after service discovery');
      }
      
      // CRITICAL FIX: Log all discovered service UUIDs for debugging (after connection check)
      final serviceUuids = services.map((s) => s.uuid.toString().toLowerCase()).toList();
      BLELogger.info('BLE_SERVICE_DISCOVERY_DETAIL: Discovered service UUIDs: ${serviceUuids.join(", ")}', 'BluetoothConnector');
      BLELogger.info('BLE_SERVICE_DISCOVERY_DETAIL: Looking for service UUID: ${serviceUUID.toLowerCase()}', 'BluetoothConnector');
      
      // If service was found during immediate processing, verify it's still valid
      if (targetService != null) {
        BLELogger.info('BLE_SERVICE_DISCOVERY_TARGET_FOUND: Target service found during immediate processing', 'BluetoothConnector');
      }
      
      // CRITICAL FIX: Check connection again after service lookup
      if (device == null || !device!.isConnected) {
        final disconnectTime = DateTime.now();
        final timeSinceDiscovery = disconnectTime.difference(discoveryEndTime);
        BLELogger.error('BLE_SERVICE_DISCOVERY_FAILED: Device disconnected after service lookup (${timeSinceDiscovery.inMilliseconds}ms after discovery)', null, 'BluetoothConnector');
        _servicesDiscovered = false;
        _cachedServices = null;
        throw StateError('Device disconnected after service lookup');
      }
      
      // CRITICAL FIX: Cache discovered services ONLY after we've found the target service
      // This ensures we don't waste time caching if device is about to disconnect
      _cachedServices = services;
      _servicesDiscovered = true;
      
      // CRITICAL FIX: Final connection check before returning service
      if (device == null || !device!.isConnected) {
        final disconnectTime = DateTime.now();
        final timeSinceDiscovery = disconnectTime.difference(discoveryEndTime);
        BLELogger.error('BLE_SERVICE_DISCOVERY_FAILED: Device disconnected after caching services (${timeSinceDiscovery.inMilliseconds}ms after discovery)', null, 'BluetoothConnector');
        _servicesDiscovered = false;
        _cachedServices = null;
        throw StateError('Device disconnected after caching services');
      }
      
      if (targetService != null) {
        final serviceFoundTime = DateTime.now();
        final totalTime = serviceFoundTime.difference(discoveryStartTime);
        BLELogger.info('BLE_SERVICE_DISCOVERY_SUCCESS: Service found: $serviceUUID (total time: ${totalTime.inMilliseconds}ms)', 'BluetoothConnector');
        return targetService;
      }

      // Service not found - but device is still connected
      BLELogger.error('BLE_SERVICE_DISCOVERY_FAILED: Service not found: $serviceUUID. Available services: ${serviceUuids.join(", ")}', null, 'BluetoothConnector');
      throw StateError('Service not found: $serviceUUID');
    } catch (e, stackTrace) {
      // RECOMMENDATION 1.3: Add exception handler with detailed logging
      // This will catch any exceptions that might be silently failing
      BLELogger.error('BLE_SERVICE_DISCOVERY_EXCEPTION: Exception during service discovery/processing for UUID: $serviceUUID', e, 'BluetoothConnector');
      BLELogger.error('BLE_SERVICE_DISCOVERY_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'BluetoothConnector');
      BLELogger.error('BLE_SERVICE_DISCOVERY_EXCEPTION_MESSAGE: ${e.toString()}', null, 'BluetoothConnector');
      
      // Log stack trace for debugging
      BLELogger.error('BLE_SERVICE_DISCOVERY_STACK: ${stackTrace.toString()}', null, 'BluetoothConnector');
      
      // Log connection state at time of exception
      if (device != null) {
        try {
          final isConnectedAtException = device!.isConnected;
          BLELogger.error('BLE_SERVICE_DISCOVERY_EXCEPTION_STATE: Device connection state at exception: ${isConnectedAtException ? "CONNECTED" : "DISCONNECTED"}', null, 'BluetoothConnector');
        } catch (stateError) {
          BLELogger.error('BLE_SERVICE_DISCOVERY_EXCEPTION_STATE: Error checking connection state: $stateError', null, 'BluetoothConnector');
        }
      } else {
        BLELogger.error('BLE_SERVICE_DISCOVERY_EXCEPTION_STATE: Device is null at exception', null, 'BluetoothConnector');
      }
      
      // Clear cache on exception
      _servicesDiscovered = false;
      _cachedServices = null;
      rethrow;
    }
  }

  Future<BluetoothCharacteristic> readCharacteristicFrom(
      BluetoothService service, String characteristicsUUID) async {
    final methodStartTime = DateTime.now();
    BLELogger.info('CHARACTERISTIC_METHOD_ENTRY: readCharacteristicFrom() called at ${methodStartTime.toIso8601String()}', 'BluetoothConnector');
    BLELogger.info('CHARACTERISTIC_METHOD_PARAMS: Service UUID: ${service.uuid}, Characteristic UUID: $characteristicsUUID', 'BluetoothConnector');
    BLELogger.info('CHARACTERISTIC_METHOD_DEVICE_STATE: Device state - isNull: ${device == null}, isConnected: ${device?.isConnected ?? false}', 'BluetoothConnector');
    
    try {
      final discoverCheckStartTime = DateTime.now();
      if (!await _isAbleToDiscoverDevice()) {
        final discoverCheckEndTime = DateTime.now();
        final discoverCheckDuration = discoverCheckEndTime.difference(discoverCheckStartTime);
        BLELogger.error('CHARACTERISTIC_METHOD_DISCOVER_CHECK_FAILED: Cannot discover device - not connected (check took ${discoverCheckDuration.inMilliseconds}ms)', null, 'BluetoothConnector');
        throw StateError('Cannot discover device - not connected');
      }
      final discoverCheckEndTime = DateTime.now();
      final discoverCheckDuration = discoverCheckEndTime.difference(discoverCheckStartTime);
      BLELogger.debug('CHARACTERISTIC_METHOD_DISCOVER_CHECK: Discover check completed in ${discoverCheckDuration.inMilliseconds}ms', 'BluetoothConnector');

      final searchStartTime = DateTime.now();
      BLELogger.info('CHARACTERISTIC_SEARCH: Looking for characteristic: $characteristicsUUID in service: ${service.uuid}', 'BluetoothConnector');
      BLELogger.info('CHARACTERISTIC_SEARCH_DETAILS: Service has ${service.characteristics.length} characteristics', 'BluetoothConnector');
      
      // Log all available characteristic UUIDs for debugging
      final availableCharacteristics = service.characteristics.map((c) => c.uuid.toString().toLowerCase()).toList();
      BLELogger.debug('CHARACTERISTIC_SEARCH_AVAILABLE: Available characteristics: ${availableCharacteristics.join(", ")}', 'BluetoothConnector');
      
      BluetoothCharacteristic? foundCharacteristic;
      
      try {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString().toLowerCase() ==
              characteristicsUUID.toLowerCase()) {
            foundCharacteristic = characteristic;
            break;
          }
        }
        
        final searchEndTime = DateTime.now();
        final searchDuration = searchEndTime.difference(searchStartTime);
        
        if (foundCharacteristic != null) {
          BLELogger.info('CHARACTERISTIC_FOUND: Characteristic found: $characteristicsUUID (search took ${searchDuration.inMilliseconds}ms)', 'BluetoothConnector');
          BLELogger.info('CHARACTERISTIC_FOUND_DETAILS: UUID: ${foundCharacteristic.uuid}, Properties: notify=${foundCharacteristic.properties.notify}, indicate=${foundCharacteristic.properties.indicate}, read=${foundCharacteristic.properties.read}, write=${foundCharacteristic.properties.write}', 'BluetoothConnector');
          
          final methodEndTime = DateTime.now();
          final totalMethodDuration = methodEndTime.difference(methodStartTime);
          BLELogger.info('CHARACTERISTIC_METHOD_SUCCESS: Method completed successfully in ${totalMethodDuration.inMilliseconds}ms', 'BluetoothConnector');
          
          return foundCharacteristic;
        }
      } catch (e, stackTrace) {
        final searchErrorTime = DateTime.now();
        final searchDuration = searchErrorTime.difference(searchStartTime);
        BLELogger.error('CHARACTERISTIC_SEARCH_EXCEPTION: Exception during characteristic search (took ${searchDuration.inMilliseconds}ms)', e, 'BluetoothConnector');
        BLELogger.error('CHARACTERISTIC_SEARCH_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'BluetoothConnector');
        BLELogger.error('CHARACTERISTIC_SEARCH_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'BluetoothConnector');
        rethrow;
      }

      final methodErrorTime = DateTime.now();
      final totalMethodDuration = methodErrorTime.difference(methodStartTime);
      BLELogger.error('CHARACTERISTIC_NOT_FOUND: Characteristic not found: $characteristicsUUID (method took ${totalMethodDuration.inMilliseconds}ms)', null, 'BluetoothConnector');
      BLELogger.error('CHARACTERISTIC_NOT_FOUND_DETAILS: Available characteristics: ${availableCharacteristics.join(", ")}', null, 'BluetoothConnector');
      throw StateError('Characteristic not found: $characteristicsUUID');
    } catch (e, stackTrace) {
      final methodErrorTime = DateTime.now();
      final totalMethodDuration = methodErrorTime.difference(methodStartTime);
      BLELogger.error('CHARACTERISTIC_METHOD_EXCEPTION: Method failed after ${totalMethodDuration.inMilliseconds}ms', e, 'BluetoothConnector');
      BLELogger.error('CHARACTERISTIC_METHOD_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'BluetoothConnector');
      BLELogger.error('CHARACTERISTIC_METHOD_EXCEPTION_MESSAGE: ${e.toString()}', null, 'BluetoothConnector');
      BLELogger.error('CHARACTERISTIC_METHOD_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'BluetoothConnector');
      
      // Log device state at exception time
      final deviceStateAtException = device == null 
          ? "null" 
          : (device!.isConnected ? "connected" : "disconnected");
      BLELogger.error('CHARACTERISTIC_METHOD_EXCEPTION_STATE: Device state at exception: $deviceStateAtException', null, 'BluetoothConnector');
      
      rethrow;
    }
  }

  //########################################################################
  //CHARACTERISTIC NOTIFICATIONS/INDICATIONS
  //########################################################################

  /// Enable notifications/indications on a characteristic
  /// Returns a stream that emits data when the characteristic value changes
  Future<Stream<List<int>>> enableCharacteristicNotifications(
      BluetoothCharacteristic characteristic) async {
    if (!await _isAbleToDiscoverDevice()) {
      throw StateError('Cannot enable notifications - not connected');
    }

    // RECOMMENDATION 1.4: Add connection state check before permission check (Enhanced)
    // This prevents wasted operations on disconnected device and fails fast
    // Uses stream-based verification for more accurate connection detection
    BLELogger.debug('BLE_NOTIFICATION_PRE_PERMISSION: Checking connection before permission verification', 'BluetoothConnector');
    final prePermissionCheckTime = DateTime.now();

    // Check device is not null
    if (device == null) {
      BLELogger.error('BLE_NOTIFICATION_FAILED: Device is null before permission check', null, 'BluetoothConnector');
      throw StateError('Device is null before notification setup');
    }

    // Check device is connected using stream-based verification
    BLELogger.debug('BLE_NOTIFICATION_PRE_PERMISSION_CONNECTION_CHECK: Starting stream-based connection verification', 'BluetoothConnector');
    final isConnectedBeforePermission = await verifyConnectionWithStream(timeout: const Duration(milliseconds: 10));
    final postConnectionCheckTime = DateTime.now();
    final connectionCheckDuration = postConnectionCheckTime.difference(prePermissionCheckTime);

    BLELogger.debug('BLE_NOTIFICATION_PRE_PERMISSION_CONNECTION: Connection check took ${connectionCheckDuration.inMilliseconds}ms, result: $isConnectedBeforePermission', 'BluetoothConnector');

    if (!isConnectedBeforePermission) {
      BLELogger.error('BLE_NOTIFICATION_FAILED: Device disconnected before permission check (stream verification)', null, 'BluetoothConnector');
      throw StateError('Device disconnected before notification setup');
    }

    BLELogger.debug('BLE_NOTIFICATION_PRE_PERMISSION_STATE: Device connected, proceeding with permission check', 'BluetoothConnector');

    // RECOMMENDATION 1.2: Add try-catch around permission check call
    // This helps diagnose if exceptions are thrown during permission check call
    BLELogger.debug('BLE_NOTIFICATION_PRE_PERMISSION_CALL: About to call _verifyBluetoothPermissions("notify")', 'BluetoothConnector');
    final prePermissionCallTime = DateTime.now();

    try {
      // CRITICAL FIX: Verify permissions immediately before notification setup (SDK 36 requirement)
      // This is THE ROOT CAUSE of the regression - notification subscription fails silently without this
      await _verifyBluetoothPermissions('notify');
      
      final postPermissionCallTime = DateTime.now();
      final permissionCallDuration = postPermissionCallTime.difference(prePermissionCallTime);
      BLELogger.debug('BLE_NOTIFICATION_POST_PERMISSION_CALL: Permission check call completed in ${permissionCallDuration.inMilliseconds}ms', 'BluetoothConnector');
    } catch (e, stackTrace) {
      final permissionCallErrorTime = DateTime.now();
      final permissionCallDuration = permissionCallErrorTime.difference(prePermissionCallTime);
      BLELogger.error('BLE_NOTIFICATION_PERMISSION_CALL_EXCEPTION: Exception during permission check call (took ${permissionCallDuration.inMilliseconds}ms)', e, 'BluetoothConnector');
      BLELogger.error('BLE_NOTIFICATION_PERMISSION_CALL_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'BluetoothConnector');
      BLELogger.error('BLE_NOTIFICATION_PERMISSION_CALL_EXCEPTION_MESSAGE: ${e.toString()}', null, 'BluetoothConnector');
      BLELogger.error('BLE_NOTIFICATION_PERMISSION_CALL_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'BluetoothConnector');
      
      // Log device state at time of exception
      final deviceStateAtException = device == null 
          ? "null" 
          : (device!.isConnected ? "connected" : "disconnected");
      BLELogger.error('BLE_NOTIFICATION_PERMISSION_CALL_EXCEPTION_STATE: Device state: $deviceStateAtException', null, 'BluetoothConnector');
      
      rethrow;
    }

    // RECOMMENDATION 1.1: Add comprehensive logging after permission check
    // This helps diagnose what happens after permission verification in notification setup
    BLELogger.info('BLE_NOTIFICATION_PERMISSION_VERIFIED: Permission check passed, proceeding with notification setup', 'BluetoothConnector');
    BLELogger.debug('BLE_NOTIFICATION_PRE_SETUP: Device state before setup - isNull: ${device == null}, isConnected: ${device?.isConnected ?? false}', 'BluetoothConnector');

    try {
      BLELogger.info('Enabling notifications on characteristic: ${characteristic.uuid}', 'BluetoothConnector');
      
      // Check if characteristic supports notifications or indications
      if (!characteristic.properties.notify && !characteristic.properties.indicate) {
        throw StateError('Characteristic does not support notifications or indications');
      }

      // CRITICAL FIX: Verify connection before enabling notifications
      if (!device!.isConnected) {
        BLELogger.error('BLE_NOTIFICATION_FAILED: Device disconnected before notification setup', null, 'BluetoothConnector');
        throw StateError('Device disconnected before notification setup');
      }

      // RECOMMENDATION 3.2: Add retry logic for notification setup
      // This may recover from transient failures and improve resilience
      int retryCount = 0;
      const maxRetries = 2;
      bool notificationSetupSuccess = false;
      
      while (retryCount <= maxRetries && !notificationSetupSuccess) {
        try {
          // Enable notifications/indications
          if (retryCount > 0) {
            BLELogger.info('BLE_NOTIFICATION_RETRY: Retrying notification setup (attempt ${retryCount + 1}/${maxRetries + 1})', 'BluetoothConnector');
          } else {
            BLELogger.info('BLE_NOTIFICATION_ENABLING: Enabling notifications on characteristic ${characteristic.uuid}', 'BluetoothConnector');
          }
          
          // RECOMMENDATION 3.2: Disable notifications before retry (if retrying)
          if (retryCount > 0) {
            try {
              await characteristic.setNotifyValue(false);
              BLELogger.debug('BLE_NOTIFICATION_RETRY_CLEANUP: Disabled notifications before retry', 'BluetoothConnector');
              // Small delay after cleanup before retry
              await Future.delayed(Duration(milliseconds: 50 * retryCount));
            } catch (cleanupError) {
              BLELogger.debug('BLE_NOTIFICATION_RETRY_CLEANUP_FAILED: Cleanup failed (non-critical): $cleanupError', 'BluetoothConnector');
              // Continue with retry even if cleanup fails
            }
          }
          
          await characteristic.setNotifyValue(true);
          BLELogger.info('BLE_NOTIFICATION_SET: setNotifyValue(true) called (attempt ${retryCount + 1})', 'BluetoothConnector');
          
          // RECOMMENDATION 2.3: Verify notification setup immediately (no delay)
          // Immediate connection check - no delay to reduce time window for disconnect
          if (!device!.isConnected) {
            BLELogger.error('BLE_NOTIFICATION_FAILED: Device disconnected immediately after setNotifyValue (attempt ${retryCount + 1})', null, 'BluetoothConnector');
            if (retryCount < maxRetries) {
              retryCount++;
              continue; // Retry
            }
            try {
              await characteristic.setNotifyValue(false);
            } catch (_) {
              // Ignore cleanup errors
            }
            throw StateError('Device disconnected immediately after notification setup');
          }
          
          // RECOMMENDATION 2.3: Verify notification stream is accessible immediately
          // This catches subscription failures right away without waiting
          // Access the stream to verify it's available - if this throws, subscription may have failed
          characteristic.onValueReceived; // Verify stream is accessible
          BLELogger.info('BLE_NOTIFICATION_VERIFIED: Notification stream accessible immediately (attempt ${retryCount + 1})', 'BluetoothConnector');
          
          // Verify characteristic still supports notifications (double-check)
          if (!characteristic.properties.notify && !characteristic.properties.indicate) {
            BLELogger.error('BLE_NOTIFICATION_FAILED: Characteristic does not support notifications after setup (attempt ${retryCount + 1})', null, 'BluetoothConnector');
            if (retryCount < maxRetries) {
              retryCount++;
              continue; // Retry
            }
            try {
              await characteristic.setNotifyValue(false);
            } catch (_) {
              // Ignore cleanup errors
            }
            throw StateError('Characteristic does not support notifications or indications');
          }
          
          BLELogger.info('BLE_NOTIFICATION_SUCCESS: Notifications enabled and verified successfully (attempt ${retryCount + 1})', 'BluetoothConnector');
          notificationSetupSuccess = true; // Success - exit retry loop
          
        } catch (e) {
          BLELogger.error('BLE_NOTIFICATION_FAILED: Notification setup failed (attempt ${retryCount + 1}): $e', e, 'BluetoothConnector');
          
          // If this was the last retry, throw the error
          if (retryCount >= maxRetries) {
            BLELogger.error('BLE_NOTIFICATION_FAILED_FINAL: All retry attempts exhausted (${maxRetries + 1} attempts)', null, 'BluetoothConnector');
            // Attempt to disable to clean up
            try {
              await characteristic.setNotifyValue(false);
            } catch (_) {
              // Ignore cleanup errors
            }
            throw StateError('Notification setup failed after ${maxRetries + 1} attempts: $e');
          }
          
          // Increment retry count and continue
          retryCount++;
          BLELogger.info('BLE_NOTIFICATION_RETRY_SCHEDULED: Will retry in ${50 * retryCount}ms (attempt ${retryCount + 1}/${maxRetries + 1})', 'BluetoothConnector');
        }
      }
      
      if (!notificationSetupSuccess) {
        BLELogger.error('BLE_NOTIFICATION_FAILED_UNEXPECTED: Notification setup failed unexpectedly', null, 'BluetoothConnector');
        try {
          await characteristic.setNotifyValue(false);
        } catch (_) {
          // Ignore cleanup errors
        }
        throw StateError('Notification setup failed unexpectedly');
      }
      
      // Return the value stream - this will emit data when device sends notifications
      // CRITICAL FIX: Return stream immediately after verification - no keep-alive delays
      // Keep-alive operations should happen after handshake confirmation
      return characteristic.onValueReceived;
    } catch (e) {
      BLELogger.error('Failed to enable notifications', e, 'BluetoothConnector');
      rethrow;
    }
  }

  /// Disable notifications/indications on a characteristic
  Future<void> disableCharacteristicNotifications(
      BluetoothCharacteristic characteristic) async {
    // Verify permissions before disabling (SDK 36 requirement)
    await _verifyBluetoothPermissions('notify');
    
    try {
      BLELogger.info('Disabling notifications on characteristic: ${characteristic.uuid}', 'BluetoothConnector');
      await characteristic.setNotifyValue(false);
      BLELogger.info('Notifications disabled successfully', 'BluetoothConnector');
    } catch (e) {
      BLELogger.warning('Error disabling notifications (may already be disabled)', 'BluetoothConnector');
      // Don't rethrow - best effort cleanup
    }
  }

  //########################################################################
  //MTU & CONNECTION PRIORITY
  //########################################################################

  /// Request MTU and set connection priority for stable BLE connection
  Future<void> _requestMtuAndPriority() async {
    if (device == null || !device!.isConnected) {
      return;
    }

    try {
      // Request MTU (preferably 247 for better throughput)
      BLELogger.info('BLE_MTU_REQUEST: Requesting MTU 247', 'BluetoothConnector');
      final mtuResult = await device!.requestMtu(247);
      BLELogger.info('BLE_MTU_RESULT: MTU set to $mtuResult', 'BluetoothConnector');
    } catch (e) {
      BLELogger.warning('BLE_MTU_REQUEST_FAILED: MTU request failed: $e', 'BluetoothConnector');
    }

    try {
      // Request high connection priority (Android-specific)
      if (Platform.isAndroid) {
        BLELogger.info('BLE_PRIORITY_REQUEST: Requesting high connection priority', 'BluetoothConnector');
        try {
          await device!.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high);
          BLELogger.info('BLE_PRIORITY_RESULT: Connection priority set to high', 'BluetoothConnector');
        } catch (apiError) {
          BLELogger.warning('BLE_PRIORITY_REQUEST_FAILED: Priority request not supported: $apiError', 'BluetoothConnector');
        }
      }
    } catch (e) {
      BLELogger.warning('BLE_PRIORITY_REQUEST_FAILED: Priority request failed: $e', 'BluetoothConnector');
    }
  }

  //########################################################################
  //PERMISSION VERIFICATION (SDK 36 REQUIREMENT)
  //########################################################################

  /// RECOMMENDATION 3.1: Public method to verify Bluetooth permissions
  /// This allows permission verification to be called from outside the class
  /// (e.g., from handshake method to verify permissions early)
  Future<void> verifyBluetoothPermissions(String operation) async {
    return await _verifyBluetoothPermissions(operation);
  }

  /// Verify Bluetooth permissions immediately before BLE operations
  /// CRITICAL: App targets SDK 36, so Android enforces SDK 31+ permission rules
  /// We MUST use BLUETOOTH_SCAN and BLUETOOTH_CONNECT, never legacy permissions
  Future<void> _verifyBluetoothPermissions(String operation) async {
    // RECOMMENDATION 1.1: Add comprehensive logging inside permission check method
    // This helps diagnose if permission check completes and timing of each step
    final permissionCheckStartTime = DateTime.now();
    BLELogger.debug('BLE_PERMISSION_CHECK_START: Starting permission verification for $operation at ${permissionCheckStartTime.toIso8601String()}', 'BluetoothConnector');
    
    if (!Platform.isAndroid) {
      BLELogger.debug('BLE_PERMISSION_CHECK_SKIP: Not Android, skipping permission check', 'BluetoothConnector');
      return; // Not applicable on iOS
    }

    // RECOMMENDATION 2.1: Skip permission check if already verified recently
    // If permissions were recently verified (within last 5 seconds), skip re-check
    if (_cachedScanPermission == true && 
        _cachedConnectPermission == true && 
        _permissionCacheTime != null &&
        DateTime.now().difference(_permissionCacheTime!) < const Duration(seconds: 5)) {
      final cacheAge = DateTime.now().difference(_permissionCacheTime!);
      BLELogger.debug('BLE_PERMISSION_CHECK_CACHED: Using cached permission status (verified ${cacheAge.inMilliseconds}ms ago)', 'BluetoothConnector');
      return;
    }

    try {
      // Log before status checks
      BLELogger.debug('BLE_PERMISSION_CHECK_STATUS_START: Checking permission statuses', 'BluetoothConnector');
      
      // CRITICAL FIX: App targets SDK 36, so Android enforces SDK 31+ rules
      // We MUST use BLUETOOTH_SCAN and BLUETOOTH_CONNECT, regardless of device SDK
      // Do NOT use legacy Permission.bluetooth - it doesn't work for apps targeting SDK 31+
      // RECOMMENDATION 2.2: Add timeout to permission check to prevent hanging
      final scanStatus = await Permission.bluetoothScan.status
        .timeout(const Duration(milliseconds: 100), onTimeout: () {
          BLELogger.warning('BLE_PERMISSION_CHECK_TIMEOUT: SCAN status check timed out after 100ms', 'BluetoothConnector');
          return PermissionStatus.denied; // Fail safe - deny permission on timeout
        });
      final scanStatusTime = DateTime.now();
      final scanStatusDuration = scanStatusTime.difference(permissionCheckStartTime);
      BLELogger.debug('BLE_PERMISSION_CHECK_SCAN_STATUS: SCAN status checked in ${scanStatusDuration.inMilliseconds}ms - $scanStatus', 'BluetoothConnector');
      
      // RECOMMENDATION 2.2: Add timeout to permission check to prevent hanging
      final connectStatus = await Permission.bluetoothConnect.status
        .timeout(const Duration(milliseconds: 100), onTimeout: () {
          BLELogger.warning('BLE_PERMISSION_CHECK_TIMEOUT: CONNECT status check timed out after 100ms', 'BluetoothConnector');
          return PermissionStatus.denied; // Fail safe - deny permission on timeout
        });
      final connectStatusTime = DateTime.now();
      final connectStatusDuration = connectStatusTime.difference(scanStatusTime);
      BLELogger.debug('BLE_PERMISSION_CHECK_CONNECT_STATUS: CONNECT status checked in ${connectStatusDuration.inMilliseconds}ms - $connectStatus', 'BluetoothConnector');

      BLELogger.info('BLE_PERMISSION_CHECK: Checking permissions for $operation - SCAN: $scanStatus, CONNECT: $connectStatus', 'BluetoothConnector');

      if (scanStatus != PermissionStatus.granted) {
        // RECOMMENDATION 2.1: Clear cache if permission denied
        _cachedScanPermission = null;
        _cachedConnectPermission = null;
        _permissionCacheTime = null;
        BLELogger.error('BLE_PERMISSION_DENIED: BLUETOOTH_SCAN permission not granted for $operation (status: $scanStatus)', null, 'BluetoothConnector');
        throw StateError('BLUETOOTH_SCAN permission required for $operation (app targets SDK 36)');
      }

      if (connectStatus != PermissionStatus.granted) {
        // RECOMMENDATION 2.1: Clear cache if permission denied
        _cachedScanPermission = null;
        _cachedConnectPermission = null;
        _permissionCacheTime = null;
        BLELogger.error('BLE_PERMISSION_DENIED: BLUETOOTH_CONNECT permission not granted for $operation (status: $connectStatus)', null, 'BluetoothConnector');
        throw StateError('BLUETOOTH_CONNECT permission required for $operation (app targets SDK 36)');
      }

      final permissionCheckEndTime = DateTime.now();
      final permissionCheckDuration = permissionCheckEndTime.difference(permissionCheckStartTime);
      BLELogger.debug('BLE_PERMISSION_CHECK_COMPLETE: Permission check completed in ${permissionCheckDuration.inMilliseconds}ms', 'BluetoothConnector');
      
      BLELogger.info('BLE_PERMISSION_GRANTED: SDK 31+ permissions verified for $operation (BLUETOOTH_SCAN + BLUETOOTH_CONNECT)', 'BluetoothConnector');
      
      // RECOMMENDATION 2.1: Cache permission results to avoid re-verification
      _cachedScanPermission = scanStatus == PermissionStatus.granted;
      _cachedConnectPermission = connectStatus == PermissionStatus.granted;
      _permissionCacheTime = DateTime.now();
      BLELogger.debug('BLE_PERMISSION_CHECK_CACHED: Permission status cached for future checks', 'BluetoothConnector');
      
      // RECOMMENDATION 1.1: Add comprehensive logging after permission check
      // This helps diagnose what happens after permission verification
      BLELogger.debug('BLE_PERMISSION_POST_CHECK: Permission check completed, returning to caller', 'BluetoothConnector');
      BLELogger.debug('BLE_PERMISSION_POST_CHECK_STATE: Device state - isNull: ${device == null}, isConnected: ${device?.isConnected ?? false}', 'BluetoothConnector');
    } catch (e, stackTrace) {
      // RECOMMENDATION 1.1: Enhanced exception logging with timing and stack trace
      final permissionCheckErrorTime = DateTime.now();
      final permissionCheckDuration = permissionCheckErrorTime.difference(permissionCheckStartTime);
      BLELogger.error('BLE_PERMISSION_CHECK_EXCEPTION: Exception during permission check (took ${permissionCheckDuration.inMilliseconds}ms)', e, 'BluetoothConnector');
      BLELogger.error('BLE_PERMISSION_CHECK_EXCEPTION_TYPE: Exception type: ${e.runtimeType}', null, 'BluetoothConnector');
      BLELogger.error('BLE_PERMISSION_CHECK_EXCEPTION_MESSAGE: ${e.toString()}', null, 'BluetoothConnector');
      BLELogger.error('BLE_PERMISSION_CHECK_EXCEPTION_STACK: ${stackTrace.toString()}', null, 'BluetoothConnector');
      rethrow;
    }
  }
}
