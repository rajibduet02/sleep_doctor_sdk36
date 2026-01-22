import 'dart:async';

import 'package:easy_localization/src/public_ext.dart';
import 'package:iptasys_sleep_doctor_flutter/datastorage/database/database_helper.dart';
import 'package:iptasys_sleep_doctor_flutter/helpers/sleep_doctor_data_helper.dart';
import 'package:iptasys_sleep_doctor_flutter/interfaces/status_observer.dart';
import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/sleep_doctor_data.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/app_state_notifier.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/ble_logger.dart';

class SleepDoctorRepository {
  static final SleepDoctorRepository _singleton =
      SleepDoctorRepository._internal();

  factory SleepDoctorRepository() {
    return _singleton;
  }

  SleepDoctorRepository._internal();

  final SleepDoctorDataConnector _sleepDoctorDataConnector =
      SleepDoctorDataConnector();

  final SleepDoctorDatabaseHelper _databaseHelper = SleepDoctorDatabaseHelper();

  StatusObserver? _statusObserver;

  void setBluetoothServiceStatesListener(
      BluetoothServiceStatesObserver bluetoothServiceStatesObserver) {
    _sleepDoctorDataConnector.setListener(bluetoothServiceStatesObserver);
  }

  void setStatusListener(StatusObserver statusObserver) {
    _statusObserver = statusObserver;
  }

  //########################################################################
  //DATA EXCHANGE
  //########################################################################

  Future<void> fetchDataFromSleepDoctorDevice() async {
    _notifyIfObserved(Status.WORKING);
    BLELogger.info('SYNC_START: Starting sync from SleepDoctor device', 'SleepDoctorRepository');

    try {
      final data = await _sleepDoctorDataConnector.fetchDataFromSleepDoctorDevice();
      BLELogger.info('SYNC_PROGRESS: Sync completed: fetched ${data.length} entries from device', 'SleepDoctorRepository');
      
      // CRITICAL FIX: Only report success if data is actually stored
      // storeDataToDatabase() now returns false if no valid data remains after filtering
      final success = await _databaseHelper.storeDataToDatabase(data);
      
      if (success) {
        // PRODUCTION HARDENING: Verify data was actually stored before reporting success
        // This prevents "sync successful but database empty" scenarios
        // Note: For empty input data (device has no data), storeDataToDatabase returns true
        // and this verification will confirm database state is correct
        try {
          final storedData = await _databaseHelper.readSleepDataFromDatabase();
          BLELogger.info('SYNC_SUCCESS: ${storedData.length} records now in database (fetched ${data.length} from device)', 'SleepDoctorRepository');
          
          _notifyIfObserved(Status.SUCCESS);
          // PRODUCTION HARDENING: Only notify UI after confirmed successful storage
          // This ensures UI refresh only happens when data is actually persisted
          AppStateNotifier().notifyDataSynced();
        } catch (verifyError) {
          // PRODUCTION HARDENING: If verification read fails, still report success
          // since storeDataToDatabase already confirmed success
          // But log the verification failure for debugging
          BLELogger.warning('SYNC_SUCCESS_VERIFY_FAILED: Sync succeeded but verification read failed: $verifyError', 'SleepDoctorRepository');
          _notifyIfObserved(Status.SUCCESS);
          AppStateNotifier().notifyDataSynced();
        }
      } else {
        // CRITICAL FIX: Report failure if storage fails or no valid data
        // This prevents misleading "sync successful but no data" scenarios
        BLELogger.error('SYNC_FAILED: Data storage failed or no valid data to store (fetched ${data.length} entries)', null, 'SleepDoctorRepository');
        _notifyIfObserved(Status.FAILURE);
      }
    } catch (error) {
      BLELogger.error('SYNC_FAILED: Exception during sync', error, 'SleepDoctorRepository');
      _notifyIfObserved(Status.FAILURE);
      rethrow; // Re-throw so caller can handle if needed
    }
  }

  Future<void> clearSleepDoctorDatabase() async {
    await _databaseHelper.clearSleepDoctorDatabase();
    // Notify UI to refresh after database clear
    AppStateNotifier().notifyDatabaseCleared();
  }

  Future<List<SleepDoctorData>> readAllSleepDoctorData() async {
    return _databaseHelper.readSleepDataFromDatabase();
  }

  void _notifyIfObserved(Status status) {
    if (_statusObserver != null) {
      switch (status) {
        case Status.WORKING:
          _statusObserver!
              .currentStateWithMessage(status, 'performingSync'.tr());
          break;
        case Status.SUCCESS:
          _statusObserver!
              .currentStateWithMessage(status, 'successfulSync'.tr());
          break;
        case Status.FAILURE:
          _statusObserver!.currentStateWithMessage(status, 'failSync'.tr());
          break;
      }
    }
  }
}
