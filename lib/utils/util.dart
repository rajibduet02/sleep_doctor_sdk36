import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

/// TypeFace class to hold font family and weight information
class TypeFace {
  final String fontFamily;
  final FontWeight fontWeight;

  const TypeFace({required this.fontFamily, required this.fontWeight});
}

abstract class Util {
  static Future<String> loadAsset(String filename) async {
    return await rootBundle.loadString('assets/$filename');
  }

  static int currentTimeMillis() {
    return DateTime.now().millisecondsSinceEpoch;
  }

  // ignore: non_constant_identifier_names
  static TypeFace REGULAR =
      const TypeFace(fontFamily: "OpenSans", fontWeight: FontWeight.w400);

  // ignore: non_constant_identifier_names
  static TypeFace LIGHT =
      const TypeFace(fontFamily: "OpenSans", fontWeight: FontWeight.w300);

  // ignore: non_constant_identifier_names
  static TypeFace BOLD =
      const TypeFace(fontFamily: "OpenSans", fontWeight: FontWeight.w700);

  // ignore: non_constant_identifier_names
  static TypeFace EXTRA_BOLD =
      const TypeFace(fontFamily: "OpenSans", fontWeight: FontWeight.w800);
}
