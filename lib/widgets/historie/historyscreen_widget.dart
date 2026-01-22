import 'package:easy_localization/src/public_ext.dart';
import 'package:flutter/material.dart';

class History extends StatelessWidget {
  const History({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
            margin:
                const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 20),
            decoration: const BoxDecoration(
                color: Color.fromRGBO(128, 212, 255, 1),
                borderRadius: BorderRadius.all(Radius.circular(10.0))),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      'history_title',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ).tr(),
                  ),
                ),
                Padding(
                    padding: const EdgeInsets.only(
                        left: 10, right: 10, top: 0, bottom: 10),
                    child: Text('history_long').tr())
              ],
            )),
      ],
    );
  }
}
