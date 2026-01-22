import 'package:easy_localization/src/public_ext.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class Info extends StatelessWidget {
  const Info({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
        child: SingleChildScrollView(
      child: Stack(children: <Widget>[
        Container(
          width: double.infinity,
          color: Theme.of(context).primaryColor,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'appName'.tr(),
                  style: TextStyle(
                      fontSize: 30,
                      color: Theme.of(context).colorScheme.secondary,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: FutureBuilder<String>(
                    future: versionBuildLabel(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          width: 0.0,
                          height: 0.0,
                        );
                      }
                      
                      if (snapshot.hasError) {
                        return Text(
                          'Version unknown',
                          style: TextStyle(
                              fontSize: 18,
                              color: Theme.of(context).colorScheme.secondary,
                              fontWeight: FontWeight.bold),
                        );
                      }
                      
                      if (snapshot.hasData) {
                        return Text(snapshot.data!,
                            style: TextStyle(
                                fontSize: 18,
                                color: Theme.of(context).colorScheme.secondary,
                                fontWeight: FontWeight.bold));
                      }
                      
                      return const SizedBox(
                        width: 0.0,
                        height: 0.0,
                      );
                    }),
              ),
              Image.asset("assets/images/IconTransparent.png"),
              Text(
                'app_developtime'.tr(),
                style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.secondary,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ]),
    ));
  }

  Future<String> versionBuildLabel() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    return "Version ${packageInfo.version} (${packageInfo.buildNumber})";
  }
}
