import 'package:flutter/material.dart';
import 'package:iptasys_sleep_doctor_flutter/styles/text/roboto_text_style.dart';

class EntryField extends StatelessWidget {
  final String title;
  final TextEditingController controller;

  const EntryField({
    super.key,
    required this.title,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          RobotoBoldText(
            title: title,
            fontSize: 20,
            color: const Color.fromARGB(255, 0, 74, 153),
          ),
          const SizedBox(
            height: 10,
          ),
          TextField(
              controller: controller,
              decoration: const InputDecoration(
                  border: InputBorder.none,
                  fillColor: Color(0xfff3f3f4),
                  filled: true))
        ],
      ),
    );
  }
}
