import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/nutrition_provider.dart';
import '../theme/app_theme.dart';

class WeightTrackingScreen extends StatefulWidget {
  const WeightTrackingScreen({super.key});

  @override
  State<WeightTrackingScreen> createState() => _WeightTrackingScreenState();
}

class _WeightTrackingScreenState extends State<WeightTrackingScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nutrition = context.watch<NutritionProvider>();
    final history = nutrition.weightHistory;

    final current = history.isNotEmpty
        ? (history.last['weight'] as num).toDouble()
        : null;
    final start = history.isNotEmpty
        ? (history.first['weight'] as num).toDouble()
        : null;
    final change =
        (current != null && start != null) ? current - start : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Weight Tracking')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Log weight ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Log Today\'s Weight',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.primary)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          hintText: 'Enter weight',
                          suffixText: 'kg',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        final w = double.tryParse(_ctrl.text);
                        if (w != null && w > 0) {
                          nutrition.logWeight(w);
                          _ctrl.clear();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Weight logged!')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                          minimumSize:
                              const Size(72, 54)),
                      child: const Text('Log'),
                    ),
                  ]),
                ],
              ),
            ),

            // ── Stats ────────────────────────────────────────────────────────
            if (current != null) ...[
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: _StatCard(
                        label: 'Current',
                        value: '${current.toStringAsFixed(1)} kg')),
                const SizedBox(width: 12),
                Expanded(
                    child: _StatCard(
                        label: 'Starting',
                        value: '${start!.toStringAsFixed(1)} kg')),
                const SizedBox(width: 12),
                Expanded(
                    child: _StatCard(
                        label: 'Change',
                        value:
                            '${change! >= 0 ? "+" : ""}${change.toStringAsFixed(1)} kg',
                        color: change <= 0
                            ? AppColors.accent
                            : AppColors.error)),
              ]),
            ],

            // ── Chart ────────────────────────────────────────────────────────
            if (history.length >= 2) ...[
              const SizedBox(height: 20),
              const Text('Last 30 Days',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.primary)),
              const SizedBox(height: 12),
              Container(
                height: 200,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _WeightChart(history: history),
              ),
            ],

            // ── History list ─────────────────────────────────────────────────
            if (history.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Log',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.primary)),
              const SizedBox(height: 8),
              ...history.reversed.take(10).map((e) {
                final date = DateTime.tryParse(e['date'] as String? ?? '');
                final dateStr = date != null
                    ? DateFormat('MMM d, y').format(date)
                    : '—';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.circle,
                          size: 8, color: AppColors.hintGreen),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(dateStr,
                              style: const TextStyle(
                                  color: AppColors.hintGreen,
                                  fontSize: 13))),
                      Text(
                          '${(e['weight'] as num).toStringAsFixed(1)} kg',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ],
                  ),
                );
              }),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard(
      {required this.label,
      required this.value,
      this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.hintGreen)),
        ],
      ),
    );
  }
}

class _WeightChart extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _WeightChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final recent = history.length > 30
        ? history.sublist(history.length - 30)
        : history;
    final spots = <FlSpot>[];
    for (int i = 0; i < recent.length; i++) {
      spots.add(FlSpot(i.toDouble(), (recent[i]['weight'] as num).toDouble()));
    }
    if (spots.length < 2) return const SizedBox.shrink();

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 2;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 2;

    return LineChart(LineChartData(
      minY: minY,
      maxY: maxY,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: AppColors.primary,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
              show: true, color: AppColors.primary.withAlpha(30)),
        ),
      ],
    ));
  }
}
