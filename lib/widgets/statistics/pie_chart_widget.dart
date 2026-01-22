import 'package:flutter/material.dart';
import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/sleep_doctor_data.dart';
import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/states/sleep_doctor_states.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:tuple/tuple.dart';

class SleepDoctorPieChart extends StatefulWidget {
  final List<SleepDoctorData>? data;
  final SleepDoctorDataType? dataType;
  final double? sleepQuality;
  final Tuple2<int, String>? sleepPhase;

  SleepDoctorPieChart({
    super.key,
    this.data,
    this.dataType,
    this.sleepQuality,
    this.sleepPhase,
  });

  @override
  State<SleepDoctorPieChart> createState() => _SleepDoctorPieChartState();
}

class _SleepDoctorPieChartState extends State<SleepDoctorPieChart> {
  final List<SleepDoctorData> sortedData = <SleepDoctorData>[];

  @override
  void initState() {
    super.initState();
    sortedData.clear();
    if (widget.data != null) {
      sortedData.addAll(_sortSleepDoctorData(widget.data!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final calculatedSleepQuality = _calculateSleepQuality(sortedData);

    return StatisticPieChart(
      sleepQuality: calculatedSleepQuality,
    );
  }

  List<SleepDoctorData> _sortSleepDoctorData(List<SleepDoctorData> data) {
    data.sort((a, b) {
      return a.fromTime.compareTo(b.fromTime);
    });
    return data;
  }

  double _calculateSleepQuality(List<SleepDoctorData> data) {
    double completeDeepSleepTime = 0.0;
    double completeSleepTime = 0.0;

    for (var entry in data) {
      if (entry.orientation !=
          SleepDoctorOrientationState.ORIENTATION_CHARGE_O.item1) {
        if (entry.sleepPhase == SleepDoctorSleepPhaseState.PHASE_DEEP.item1) {
          completeDeepSleepTime +=
              entry.toTime.microsecondsSinceEpoch - entry.fromTime.microsecondsSinceEpoch;
        }
        completeSleepTime +=
            entry.toTime.microsecondsSinceEpoch - entry.fromTime.microsecondsSinceEpoch;
      }
    }

    if (completeSleepTime == 0) return 0;
    return completeDeepSleepTime / completeSleepTime;
  }
}

class StatisticPieChart extends StatefulWidget {
  final double sleepQuality;

  const StatisticPieChart({
    super.key,
    required this.sleepQuality,
  });

  @override
  State<StatisticPieChart> createState() => _StatisticPieChartState();
}

class _StatisticPieChartState extends State<StatisticPieChart> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color.fromRGBO(128, 212, 255, 1),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: PieChart(
              PieChartData(
                sectionsSpace: 0,
                centerSpaceRadius: 58,
                startDegreeOffset: -90,
                sections: _buildSections(),
              ),
            ),
          ),
          Center(
            child: Text(
              _generateCenterSpannableText(widget.sleepQuality),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color.fromRGBO(89, 41, 255, 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildSections() {
    Color qualityColor;
    if (widget.sleepQuality < 0.05) {
      qualityColor = Colors.red;
    } else if (widget.sleepQuality < 0.25) {
      qualityColor = Colors.yellow;
    } else {
      qualityColor = Colors.green;
    }

    return [
      PieChartSectionData(
        value: widget.sleepQuality * 100,
        color: qualityColor,
        showTitle: false,
        radius: 40,
      ),
      PieChartSectionData(
        value: (1 - widget.sleepQuality) * 100,
        color: Colors.transparent,
        showTitle: false,
        radius: 40,
      ),
    ];
  }

  String _generateCenterSpannableText(double value) {
    var percentage = value * 100;
    return "${percentage.toStringAsFixed(2)}%";
  }
}
