import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/sleep_doctor_abstract_data.dart';
import 'package:floor/floor.dart';
import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/states/sleep_doctor_states.dart';
import 'package:tuple/tuple.dart';

enum SleepDoctorDataType { STIMULATION, ORIENTATION, SLEEP_PHASE, MODE, MODE_APNOE, MODE_SNORE }

class SleepDoctorDataTypeRaw {
  static String typeDescription(SleepDoctorDataType type) {
    switch (type) {
      case SleepDoctorDataType.MODE:
        return "MODE";
      case SleepDoctorDataType.ORIENTATION:
        return "ORIENTATION";
      case SleepDoctorDataType.STIMULATION:
        return "STIMULATION";
      case SleepDoctorDataType.SLEEP_PHASE:
        return "SLEEP_PHASE";
      default:
        return "";
    }
  }
}

class SleepDoctorDataTypeLabels {
  static List<Tuple2<int, String>> typeLabels(SleepDoctorDataType type) {
    switch (type) {
      case SleepDoctorDataType.MODE:
        return <Tuple2<int, String>>[
          SleepDoctorModeState.MODE_TIME,
          SleepDoctorModeState.MODE_SIDLE,
          SleepDoctorModeState.MODE_APNOE,
          SleepDoctorModeState.MODE_SNORE
        ];
      case SleepDoctorDataType.ORIENTATION:
        return <Tuple2<int, String>>[
          SleepDoctorOrientationState.ORIENTATION_STOMACH,
          SleepDoctorOrientationState.ORIENTATION_BACK,
          SleepDoctorOrientationState.ORIENTATION_LEFT,
          SleepDoctorOrientationState.ORIENTATION_RIGHT,
          SleepDoctorOrientationState.ORIENTATION_SITTING,
          SleepDoctorOrientationState.ORIENTATION_WALK,
          SleepDoctorOrientationState.ORIENTATION_HEADSTAND,
        ];
      case SleepDoctorDataType.STIMULATION:
        return <Tuple2<int, String>>[
          SleepDoctorStimulationState.STIMULATION_OFF,
          SleepDoctorStimulationState.STIMULATION_ON,
        ];
      case SleepDoctorDataType.SLEEP_PHASE:
        return <Tuple2<int, String>>[
          SleepDoctorSleepPhaseState.PHASE_DEEP,
          SleepDoctorSleepPhaseState.PHASE_LIGHT,
          SleepDoctorSleepPhaseState.PHASE_REM,
          SleepDoctorSleepPhaseState.PHASE_AWAKE
        ];
      default:
        return <Tuple2<int, String>>[];
    }
  }
}

@Entity(tableName: 'sleep_data')
class SleepDoctorData extends SleepDoctorAbstractData {
  @PrimaryKey()
  @ColumnInfo(name: 'fromTime')
  DateTime fromTime;

  DateTime toTime;

  @ColumnInfo(name: 'mode')
  final int mode;

  @ColumnInfo(name: 'stimulation')
  final bool stimulation;

  @ColumnInfo(name: 'orientation')
  int orientation;

  @ColumnInfo(name: 'sleep_phase')
  final int sleepPhase;

  SleepDoctorData({
    required this.mode,
    required this.stimulation,
    required this.orientation,
    required this.sleepPhase,
    required this.fromTime,
    required this.toTime,
  });

  void setFromTime(DateTime fromTime) {
    this.fromTime = fromTime;
  }

  void setToTime(DateTime toTime) {
    this.toTime = toTime;
  }

  @override
  String toString() {
    return "\t_fromTime:\t$fromTime"
        "\t_toTime:\t$toTime"
        "\tmode:\t$mode"
        "\tstimulation:\t$stimulation"
        "\torientation:\t$orientation"
        "\tsleepPhase:\t$sleepPhase";
  }

  double valueOf(SleepDoctorDataType type) {
    switch (type) {
      case SleepDoctorDataType.MODE:
        return mode.toDouble();
      case SleepDoctorDataType.ORIENTATION:
        return orientation.toDouble();
      case SleepDoctorDataType.STIMULATION:
        return stimulation ? 1 : 0;
      case SleepDoctorDataType.SLEEP_PHASE:
        return sleepPhase.toDouble();
      default:
        return 0;
    }
  }

  double timeMode(SleepDoctorDataType type) {
    switch (type) {
      case SleepDoctorDataType.MODE:
        return fromTime.microsecondsSinceEpoch.toDouble();
      default:
        return 0;
    }
  }
}
