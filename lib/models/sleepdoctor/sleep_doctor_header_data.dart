import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/sleep_doctor_abstract_data.dart';

class SleepDoctorHeaderData extends SleepDoctorAbstractData {
  double verFirmware;
  double verBootloader;
  int batteryLevel;
  DateTime startDateTime;
  int numberOfElements;

  SleepDoctorHeaderData({
    required this.verFirmware,
    required this.batteryLevel,
    required this.verBootloader,
    required this.startDateTime,
    required this.numberOfElements,
  });

  @override
  String toString() {
    return "\tverFirmware:\t$verFirmware"
        "\tverBootloader:\t$verBootloader"
        "\tbatteryLevel:\t$batteryLevel"
        "\tstartDateTime:\t$startDateTime"
        "\tnumberOfElements:\t$numberOfElements";
  }
}
