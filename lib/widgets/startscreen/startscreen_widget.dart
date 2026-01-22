import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:iptasys_sleep_doctor_flutter/interfaces/routable.dart';
import 'package:iptasys_sleep_doctor_flutter/repositories/sleep_doctor_repository.dart';
import 'package:iptasys_sleep_doctor_flutter/widgets/appBarMenu/info_widget.dart';
import 'package:iptasys_sleep_doctor_flutter/widgets/appBarMenu/settings_widget.dart';
import 'package:iptasys_sleep_doctor_flutter/widgets/historie/historyscreen_widget.dart';

import 'package:iptasys_sleep_doctor_flutter/repositories/sleep_doctor_repository_singleton_global.dart'
    as global;
import 'package:iptasys_sleep_doctor_flutter/widgets/statistics/statistic_screen.dart';
import 'package:iptasys_sleep_doctor_flutter/widgets/syncscreen/syncscreen_widget.dart';

class StartScreen extends StatefulWidget implements Routable {
  static String ROUTE_ID = "/StartScreenWidget";

  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _MainState();
}

class _MainState extends State<StartScreen> {
  final SleepDoctorRepository _repository = global.sleepDoctorRepository;

  bool selectedItemAppBar = false;
  int indexApp = 0;

  int indexBottom = 0;

  // Remove unused data list - Statistics handles its own data now
  @override
  void initState() {
    super.initState();
  }

  List<Widget> tabPages = [
    const Statistics(),
    const History(),
    const SyncScreen(),
    const Settings(),
    const Info(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          centerTitle: false,
          title: const Text(
            'SleepDoctor',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: <Widget>[
            PopupMenuButton<int>(
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 3,
                  child: Text(
                    tr('settings'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                PopupMenuItem(
                  value: 4,
                  child: Text('appInfo',
                          style: Theme.of(context).textTheme.bodyMedium)
                      .tr(),
                ),
              ],
              onSelected: (value) {
                appBarWidget(value);
                indexApp = value;
              },
              icon: const Icon(Icons.more_vert),
            )
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: indexBottom,
          unselectedItemColor: const Color.fromRGBO(115, 115, 115, 1),
          selectedItemColor: selectedItemAppBar
              ? const Color.fromRGBO(115, 115, 115, 1)
              : Colors.blue,
          onTap: _onItemTapped,
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: const Icon(Icons.home),
              label: 'start'.tr(),
            ),
            BottomNavigationBarItem(
              icon: const Icon(
                Icons.calendar_today_outlined,
              ),
              label: 'history'.tr(),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.sync),
              label: 'synchronize'.tr(),
            ),
          ],
        ),
        body: SafeArea(child: bodyWidget(indexApp, indexBottom)));
  }

  appBarWidget(int value) {
    switch (value) {
      case 3:
        setState(() {
          selectedItemAppBar = true;
          indexApp = 3;
        });
        break;
      case 4:
        setState(() {
          selectedItemAppBar = true;
          indexApp = 4;
        });
        break;
    }
  }

  Widget bodyWidget(int indexApp, int indexBottom) {
    if (indexApp == 3) {
      return tabPages.elementAt(3);
    }
    if (indexApp == 4) {
      return tabPages.elementAt(4);
    }
    if (indexBottom == 0) {
      return tabPages.elementAt(0);
    }
    if (indexBottom == 1) {
      return tabPages.elementAt(1);
    }
    if (indexBottom == 2) {
      return tabPages.elementAt(2);
    }
    return tabPages.elementAt(0);
  }

  void _onItemTapped(int index) {
    setState(() {
      indexBottom = index;
      selectedItemAppBar = false;
      indexApp = 0;
    });
  }
}
