import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';
class VoltageSensorTab extends StatelessWidget {
  const VoltageSensorTab({super.key});

  SupabaseClient get supabase => Supabase.instance.client;

  String formatTime(dynamic createdAt) {
    if (createdAt == null) return 'N/A';

    try {
      final date = DateTime.parse(createdAt.toString()).toLocal();
      return DateFormat('hh:mm:ss a').format(date);
    } catch (_) {
      return 'N/A';
    }
  }

  Color getVoltageColor(String status) {
    switch (status.toUpperCase()) {
      case 'NORMAL':
        return Colors.green;
      case 'LOW':
        return Colors.orange;
      case 'POWER_OUTAGE':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData getVoltageIcon(String status) {
    switch (status.toUpperCase()) {
      case 'NORMAL':
        return Icons.bolt;
      case 'LOW':
        return Icons.warning_amber_rounded;
      case 'POWER_OUTAGE':
        return Icons.power_off;
      default:
        return Icons.electrical_services;
    }
  }

  Widget buildInfoCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withOpacity(0.12),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildVoltageChart(List<Map<String, dynamic>> readings) {
    if (readings.length < 2) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          'Need more readings to draw chart',
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    }

    final voltages = readings
        .map((row) => double.tryParse(row['voltage'].toString()) ?? 0.0)
        .toList();

    return Container(
      height: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: CustomPaint(
        painter: VoltageChartPainter(voltages),
        child: Container(),
      ),
    );
  }

  Widget buildReadingTile(Map<String, dynamic> reading) {
    final status = (reading['status'] ?? 'UNKNOWN').toString();
    final color = getVoltageColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withOpacity(0.12),
            child: Icon(getVoltageIcon(status), color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${reading['voltage']} V',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ADC: ${reading['adc_value'] ?? 'N/A'}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                Text(
                  formatTime(reading['created_at']),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                reading['battery_active'] == true
                    ? 'Battery ON'
                    : 'Battery OFF',
                style: TextStyle(
                  fontSize: 12,
                  color: reading['battery_active'] == true
                      ? Colors.red
                      : Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final voltageStream = supabase
        .from('voltage sensor')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(50);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: voltageStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error loading voltage data:\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final readings = snapshot.data!;

        if (readings.isEmpty) {
          return Center(
            child: Text(
              'No voltage readings yet',
              style: TextStyle(
                fontSize: 17,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }

        final latest = readings.first;
        final latestVoltage =
            double.tryParse(latest['voltage'].toString()) ?? 0.0;
        final latestStatus = (latest['status'] ?? 'UNKNOWN').toString();
        final batteryActive = latest['battery_active'] == true;
        final statusColor = getVoltageColor(latestStatus);

        final chartReadings = readings.reversed.toList();
        final totalReadings = readings.length;

        final outageCount = readings
            .where((r) =>
                (r['status'] ?? '').toString().toUpperCase() == 'POWER_OUTAGE')
            .length;

        final normalCount = readings
            .where((r) =>
                (r['status'] ?? '').toString().toUpperCase() == 'NORMAL')
            .length;

        final outagePercentage =
            totalReadings == 0 ? 0 : (outageCount / totalReadings) * 100;

        final stabilityPercentage =
            totalReadings == 0 ? 0 : (normalCount / totalReadings) * 100;

        final averageVoltage = readings
                .map((r) => double.tryParse(r['voltage'].toString()) ?? 0)
                .reduce((a, b) => a + b) /
            totalReadings;
        return RefreshIndicator(
          onRefresh: () async {},
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.15),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: statusColor.withOpacity(0.12),
                      child: Icon(
                        getVoltageIcon(latestStatus),
                        color: statusColor,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Live Voltage Monitor',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${latestVoltage.toStringAsFixed(2)} V',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Last update: ${formatTime(latest['created_at'])}',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  buildInfoCard(
                    title: 'Status',
                    value: latestStatus,
                    icon: getVoltageIcon(latestStatus),
                    color: statusColor,
                  ),
                  const SizedBox(width: 12),
                  buildInfoCard(
                    title: 'Backup',
                    value: batteryActive ? 'ON' : 'OFF',
                    icon: batteryActive
                        ? Icons.battery_charging_full
                        : Icons.battery_5_bar,
                    color: batteryActive ? Colors.red : Colors.green,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  buildInfoCard(
                    title: 'Power Stability',
                    value: '${stabilityPercentage.toStringAsFixed(0)}%',
                    icon: Icons.shield,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 12),
                  buildInfoCard(
                    title: 'Outage Rate',
                    value: '${outagePercentage.toStringAsFixed(0)}%',
                    icon: Icons.power_off,
                    color: Colors.red,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  buildInfoCard(
                    title: 'Average Voltage',
                    value: '${averageVoltage.toStringAsFixed(2)} V',
                    icon: Icons.show_chart,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 12),
                  buildInfoCard(
                    title: 'Detected Outages',
                    value: '$outageCount',
                    icon: Icons.warning_amber_rounded,
                    color: Colors.orange,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              const Text(
                'Voltage Live Chart',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              buildVoltageChart(chartReadings),

              const SizedBox(height: 18),

              const Text(
                'Recent Readings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              ...readings.map(buildReadingTile),
            ],
          ),
        );
      },
    );
  }
}

class VoltageChartPainter extends CustomPainter {
  final List<double> voltages;

  VoltageChartPainter(this.voltages);

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1.2;

    final normalLinePaint = Paint()
      ..color = Colors.green.withOpacity(0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final lowLinePaint = Paint()
      ..color = Colors.orange.withOpacity(0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final chartPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(
      textDirection: ui.TextDirection.ltr,
    );

    const double maxVoltage = 5.0;
    const double minVoltage = 0.0;

    double mapY(double voltage) {
      final normalized = (voltage - minVoltage) / (maxVoltage - minVoltage);
      return size.height - (normalized * size.height);
    }

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axisPaint,
    );

    canvas.drawLine(
      Offset(0, 0),
      Offset(0, size.height),
      axisPaint,
    );

    final y5v = mapY(5.0);
    final y2v = mapY(2.0);

    canvas.drawLine(
      Offset(0, y5v),
      Offset(size.width, y5v),
      normalLinePaint,
    );

    canvas.drawLine(
      Offset(0, y2v),
      Offset(size.width, y2v),
      lowLinePaint,
    );

    textPainter.text = const TextSpan(
      text: '12V Normal',
      style: TextStyle(color: Colors.green, fontSize: 11),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(6, y5v + 4));

    textPainter.text = const TextSpan(
      text: '1V Outage Threshold',
      style: TextStyle(color: Colors.orange, fontSize: 11),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(6, y2v + 4));

    if (voltages.length < 2) return;

    final path = Path();

    for (int i = 0; i < voltages.length; i++) {
      final x = (i / (voltages.length - 1)) * size.width;
      final y = mapY(voltages[i].clamp(minVoltage, maxVoltage));

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }

      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
    }

    canvas.drawPath(path, chartPaint);
  }

  @override
  bool shouldRepaint(covariant VoltageChartPainter oldDelegate) {
    return oldDelegate.voltages != voltages;
  }
}