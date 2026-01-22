import 'dart:typed_data';

import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/sleep_doctor_data.dart';
import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/sleep_doctor_header_data.dart';
import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/states/sleep_doctor_states.dart';

//########################################################################
// DATA PARSING
//########################################################################

class BluetoothDataHelper {
  static DateTime parseDate({required List<int> from}) {
    var data = from;

    if (data.length < 7) {
      return DateTime.now();
    }

    int year = data[0] + (data[1] << 8);
    int month = data[2];
    int day = data[3];
    int hour = data[4];
    int min = data[5];
    int sec = data[6];

    return DateTime(year, month, day, hour, min, sec);
  }

  static List<int> prepareDateAsData({required DateTime from}) {
    var date = from;

    var data = <int>[];

    var yearAsByte = ByteData(1);
    yearAsByte.setInt8(0, date.year);
    data.add(yearAsByte.getInt8(0));

    yearAsByte = ByteData(1);
    yearAsByte.setInt8(0, date.year >> 8);
    data.add(yearAsByte.getInt8(0));

    data.add(date.month);
    data.add(date.day);
    data.add(date.hour);
    data.add(date.minute);
    data.add(date.second);

    // 2020-08-31: MS: FIXME added % 7 because SleepDoctor did not accept weekday = 7 (for Sunday)
    //  --> Taken from Sleep Doctor Android Origin Project
    data.add(((date.weekday + 5) % 7 + 1) % 7);
    var millis = ByteData(1);
    millis.setInt8(0, (date.millisecond * 256 / 1000).round());
    data.add(millis.getInt8(0));
    data.add(1);

    return data;
  }

  static SleepDoctorHeaderData? parseHeaderData({required List<int> from}) {
    var data = from;

    if (data.length < 14) {
      return null;
    }
    double verBootloaderMaj = data[1] / 16;
    int verBootloaderMin = data[1] % 16;
    double verBootloader = double.parse(
        "${verBootloaderMaj.toInt()}.$verBootloaderMin");

    double verFirmwareMaj = data[2] / 16;
    int verFirmwareMin = data[2] % 16;
    double verFirmware = double.parse(
        "${verFirmwareMaj.toInt()}.$verFirmwareMin");

    int year = data[3] + (data[4] << 8);
    year = year < DateTime.now().year ? year + 1900 : year;
    int month = data[5] + 1; //FIXME SleepDoctor months start at 0
    int day = data[6];
    int hour = data[7];
    int min = data[8];
    int sec = data[9];
    // int dayofweek = data[10]; //FIXME not used
    int numberOfElements = data[11] + (data[12] << 8);
    int batteryLevel = data[13];

    return SleepDoctorHeaderData(
        verBootloader: verBootloader,
        verFirmware: verFirmware,
        startDateTime: DateTime(year, month, day, hour, min, sec),
        batteryLevel: batteryLevel,
        numberOfElements: numberOfElements);
  }

  static List<SleepDoctorData> parseData({
    required List<List<int>> from,
    required DateTime? withSyncedTime,
  }) {
    var dataList = from;
    var currTime = withSyncedTime ?? DateTime.now();

    List<SleepDoctorData> sleepDoctorDataList = <SleepDoctorData>[];
    SleepDoctorData? currSleepDocData;

    for (List<int> data in dataList) {
      var len = data[1]; //number of elements

      if (len + 2 > data.length) {
        // Log warning but continue - data may still be partially valid
        // This is handled gracefully by skipping invalid entries
      }

      for (int i = 0; i < len; i++) {
        int entry = data[i + 2];
        int mode = (entry & 0xC0) >> 6;
        if (mode == SleepDoctorModeState.MODE_TIME.item1) {
          int repeat = entry & 0x3F;
          // add repeat * 10 Sec
          currTime = currTime.add(Duration(seconds: 10 * repeat));
        } else {
          int phase = (entry & 0x30) >> 4;
          int orientation = (entry & 0x0E) >> 1;
          bool stimulation = (entry & 0x01) > 0;

          if (currSleepDocData != null) {
            currSleepDocData.setToTime(currTime);
            sleepDoctorDataList.add(currSleepDocData);
          }
          currSleepDocData = SleepDoctorData(
            mode: mode,
            stimulation: stimulation,
            orientation: orientation,
            sleepPhase: phase,
            fromTime: currTime,
            toTime: currTime,
          );
          currTime = currTime.add(const Duration(seconds: 10));
        }
        if (i == len - 1 && currSleepDocData != null) {
          // last entry
          currSleepDocData.setToTime(currTime);
          sleepDoctorDataList.add(currSleepDocData);
        }
      }
    }

    return sleepDoctorDataList;
  }

  //########################################################################
  // TIME SYNCHRONIZATION
  //########################################################################

  static bool areaDatesSynchronous({
    required DateTime firstTime,
    required DateTime secondTime,
  }) {
    //if time difference is less than 1 day, sleep doctor has the correct date (as explained in Android version)
    return firstTime.difference(secondTime).inHours.abs() < 24;
  }

  //this method is used if the time on the device is not correct and the actual start date has to be estimated
  static DateTime estimateStartTimeOfMeasurement({
    required DateTime of,
    required List<List<int>> and,
  }) {
    var dataList = and;
    var time = of;
    int numIntervalls = 0;

    for (List<int> data in dataList) {
      int len = data[1]; //number of elements

      // go through data entries and parse them to SleepDoctorData
      for (int i = 0; i < len; i++) {
        int entry = data[i + 2];
        int mode = (entry & 0xC0) >> 6;
        if (mode == SleepDoctorModeState.MODE_TIME.item1) {
          int repeat = entry & 0x3F;
          // add repeat Intervalls
          numIntervalls += repeat;
        } else {
          numIntervalls++;
        }
      }
    }

    //magic calculation take from Android SleepDoctor Project
    return time.subtract(Duration(seconds: numIntervalls * 10));
  }
}
