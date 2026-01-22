import 'package:floor/floor.dart';
import 'package:iptasys_sleep_doctor_flutter/datastorage/database/daos/sleep_doctor_data_dao.dart';
import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/sleep_doctor_data.dart';
import 'converters/date_time_converter.dart';

// required package imports
import 'dart:async';
import 'package:sqflite/sqflite.dart' as sqflite;

part 'database.g.dart'; // the generated code will be there

//FIXME ATTENTION: Run "flutter packages pub run build_runner build" after changing anything at the database

@TypeConverters([DateTimeConverter])
@Database(version: 1, entities: [SleepDoctorData])
abstract class SleepDoctorDatabase extends FloorDatabase {
  SleepDoctorDataDao get sleepDataDao;
}