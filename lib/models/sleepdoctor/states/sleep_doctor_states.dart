
import 'package:easy_localization/src/public_ext.dart';
import 'package:tuple/tuple.dart';

class SleepDoctorModeState implements SleepDoctorStates {
  static var MODE_TIME = Tuple2<int, String>(0, 'mode_time'.tr());
  static var MODE_SIDLE = Tuple2<int, String>(1, 'mode_sidle'.tr());
  static var MODE_APNOE = Tuple2<int, String>(2, 'mode_apnoe'.tr());
  static var MODE_SNORE = Tuple2<int, String>(3, 'mode_snore'.tr());
}


class SleepDoctorSleepPhaseState implements SleepDoctorStates {
  static var PHASE_DEEP = Tuple2<int, String>(0, 'phase_deep'.tr());
  static var PHASE_LIGHT = Tuple2<int, String>(1, 'phase_light'.tr());
  static var PHASE_REM = Tuple2<int, String>(2, 'phase_rem'.tr());
  static var PHASE_AWAKE = Tuple2<int, String>(3, 'phase_awake'.tr());
}

class SleepDoctorOrientationState implements SleepDoctorStates {
  static var ORIENTATION_STOMACH =
      Tuple2<int, String>(0, 'orientation_stomach'.tr());
  static var ORIENTATION_BACK =
      Tuple2<int, String>(1, 'orientation_back'.tr());
  static var ORIENTATION_LEFT =
      Tuple2<int, String>(2, 'orientation_left'.tr());
  static var ORIENTATION_RIGHT =
       Tuple2<int, String>(3, 'orientation_right'.tr());
  static var ORIENTATION_SITTING =
       Tuple2<int, String>(4, 'orientation_sitting'.tr());
  static var ORIENTATION_WALK =
       Tuple2<int, String>(5, 'orientation_walk'.tr());
  static var ORIENTATION_HEADSTAND =
       Tuple2<int, String>(6, 'orientation_headstand'.tr());
  static var ORIENTATION_CHARGE_O =
       Tuple2<int, String>(7, 'orientation_charge'.tr());
  static var ORIENTATION_INVALID =
       Tuple2<int, String>(8, 'orientation_invalid'.tr());
}

class SleepDoctorStimulationState implements SleepDoctorStates {
  static var STIMULATION_OFF =
       Tuple2<int, String>(0, 'stimulation_off'.tr());
   static var STIMULATION_ON =
        Tuple2<int, String>(1, 'stimulation_on'.tr());
}

class SleepDoctorStates {}