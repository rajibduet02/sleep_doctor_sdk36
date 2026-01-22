import 'package:flutter/material.dart';
import 'package:iptasys_sleep_doctor_flutter/styles/text/roboto_text_style.dart';

class SecureEntryField extends StatefulWidget {
  final TextEditingController controller;
  final String title;

  const SecureEntryField({
    super.key,
    required this.title,
    required this.controller,
  });

  @override
  State<SecureEntryField> createState() => _SecureEntryFieldState();
}

class _SecureEntryFieldState extends State<SecureEntryField> {
  // Initially password is obscure
  bool _obscureText = true;
  IconData _icon = Icons.remove_red_eye_outlined;

  // Toggles the password show status
  void _toggle() {
    setState(() {
      _obscureText = !_obscureText;
      _icon = _obscureText ? Icons.visibility : Icons.visibility_off_outlined;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          RobotoBoldText(
            title: widget.title,
            fontSize: 20,
            color: const Color.fromARGB(255, 0, 74, 153),
          ),
          const SizedBox(
            height: 10,
          ),
          TextFormField(
            decoration: InputDecoration(
                suffixIcon: IconButton(
                  icon: Icon(
                    _icon,
                    color: const Color.fromARGB(255, 0, 74, 153),
                  ),
                  onPressed: _toggle,
                ),
                border: InputBorder.none,
                fillColor: const Color(0xfff3f3f4),
                filled: true),
            obscureText: _obscureText,
            controller: widget.controller,
          ),
        ],
      ),
    );
  }
}
