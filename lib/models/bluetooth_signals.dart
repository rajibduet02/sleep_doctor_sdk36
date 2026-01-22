import 'package:flutter/services.dart';

class BTSignals {

  // Start of Heading
  static int E_SOH() {
    var signalAsBytes = ByteData(1);
    signalAsBytes.setInt8(0, 0x01);
    return signalAsBytes.getInt8(0);
  }

// Start of Text
  static int E_STX() {
    var signalAsBytes = ByteData(1);
    signalAsBytes.setInt8(0, 0x02);
    return signalAsBytes.getInt8(0);
  }

// End of Text
  static int E_ETX() {
    var signalAsBytes = ByteData(1);
    signalAsBytes.setInt8(0, 0x03);
    return signalAsBytes.getInt8(0);
  }

// Unit Separator
  static int E_US() {
    var signalAsBytes = ByteData(1);
    signalAsBytes.setInt8(0, 0x1f);
    return signalAsBytes.getInt8(0);
  }

// Acknowledge
  static int E_ACK() {
    var signalAsBytes = ByteData(1);
    signalAsBytes.setInt8(0, 0x06);
    return signalAsBytes.getInt8(0);
  }


  // Clear Signal
  static int C() {
    return 67;
  }
}
