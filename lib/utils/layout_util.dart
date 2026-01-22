import 'package:flutter/material.dart';

class LayoutUtility {
  static bool isDeviceAPhone(BuildContext context) {
    // The equivalent of the "smallestWidth" qualifier on Android.
    var smallestDimension = MediaQuery.of(context).size.shortestSide;
    return smallestDimension < 600;
  }

  static void makeToastWith(String message, BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: const Color.fromARGB(255, 0, 74, 153),
        content: Text(
          message,
          textAlign: TextAlign.center,
        )));
  }
}
