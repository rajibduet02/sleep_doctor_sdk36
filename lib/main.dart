import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iptasys_sleep_doctor_flutter/widgets/startscreen/startscreen_widget.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/app_config.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/app_lifecycle_manager.dart';
import 'package:iptasys_sleep_doctor_flutter/core/debug/debug_logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  
  // Initialize debug logger
  await DebugLogger.init();
  
  // Initialize app lifecycle manager for BLE stability
  AppLifecycleManager().initialize();
  
  //Set status bar and icons color (The safe area solution doesn't work for Android.)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark));
  runApp(
    EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('de'), Locale('fr')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: const SleepDoctorApp()),
  );
}

class SleepDoctorApp extends StatelessWidget {
  const SleepDoctorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      title: AppConfig.appTitle,
      theme: ThemeData(
        primaryColor: const Color.fromRGBO(41, 98, 255, 1),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromRGBO(41, 98, 255, 1),
          secondary: const Color.fromRGBO(255, 198, 41, 1),
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(
              fontSize: 16.0,
              fontWeight: FontWeight.bold,
              color: Color.fromRGBO(0, 51, 204, 1)),
          bodyMedium: TextStyle(
            fontSize: 14.0,
          ),
          titleMedium: TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: 14,
              color: Color.fromRGBO(255, 198, 41, 1)),
          titleSmall:
              TextStyle(fontSize: 14, color: Color.fromRGBO(169, 169, 169, 1)),
        ),
      ),
      home: const StartScreen(),
      routes: <String, WidgetBuilder>{
        //TODO add routes
      },
    );
  }
}
