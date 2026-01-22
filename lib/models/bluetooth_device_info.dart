import 'package:iptasys_sleep_doctor_flutter/interfaces/parsable.dart';
import 'package:equatable/equatable.dart';

class BTDeviceInfo extends Equatable implements Parsable {
  final String deviceName;
  final int rssi;

  const BTDeviceInfo({required this.deviceName, required this.rssi});

  @override
  List<Object> get props => [deviceName, rssi];
}
