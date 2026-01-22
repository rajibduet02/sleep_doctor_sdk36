import 'dart:io';

import 'package:easy_localization/src/public_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:iptasys_sleep_doctor_flutter/interfaces/routable.dart';
import 'package:iptasys_sleep_doctor_flutter/interfaces/status_observer.dart';
import 'package:iptasys_sleep_doctor_flutter/repositories/sleep_doctor_repository.dart';
import 'package:iptasys_sleep_doctor_flutter/repositories/sleep_doctor_repository_singleton_global.dart'
    as global;
import 'package:iptasys_sleep_doctor_flutter/utils/layout_util.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/ble_logger.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/app_lifecycle_manager.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/battery_optimization_handler.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncScreen extends StatefulWidget implements Routable {
  static String ROUTE_ID = "/SyncScreen";

  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen>
    implements StatusObserver, BluetoothServiceStatesObserver {
  final SleepDoctorRepository _repository = global.sleepDoctorRepository;
  final AppLifecycleManager _lifecycleManager = AppLifecycleManager();

  BluetoothAdapterState _bluetoothState = BluetoothAdapterState.unknown;

  bool _isFetching = false;

  bool _failure = false;

  bool _success = false;

  bool _searchDevice = false;
  bool _waitingForButtonPress = false;

  @override
  void initState() {
    super.initState();
    // PRODUCTION HARDENING: Remove redundant lifecycle initialization
    // Lifecycle manager is already initialized in main.dart
    // Calling initialize() again is redundant (singleton prevents issues but unclear)
    // _lifecycleManager.initialize(); // REMOVED - already initialized in main.dart
    
    _repository.setStatusListener(this);
    _repository.setBluetoothServiceStatesListener(this);
    
    // PRODUCTION HARDENING: Reset sync state when screen is initialized
    // This ensures UI reflects current sync status, not stale results from previous navigation
    _resetSyncState();
  }
  
  /// Reset sync state to initial values
  void _resetSyncState() {
    setState(() {
      _isFetching = false;
      _failure = false;
      _success = false;
      _searchDevice = false;
      _waitingForButtonPress = false;
    });
  }

  @override
  void dispose() {
    _lifecycleManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        margin: const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 20),
        child: Container(
          decoration: const BoxDecoration(
              color: Color.fromRGBO(128, 212, 255, 1),
              borderRadius: BorderRadius.all(Radius.circular(10.0))),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    'synchronize',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ).tr(),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Stack(
                    children: [
                      _createBluetoothStateIcon(),
                      _createStateIndicator(),
                    ],
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isFetching
                          ? const Color.fromRGBO(169, 169, 169, 1)
                          : const Color.fromRGBO(224, 224, 224, 1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5.0),
                          side: const BorderSide(
                              color: Color.fromRGBO(160, 160, 160, 1))),
                    ),
                    onPressed: () async {
                      // Re-check permissions before every sync
                      if (!await hasBluetoothPermission()) {
                        BLELogger.warning('Permissions not granted, requesting...', 'SyncScreen');
                        final status = await requestBluetoothPermission();
                        if (status != PermissionStatus.granted) {
                          LayoutUtility.makeToastWith(
                              'Bluetooth permissions required'.tr(), context);
                          return;
                        }
                      }

                      if (_bluetoothState != BluetoothAdapterState.on) {
                        LayoutUtility.makeToastWith(
                            'turnOnBluetooth'.tr(), context);
                        return;
                      }

                      if (_isFetching) {
                        LayoutUtility.makeToastWith(
                            'alreadyInSync'.tr(), context);
                        return;
                      }

                      // Request battery optimization exemption (Android)
                      if (Platform.isAndroid) {
                        await BatteryOptimizationHandler.ensureBatteryOptimizationExempt();
                      }

                      // Start sync
                      try {
                        BLELogger.info('SYNC_USER_INITIATED: User initiated sync', 'SyncScreen');
                        await _repository.fetchDataFromSleepDoctorDevice();
                      } catch (e) {
                        BLELogger.error('SYNC_USER_INITIATED_FAILED: Sync failed', e, 'SyncScreen');
                        // Error is already handled by status observer
                      }
                    },
                    child: Text('syncButton',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black))
                        .tr(),
                  ),
                ],
              ),
              _fetchingText(),
              _failureText(),
              _successText(),
              _searchDeviceText()
            ],
          ),
        ));
  }

  @override
  bluetoothIsScanningStateChanged(bool isScanning) {
    BLELogger.debug('Scanning state changed: $isScanning', 'SyncScreen');
    if (mounted) {
      setState(() {
        _searchDevice = isScanning;
      });
    }
  }

  @override
  bluetoothStateChanged(BluetoothAdapterState state) {
    BLELogger.info('Bluetooth adapter state changed: $state', 'SyncScreen');
    if (mounted) {
      setState(() {
        _bluetoothState = state;
      });
    }
  }

  @override
  bluetoothConnectionStateChanged(BluetoothConnectionState deviceState) {
    BLELogger.info('Connection state changed: $deviceState', 'SyncScreen');
    // Could update UI here if needed
  }

  @override
  waitingForButtonPress(bool isWaiting) {
    BLELogger.info('Waiting for button press: $isWaiting', 'SyncScreen');
    if (mounted) {
      setState(() {
        _waitingForButtonPress = isWaiting;
        // Keep searchDevice true while waiting for button press
        // This ensures UI shows "Press blue button" message
        if (isWaiting) {
          _searchDevice = true;
        }
      });
    }
  }

  @override
  currentStateWithMessage(
    Status state,
    String stateMessage,
  ) {
    setState(() {
      _isFetching = state == Status.WORKING ? true : false;
      _failure = state == Status.FAILURE ? true : false;
      _success = state == Status.SUCCESS ? true : false;
    });
  }

  /// Check Bluetooth permissions - re-check before every sync
  /// CRITICAL: App targets SDK 36, so we MUST use BLUETOOTH_SCAN and BLUETOOTH_CONNECT
  /// Do NOT check Permission.bluetooth - it's not valid for apps targeting SDK 31+
  Future<bool> hasBluetoothPermission() async {
    try {
      // App targets SDK 36, so Android enforces SDK 31+ permission rules
      // Always check BLUETOOTH_SCAN and BLUETOOTH_CONNECT
      final scanStatus = await Permission.bluetoothScan.status;
      final connectStatus = await Permission.bluetoothConnect.status;
      
      final allGranted = scanStatus == PermissionStatus.granted &&
          connectStatus == PermissionStatus.granted;
      
      if (!allGranted) {
        BLELogger.warning('BLE_PERMISSION_CHECK_FAILED: Missing permissions: SCAN=$scanStatus, CONNECT=$connectStatus', 'SyncScreen');
      } else {
        BLELogger.info('BLE_PERMISSION_CHECK_PASSED: Permissions granted: SCAN=$scanStatus, CONNECT=$connectStatus', 'SyncScreen');
      }
      
      return allGranted;
    } catch (e) {
      BLELogger.error('Error checking permissions', e, 'SyncScreen');
      return false;
    }
  }

  /// Request Bluetooth permissions
  /// CRITICAL: App targets SDK 36, so ALWAYS use BLUETOOTH_SCAN and BLUETOOTH_CONNECT
  /// Do NOT use Permission.bluetooth - it's not valid for apps targeting SDK 31+
  Future<PermissionStatus> requestBluetoothPermission() async {
    // App targets SDK 36 → Always use SDK 31+ permissions
    // No SDK detection needed - always request modern permissions
    var statusBluetoothScan = await Permission.bluetoothScan.request();
    var statusBluetoothConnect = await Permission.bluetoothConnect.request();

    BLELogger.info('BLE_PERMISSION_REQUEST_RESULT: Permission request results - SCAN: $statusBluetoothScan, CONNECT: $statusBluetoothConnect', 'SyncScreen');

    // Both SCAN and CONNECT are required for SDK 36
    if (statusBluetoothScan == PermissionStatus.granted &&
        statusBluetoothConnect == PermissionStatus.granted) {
      return PermissionStatus.granted;
    }

    // CRITICAL FIX: Handle permanently denied permissions
    // If user permanently denied, guide them to app settings
    if (statusBluetoothScan.isPermanentlyDenied || statusBluetoothConnect.isPermanentlyDenied) {
      BLELogger.warning('Permissions permanently denied - user must enable in settings', 'SyncScreen');
      if (mounted) {
        LayoutUtility.makeToastWith(
          'Bluetooth permissions are required. Please enable them in app settings.'.tr(),
          context,
        );
        // Optionally open app settings (commented out to avoid auto-navigation)
        // await openAppSettings();
      }
      return PermissionStatus.permanentlyDenied;
    }

    return PermissionStatus.denied;
  }

  Widget _createBluetoothStateIcon() {
    if (_bluetoothState == BluetoothAdapterState.on) {
      return const Icon(
        Icons.bluetooth,
        size: 30,
      );
    } else {
      return const Icon(
        Icons.bluetooth_disabled,
        size: 30,
      );
    }
  }

  Widget _createStateIndicator() {
    if (_isFetching || _searchDevice) {
      return const SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.amberAccent),
          ));
    } else {
      return const Icon(
        Icons.bluetooth_disabled,
        size: 30,
      );
    }
  }

  Widget _fetchingText() {
    if (_isFetching && !_searchDevice) {
      return Container(
        margin: const EdgeInsets.only(top: 20),
        child: Text(
          'performingSync',
          style: Theme.of(context).textTheme.bodyMedium,
        ).tr(),
      );
    } else {
      return const Visibility(
        visible: false,
        child: Text(""),
      );
    }
  }

  Widget _failureText() {
    if (_failure) {
      return Container(
        margin: const EdgeInsets.only(top: 20),
        child: Text(
          'failSync',
          style: Theme.of(context).textTheme.bodyMedium,
        ).tr(),
      );
    } else {
      return const Visibility(
        visible: false,
        child: Text(""),
      );
    }
  }

  Widget _successText() {
    if (_success) {
      return Container(
        margin: const EdgeInsets.only(top: 20),
        child: Text(
          'successfulSync',
          style: Theme.of(context).textTheme.bodyMedium,
        ).tr(),
      );
    } else {
      return const Visibility(
        visible: false,
        child: Text(""),
      );
    }
  }

  Widget _searchDeviceText() {
    // Show message when scanning OR waiting for button press
    if (_searchDevice || _waitingForButtonPress) {
      return Container(
        margin: const EdgeInsets.only(top: 20),
        child: Text(
          'searchDevice',
          style: Theme.of(context).textTheme.bodyMedium,
        ).tr(),
      );
    } else {
      return const Visibility(
        visible: false,
        child: Text(""),
      );
    }
  }

  Future<void> _saveOptions() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync', true);
  }
}
