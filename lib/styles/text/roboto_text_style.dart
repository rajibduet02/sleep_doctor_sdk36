import 'package:flutter/material.dart';

class RobotoText extends StatelessWidget {
  final String title;
  final double fontSize;
  final Color color;

  const RobotoText({
    super.key,
    required this.fontSize,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: "Roboto",
          color: color,
        ));
  }
}

class RobotoBoldText extends StatelessWidget {
  final String title;
  final double fontSize;
  final Color color;

  const RobotoBoldText({
    super.key,
    required this.fontSize,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: TextStyle(
            fontSize: fontSize,
            fontFamily: "Roboto",
            color: color,
            fontWeight: FontWeight.w700));
  }
}
