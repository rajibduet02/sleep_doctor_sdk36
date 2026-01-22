import 'package:easy_localization/src/public_ext.dart';
import 'package:flutter/material.dart';
import 'package:iptasys_sleep_doctor_flutter/repositories/sleep_doctor_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iptasys_sleep_doctor_flutter/utils/debug_log_saver.dart';

import 'package:iptasys_sleep_doctor_flutter/repositories/sleep_doctor_repository_singleton_global.dart'
    as global;

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  var check = false;

  final SleepDoctorRepository _repository = global.sleepDoctorRepository;

  late Future<SharedPreferences> _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = SharedPreferences.getInstance();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: constraints.copyWith(
            minHeight: constraints.maxHeight,
            maxHeight: double.infinity,
          ),
          child: IntrinsicHeight(
            child: Column(
              children: <Widget>[
                Row(children: [
                  Flexible(
                    child: Container(
                      margin: const EdgeInsets.only(left: 80, right: 20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 20, top: 20),
                              child: Text('database',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium)
                                  .tr(),
                            ),
                            Text('clear_database',
                                    style:
                                        Theme.of(context).textTheme.labelLarge)
                                .tr(),
                            GestureDetector(
                                onTap: () {
                                  _showAlertDialogForDelete(context);
                                },
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('clear_database_long',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium)
                                          .tr(),
                                    ])),
                            Padding(
                              padding: const EdgeInsets.only(top: 20),
                              child: Text(
                                'send_database',
                                style: Theme.of(context).textTheme.titleSmall,
                              ).tr(),
                            ),
                            Text(
                              'send_database_long',
                              style: Theme.of(context).textTheme.titleSmall,
                            ).tr(),
                            Padding(
                              padding: const EdgeInsets.only(top: 20),
                              child: Text(
                                'Debug Logs',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  if (!mounted) return;
                                  
                                  try {
                                    final filePath = await saveDebugLogs(context);
                                    
                                    if (!mounted) return;
                                    
                                    if (filePath != null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Debug logs saved to Downloads/SleepDoctor'),
                                          backgroundColor: Colors.green,
                                          duration: Duration(seconds: 3),
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Unable to save debug logs. Please try again.'),
                                          backgroundColor: Colors.red,
                                          duration: Duration(seconds: 4),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (!mounted) return;
                                    
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Error saving debug logs'),
                                        backgroundColor: Colors.red,
                                        duration: Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.save),
                                label: const Text('Save Debug Logs'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color.fromRGBO(41, 98, 255, 1),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                'Save debug logs to file manager for manual sharing',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                const Divider(),
                Row(children: [
                  Flexible(
                    child: Container(
                      margin: const EdgeInsets.only(
                        left: 80,
                        right: 20,
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 20, top: 20),
                              child: Text('settings_privacy',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium)
                                  .tr(),
                            ),
                            Text('agreement',
                                    style:
                                        Theme.of(context).textTheme.labelLarge)
                                .tr(),
                            FutureBuilder<SharedPreferences>(
                                future: _prefs,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const SizedBox(
                                      width: 0.0,
                                      height: 0.0,
                                    );
                                  }
                                  
                                  if (snapshot.hasError) {
                                    return Text('Error: ${snapshot.error}');
                                  }
                                  
                                  if (snapshot.hasData) {
                                    final agreementValue = snapshot.data!
                                            .getBool("dev_feedback_agreement") ??
                                        false;
                                    return CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      value: agreementValue,
                                      title: Text('agreement_long',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium)
                                          .tr(),
                                      onChanged: (bool? check) {
                                        if (check != null) {
                                          _showAlertDialogForAcceptance(
                                              context, check);
                                        }
                                      },
                                    );
                                  }
                                  
                                  return const SizedBox(
                                    width: 0.0,
                                    height: 0.0,
                                  );
                                })
                          ]),
                    ),
                  )
                ]),
              ],
            ),
          ),
        ),
      );
    });
  }

  void _showAlertDialogForDelete(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('clear_database').tr(),
            content: Text('clear_database_question',
                    style: Theme.of(context).textTheme.bodyMedium)
                .tr(),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('cancel').tr(),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await _repository.clearSleepDoctorDatabase();
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      // Show success message
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Database cleared successfully').tr(),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error clearing database: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('ok').tr(),
              )
            ],
          );
        });
  }

  void _showAlertDialogForAcceptance(BuildContext context, bool value) async {
    final SharedPreferences prefs = await _prefs;

    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('agreement').tr(),
            scrollable: true,
            content: Text(
              'agreement_text',
              style: Theme.of(context).textTheme.bodyMedium,
            ).tr(),
            actions: [
              TextButton(
                onPressed: () async {
                  final newValue = false;
                  await prefs.setBool("dev_feedback_agreement", newValue);
                  if (context.mounted) {
                    setState(() {
                      check = newValue;
                    });
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('not_agree').tr(),
              ),
              TextButton(
                onPressed: () async {
                  final newValue = true;
                  await prefs.setBool("dev_feedback_agreement", newValue);
                  if (context.mounted) {
                    setState(() {
                      check = newValue;
                    });
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('agree').tr(),
              )
            ],
          );
        });
  }
}
