import 'package:flutter/material.dart';

/// Base abstract class for stateful widgets that display chart content
abstract class ActionState<T extends StatefulWidget> extends State<T> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: getBody());
  }

  Widget getBody();

  String getTitle();
}

/// Abstract class for pie chart action states
abstract class PieActionState<T extends StatefulWidget> extends ActionState<T> {
  @override
  String getTitle() {
    return '';
  }
}

/// Abstract class for line chart action states
abstract class LineActionState<T extends StatefulWidget> extends ActionState<T> {
  @override
  String getTitle() {
    return '';
  }
}

typedef CaptureCallback = void Function();
