import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/sleep_doctor_abstract_data.dart';
import 'package:iptasys_sleep_doctor_flutter/datastorage/database/database.dart';
import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/sleep_doctor_data.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/ble_logger.dart';
import 'dart:async';

class SleepDoctorDatabaseHelper {
  final database =
      $FloorSleepDoctorDatabase.databaseBuilder('sleep_doctor_database.db').build();

  //########################################################################
  //DATABASE CRUD
  //########################################################################

  Future<bool> storeDataToDatabase(List<SleepDoctorAbstractData> data) async {
    // CRITICAL FIX: Match SDK 31 behavior - return false if data is null
    // Empty data after filtering means no valid data to store = failure
    final fetchedCount = data.length;
    BLELogger.info('Storing data to database: fetched $fetchedCount entries', 'DatabaseHelper');
    
    if (data.isEmpty) {
      // Empty input list - this is valid (no data to sync), return true
      BLELogger.debug('No data to store (empty list)', 'DatabaseHelper');
      return true;
    }

    try {
      final db = await database;
      final dao = db.sleepDataDao;
      
      // CRITICAL FIX: Apply the SAME filtering rules as SDK 31
      // Filter out entries that are not SleepDoctorData
      // In SDK 36, fromTime and toTime are required (non-nullable), so null checks are not needed
      // However, we still filter by type to ensure only valid SleepDoctorData objects are stored
      // This prevents invalid data from being stored and causing database errors
      final sleepData = data.where((entry) => entry is SleepDoctorData)
          .cast<SleepDoctorData>()
          .toList();
      
      final filteredCount = sleepData.length;
      BLELogger.info('After filtering: $filteredCount valid SleepDoctorData entries (from $fetchedCount total)', 'DatabaseHelper');

      // CRITICAL FIX: Do NOT report success when no valid data remains after filtering
      // This ensures we only report success when data is actually stored
      if (sleepData.isEmpty) {
        BLELogger.warning('No valid data to store after filtering (all $fetchedCount entries filtered out)', 'DatabaseHelper');
        return false; // Changed from true to false - matches SDK 31 behavior
      }

      // CRITICAL FIX: Insert all data with proper error handling
      // Future.wait will throw if ANY insert fails, which is caught below
      // This ensures partial insert failures are detected and reported
      int insertedCount = 0;
      int failedCount = 0;
      
      // Insert each record individually to track success/failure
      for (var currSleepData in sleepData) {
        try {
          await dao.insertSleepData(currSleepData);
          insertedCount++;
        } catch (e) {
          failedCount++;
          BLELogger.error('Failed to insert record: ${currSleepData.toString()}', e, 'DatabaseHelper');
          // Continue inserting other records, but we'll report failure at the end
        }
      }

      // CRITICAL FIX: Only report success if ALL inserts succeeded
      if (failedCount > 0) {
        BLELogger.error('Partial insert failure: $insertedCount succeeded, $failedCount failed out of $filteredCount total', null, 'DatabaseHelper');
        return false;
      }

      BLELogger.info('Successfully stored $insertedCount records to database (fetched: $fetchedCount, filtered: $filteredCount)', 'DatabaseHelper');
      return true;
    } catch (e) {
      BLELogger.error('Error storing data to database', e, 'DatabaseHelper');
      return false;
    }
  }

  Future<List<SleepDoctorData>> readSleepDataFromDatabase() async {
    try {
      final db = await database;
      final data = await db.sleepDataDao.getSleepData();
      BLELogger.debug('Read ${data.length} records from database', 'DatabaseHelper');
      return data;
    } catch (e) {
      BLELogger.error('Error reading data from database', e, 'DatabaseHelper');
      rethrow;
    }
  }

  Future<List<SleepDoctorData>> readSleepDataFromDatabaseSince(
      DateTime dateTime) async {
    try {
      final db = await database;
      final data = await db.sleepDataDao.getSleepDataSince(dateTime);
      BLELogger.debug('Read ${data.length} records since $dateTime', 'DatabaseHelper');
      return data;
    } catch (e) {
      BLELogger.error('Error reading data since date from database', e, 'DatabaseHelper');
      rethrow;
    }
  }

  Future<void> clearSleepDoctorDatabase() async {
    try {
      final db = await database;
      await db.sleepDataDao.deleteAllSleepData();
      BLELogger.info('Database cleared successfully', 'DatabaseHelper');
    } catch (e) {
      BLELogger.error('Error clearing database', e, 'DatabaseHelper');
      rethrow;
    }
  }
}
