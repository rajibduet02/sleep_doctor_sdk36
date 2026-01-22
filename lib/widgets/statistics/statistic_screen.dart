import 'dart:core';
import 'package:easy_localization/src/public_ext.dart';
import 'package:flutter/material.dart';
import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/sleep_doctor_data.dart';
import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/states/sleep_doctor_states.dart';
import 'package:iptasys_sleep_doctor_flutter/widgets/statistics/pie_chart_widget.dart';
import 'package:iptasys_sleep_doctor_flutter/widgets/statistics/statistic_chart_widget.dart';
import 'package:iptasys_sleep_doctor_flutter/repositories/sleep_doctor_repository_singleton_global.dart'
    as global;
import 'package:iptasys_sleep_doctor_flutter/utils/app_state_notifier.dart';

import '../../repositories/sleep_doctor_repository.dart';

class Statistics extends StatefulWidget {
  const Statistics({super.key});

  @override
  State<Statistics> createState() => _StatisticsState();
}

class _StatisticsState extends State<Statistics> {
  final SleepDoctorRepository _repository = global.sleepDoctorRepository;
  final AppStateNotifier _appStateNotifier = AppStateNotifier();
  
  // Use a single Future that can be refreshed
  Future<List<SleepDoctorData>>? _dataFuture;
  bool _isLoading = false; // CRITICAL FIX: Prevent redundant loads

  @override
  void initState() {
    super.initState();
    // CRITICAL FIX: Defer database read until after first frame to prevent main thread blocking
    // This ensures UI remains responsive during startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadData();
      }
    });
    // Listen for data changes (sync completion, database clear)
    _appStateNotifier.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _appStateNotifier.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    // CRITICAL FIX: Ensure UI refreshes when data changes
    // This is called when AppStateNotifier fires after sync or database clear
    // Use postFrameCallback to ensure this happens after current frame completes
    // This prevents timing issues where notification fires before widget is ready
    // Also prevent redundant loads if already loading
    if (mounted && !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isLoading) {
          _loadData();
        }
      });
    }
  }

  void _loadData() {
    if (mounted && !_isLoading) {
      _isLoading = true;
      setState(() {
        // CRITICAL FIX: Create a NEW Future reference to ensure FutureBuilder rebuilds
        // FutureBuilder only rebuilds when the Future reference changes
        // By creating a new Future each time, we guarantee a rebuild
        // This ensures UI always reflects the latest database state
        _dataFuture = _repository.readAllSleepDoctorData().then((data) {
          _isLoading = false;
          return data;
        }).catchError((error) {
          _isLoading = false;
          throw error;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 20),
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
                      'sleep_quality'.tr(),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
                SizedBox(
                    height: 300,
                    width: MediaQuery.of(context).size.width,
                    child: FutureBuilder<List<SleepDoctorData>>(
                        future: _dataFuture,
                        builder: (BuildContext context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          
                          if (snapshot.hasError) {
                            return Center(
                              child: Text('Error: ${snapshot.error}'),
                            );
                          }
                          
                          if (snapshot.hasData) {
                            final data = snapshot.data!;
                            if (data.isNotEmpty) {
                              return Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: 15, left: 50, right: 50),
                                  child: SleepDoctorPieChart(data: data));
                            } else {
                              return Center(
                                  child: Text('noData').tr());
                            }
                          }
                          
                          return Center(child: Text('noData').tr());
                        }))
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 20),
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
                      'sleep_phases',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ).tr(),
                  ),
                ),
                SizedBox(
                    height: 300,
                    width: MediaQuery.of(context).size.width,
                    child: FutureBuilder<List<SleepDoctorData>>(
                        future: _dataFuture,
                        builder: (BuildContext context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          
                          if (snapshot.hasError) {
                            return Center(
                              child: Text('Error: ${snapshot.error}'),
                            );
                          }
                          
                          if (snapshot.hasData) {
                            final data = snapshot.data!;
                            if (data.isNotEmpty) {
                              return Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: 15, left: 50, right: 50),
                                  child: SleepDoctorDataChart(
                                    data: data,
                                    dataType: SleepDoctorDataType.SLEEP_PHASE,
                                    color: const Color.fromRGBO(198, 41, 255, 1),
                                  ));
                            } else {
                              return Center(
                                  child: Text('noData').tr());
                            }
                          }
                          
                          return Center(child: Text('noData').tr());
                        }))
              ],
            ),
          ),
          Container(
              margin: const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 20),
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
                        'orientation'.tr(),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ),
                  SizedBox(
                      height: 300,
                      width: MediaQuery.of(context).size.width,
                      child: FutureBuilder<List<SleepDoctorData>>(
                          future: _dataFuture,
                          builder: (BuildContext context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            
                            if (snapshot.hasError) {
                              return Center(
                                child: Text('Error: ${snapshot.error}'),
                              );
                            }
                            
                            if (snapshot.hasData) {
                              final data = snapshot.data!;
                              if (data.isNotEmpty) {
                                return Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: 15, left: 60, right: 60),
                                    child: SleepDoctorDataChart(
                                        data: data,
                                        dataType:
                                            SleepDoctorDataType.ORIENTATION,
                                        color:
                                            const Color.fromRGBO(255, 198, 41, 1)));
                              } else {
                                return Center(
                                    child: const Text('noData').tr());
                              }
                            }
                            
                            return Center(child: Text('noData').tr());
                          })),
                ],
              )),
          Container(
              margin: const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 20),
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
                        'apnoe_phases',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ).tr(),
                    ),
                  ),
                  SizedBox(
                      height: 300,
                      width: MediaQuery.of(context).size.width,
                      child: FutureBuilder<List<SleepDoctorData>>(
                          future: _dataFuture,
                          builder: (BuildContext context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            
                            if (snapshot.hasError) {
                              return Center(
                                child: Text('Error: ${snapshot.error}'),
                              );
                            }
                            
                            if (snapshot.hasData) {
                              final data = snapshot.data!;
                              if (data.isNotEmpty) {
                                return Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: 15, left: 50, right: 50),
                                    child: SleepDoctorDataChart(
                                      data: data,
                                      dataType: SleepDoctorDataType.MODE,
                                      modeState:
                                          SleepDoctorModeState.MODE_APNOE,
                                      color: const Color.fromRGBO(255, 41, 98, 1),
                                    ));
                              } else {
                                return Center(
                                    child: const Text('noData').tr());
                              }
                            }
                            
                            return Center(child: Text('noData').tr());
                          }))
                ],
              )),
          Container(
              margin: const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 20),
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
                        'snorin',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ).tr(),
                    ),
                  ),
                  SizedBox(
                      height: 300,
                      width: MediaQuery.of(context).size.width,
                      child: FutureBuilder<List<SleepDoctorData>>(
                          future: _dataFuture,
                          builder: (BuildContext context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            
                            if (snapshot.hasError) {
                              return Center(
                                child: Text('Error: ${snapshot.error}'),
                              );
                            }
                            
                            if (snapshot.hasData) {
                              final data = snapshot.data!;
                              if (data.isNotEmpty) {
                                return Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: 15, left: 50, right: 50),
                                    child: SleepDoctorDataChart(
                                      data: data,
                                      dataType: SleepDoctorDataType.MODE,
                                      modeState:
                                          SleepDoctorModeState.MODE_SNORE,
                                      color: const Color.fromRGBO(198, 41, 255, 1),
                                    ));
                              } else {
                                return Center(
                                    child: const Text('noData').tr());
                              }
                            }
                            
                            return Center(child: Text('noData').tr());
                          }))
                ],
              )),
          Container(
              margin: const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 20),
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
                        'device_activities',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ).tr(),
                    ),
                  ),
                  SizedBox(
                      height: 300,
                      width: MediaQuery.of(context).size.width,
                      child: FutureBuilder<List<SleepDoctorData>>(
                          future: _dataFuture,
                          builder: (BuildContext context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            
                            if (snapshot.hasError) {
                              return Center(
                                child: Text('Error: ${snapshot.error}'),
                              );
                            }
                            
                            if (snapshot.hasData) {
                              final data = snapshot.data!;
                              if (data.isNotEmpty) {
                                return Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: 15, left: 50, right: 50),
                                    child: SleepDoctorDataChart(
                                      data: data,
                                      dataType: SleepDoctorDataType.STIMULATION,
                                      color: const Color.fromRGBO(89, 41, 255, 1),
                                    ));
                              } else {
                                return Center(
                                    child: const Text('noData').tr());
                              }
                            }
                            
                            return Center(child: Text('noData').tr());
                          }))
                ],
              )),
        ],
      ),
    );
  }
}

class SleepQualityDescription extends StatelessWidget {
  const SleepQualityDescription({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('sleep_quality').tr()),
        body: Column(
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
                          'sleep_quality',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ).tr(),
                      ),
                    ),
                    Padding(
                        padding: const EdgeInsets.only(
                            left: 10, right: 10, top: 0, bottom: 10),
                        child: Text(
                          'sleep_quality_description',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ).tr())
                  ],
                )),
          ],
        ));
  }
}

class SleepPhasesDescription extends StatelessWidget {
  const SleepPhasesDescription({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('sleep_phases').tr()),
        body: Column(
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
                          'sleep_phases',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ).tr(),
                      ),
                    ),
                    Padding(
                        padding: const EdgeInsets.only(
                            left: 10, right: 10, top: 0, bottom: 10),
                        child: Text(
                          'sleep_phases_description',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ).tr())
                  ],
                )),
          ],
        ));
  }
}

class SleepOrientationDescription extends StatelessWidget {
  const SleepOrientationDescription({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('orientation').tr()),
        body: Column(
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
                          'orientation',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ).tr(),
                      ),
                    ),
                    Padding(
                        padding: const EdgeInsets.only(
                            left: 10, right: 10, top: 0, bottom: 10),
                        child: Text(
                          'orientation_description',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ).tr())
                  ],
                )),
          ],
        ));
  }
}
