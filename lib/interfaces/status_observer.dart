import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class StatusObserver {
  currentStateWithMessage(Status state, String stateMessage) {}
}

class BluetoothServiceStatesObserver {
  bluetoothConnectionStateChanged(BluetoothConnectionState deviceState) {}
  bluetoothStateChanged(BluetoothAdapterState state) {}
  bluetoothIsScanningStateChanged(bool isScanning) {}
  /// Called when device is connected and waiting for button press
  waitingForButtonPress(bool isWaiting) {}
}

enum Status {
  SUCCESS,
  FAILURE,
  WORKING
}
