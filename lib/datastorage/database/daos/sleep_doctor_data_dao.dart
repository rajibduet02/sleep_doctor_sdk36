import 'package:floor/floor.dart';
import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/sleep_doctor_data.dart';

@dao
abstract class SleepDoctorDataDao {

  @Query('SELECT * FROM sleep_data')
  Future<List<SleepDoctorData>> getSleepData();

  @Query('SELECT * FROM sleep_data WHERE fromTime >= :dateTime')
  Future<List<SleepDoctorData>> getSleepDataSince(DateTime dateTime);

  @Insert(onConflict: OnConflictStrategy.replace)
  Future<void> insertSleepData(SleepDoctorData data);

  @Query('DELETE FROM sleep_data')
  Future<void> deleteAllSleepData();

}