import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/sleep_doctor_data.dart';
import 'package:iptasys_sleep_doctor_flutter/models/sleepdoctor/states/sleep_doctor_states.dart';
import 'package:intl/intl.dart' as intl;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:tuple/tuple.dart';

class SleepDoctorDataChart extends StatefulWidget {
  final List<SleepDoctorData>? data;
  final SleepDoctorDataType? dataType;
  final Color? color;
  final Tuple2<int, String>? modeState;

  const SleepDoctorDataChart({
    super.key,
    this.data,
    this.dataType,
    this.color,
    this.modeState,
  });

  @override
  State<SleepDoctorDataChart> createState() => _SleepDoctorDataChartState();
}

class _SleepDoctorDataChartState extends State<SleepDoctorDataChart> {
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
    var dataWithoutChargeState = _removeOrientationCharge(sortedData);
    var filteredData = _filterSleepDoctorData(dataWithoutChargeState);
    var data = _transformSleepDoctorDataIntoDataPoints(filteredData);

    return StatisticLineChart(
      data: data,
      chartDescription: widget.dataType != null 
          ? SleepDoctorDataTypeRaw.typeDescription(widget.dataType!) 
          : '',
      dataType: widget.dataType,
      color: widget.color ?? Colors.blue,
      modeState: widget.modeState,
      minYValue: _getMinYChartValue(widget.dataType).toDouble(),
      maxYValue: _getMaxYChartValue(widget.dataType).toDouble(),
    );
  }

  int _getMaxYChartValue(SleepDoctorDataType? dataType) {
    if (dataType == null) return 0;
    switch (dataType) {
      case SleepDoctorDataType.MODE:
        if (widget.modeState == SleepDoctorModeState.MODE_SNORE) {
          return 3;
        } else if (widget.modeState == SleepDoctorModeState.MODE_APNOE) {
          return 2;
        } else if (widget.modeState == SleepDoctorModeState.MODE_TIME) {
          return 0;
        } else if (widget.modeState == SleepDoctorModeState.MODE_SIDLE) {
          return 1;
        } else {
          return 0;
        }
      case SleepDoctorDataType.ORIENTATION:
        return SleepDoctorDataTypeLabels.typeLabels(dataType).length - 1;
      case SleepDoctorDataType.STIMULATION:
        return 1;
      case SleepDoctorDataType.SLEEP_PHASE:
        return SleepDoctorDataTypeLabels.typeLabels(dataType).length - 1;
      default:
        return 0;
    }
  }

  int _getMinYChartValue(SleepDoctorDataType? dataType) {
    if (dataType == null) return 0;
    switch (dataType) {
      case SleepDoctorDataType.MODE:
        if (widget.modeState == SleepDoctorModeState.MODE_SNORE) {
          return 1;
        } else if (widget.modeState == SleepDoctorModeState.MODE_APNOE) {
          return 1;
        } else if (widget.modeState == SleepDoctorModeState.MODE_TIME) {
          return 0;
        } else if (widget.modeState == SleepDoctorModeState.MODE_SIDLE) {
          return 0;
        } else {
          return 0;
        }
      case SleepDoctorDataType.ORIENTATION:
        return 0;
      case SleepDoctorDataType.STIMULATION:
        return 0;
      case SleepDoctorDataType.SLEEP_PHASE:
        return 0;
      default:
        return 0;
    }
  }

  List<SleepDoctorData> _sortSleepDoctorData(List<SleepDoctorData> data) {
    data.sort((a, b) {
      return a.fromTime.compareTo(b.fromTime);
    });
    return data;
  }

  List<SleepDoctorData> _filterSleepDoctorData(List<SleepDoctorData> data) {
    List<SleepDoctorData> filteredData = <SleepDoctorData>[];

    if (data.length > 1) {
      var d1 = data[0].fromTime.millisecondsSinceEpoch;
      for (var i = 1; i < data.length; i++) {
        var d2 = data[i].fromTime.millisecondsSinceEpoch;
        if (d2 - d1 >= 10 * 1000) {
          filteredData.add(data[i]);
        }
        d1 = d2;
      }
    }

    return filteredData;
  }

  List<SleepDoctorData> _removeOrientationCharge(List<SleepDoctorData> data) {
    for (var i = 1; i < data.length; i++) {
      if (data[i].orientation == SleepDoctorOrientationState.ORIENTATION_CHARGE_O.item1) {
        data[i].orientation = data[i - 1].orientation;
      }
    }
    return data;
  }

  List<FlSpot> _transformSleepDoctorDataIntoDataPoints(
      List<SleepDoctorData> data) {
    if (widget.dataType == SleepDoctorDataType.MODE) {
      return data
          .where((element) =>
              element.valueOf(SleepDoctorDataType.MODE) ==
                  widget.modeState?.item1 ||
              element.valueOf(SleepDoctorDataType.MODE) ==
                  SleepDoctorModeState.MODE_SIDLE.item1)
          .map((entry) {
            var value = entry.valueOf(widget.dataType!);
            return [
              FlSpot(
                  entry.fromTime.microsecondsSinceEpoch.toDouble(), value),
              FlSpot(entry.toTime.microsecondsSinceEpoch.toDouble(), value)
            ];
          })
          .expand((element) => element)
          .toList();
    } else {
      return data.map((entry) {
        var value = entry.valueOf(widget.dataType!);
        return [
          FlSpot(entry.fromTime.microsecondsSinceEpoch.toDouble(), value),
          FlSpot(entry.toTime.microsecondsSinceEpoch.toDouble(), value)
        ];
      }).expand((element) => element).toList();
    }
  }
}

class StatisticLineChart extends StatefulWidget {
  final List<FlSpot> data;
  final String chartDescription;
  final SleepDoctorDataType? dataType;
  final Color color;
  final Tuple2<int, String>? modeState;
  final Tuple2<int, String>? orientationState;
  final double minYValue;
  final double maxYValue;

  const StatisticLineChart({
    super.key,
    required this.data,
    required this.chartDescription,
    this.dataType,
    required this.color,
    this.modeState,
    this.orientationState,
    required this.minYValue,
    required this.maxYValue,
  });

  @override
  State<StatisticLineChart> createState() => _StatisticLineChartState();
}

class _StatisticLineChartState extends State<StatisticLineChart> {
  double minXValue = 0.0;
  double maxXValue = 0.0;

  @override
  void initState() {
    super.initState();
    _setExtremePoints(widget.data);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color.fromRGBO(128, 212, 255, 1),
      child: LineChart(
        LineChartData(
          minY: widget.minYValue,
          maxY: widget.maxYValue,
          minX: minXValue,
          maxX: maxXValue,
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return _getYAxisLabel(value);
                },
              ),
            ),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return _getYAxisLabel(value);
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  return _getXAxisLabel(value);
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: widget.data.isEmpty
                  ? [const FlSpot(0, 0)]
                  : widget.data,
              isCurved: false,
              isStepLineChart: true,
              color: widget.color,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: widget.color.withAlpha(64),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _getYAxisLabel(double value) {
    final index = value.floor();
    String label = '';
    
    if (widget.dataType != null) {
      final labels = SleepDoctorDataTypeLabels.typeLabels(widget.dataType!);
      
      if (labels.contains(SleepDoctorModeState.MODE_APNOE) &&
          labels.contains(SleepDoctorModeState.MODE_SNORE)) {
        label = '';
      } else if (labels.contains(SleepDoctorStimulationState.STIMULATION_OFF)) {
        label = '';
      } else if (index >= 0 && index < labels.length) {
        label = labels[index].item2;
      }
    }
    
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: Colors.black,
      ),
    );
  }

  Widget _getXAxisLabel(double value) {
    final formatter = intl.DateFormat("HH:mm");
    final dateTime = DateTime.fromMicrosecondsSinceEpoch(value.toInt());
    return Text(
      formatter.format(dateTime),
      style: const TextStyle(fontSize: 10, color: Colors.black),
    );
  }

  void _setExtremePoints(List<FlSpot> data) {
    if (data.isEmpty) {
      return;
    }

    maxXValue = data.map((entry) => entry.x).reduce(max);
    minXValue = data.map((entry) => entry.x).reduce(min);
  }
}
