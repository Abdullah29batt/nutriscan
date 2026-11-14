import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

class FastingScreen extends StatefulWidget {
  const FastingScreen({super.key});

  @override
  State<FastingScreen> createState() => _FastingScreenState();
}

class _FastingScreenState extends State<FastingScreen> {
  // Protocol: [fastHours, eatHours]
  static const _protocols = {
    '16:8': [16, 8],
    '18:6': [18, 6],
    '20:4': [20, 4],
    '24hr': [24, 0],
  };

  String _selectedProtocol = '16:8';
  bool _isRunning = false;
  DateTime? _startTime;
  TimeOfDay _lastMealTime = TimeOfDay.now();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  int _streak = 0;

  int get _fastHours => _protocols[_selectedProtocol]![0];
  Duration get _fastDuration => Duration(hours: _fastHours);

  double get _progress {
    if (_startTime == null) return 0;
    final ratio = _elapsed.inSeconds / _fastDuration.inSeconds;
    return ratio.clamp(0.0, 1.0);
  }

  bool get _inFastingWindow => _elapsed < _fastDuration;

  String get _stateLabel => _inFastingWindow ? 'Fasting' : 'Eating Window';

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    // Load from local immediately
    final prefs = await SharedPreferences.getInstance();
    final startMs = prefs.getInt('fasting_start');
    final running = prefs.getBool('fasting_running') ?? false;
    _streak = prefs.getInt('fasting_streak') ?? 0;
    _selectedProtocol = prefs.getString('fasting_protocol') ?? '16:8';

    if (running && startMs != null) {
      _startTime = DateTime.fromMillisecondsSinceEpoch(startMs);
      _isRunning = true;
      _elapsed = DateTime.now().difference(_startTime!);
      _startTicker();
    }
    if (mounted) setState(() {});

    // Background Firestore refresh
    _refreshFromFirestore(prefs);
  }

  Future<void> _refreshFromFirestore(SharedPreferences prefs) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fasting')
          .doc('state')
          .get();
      if (!doc.exists || !mounted) return;
      final data = doc.data()!;
      // Only restore from Firestore if not currently running locally
      if (!_isRunning) {
        final fsRunning = data['isRunning'] as bool? ?? false;
        final fsStartMs = data['startMs'] as int?;
        final fsStreak = (data['streak'] as num?)?.toInt() ?? _streak;
        final fsProtocol = data['protocol'] as String? ?? _selectedProtocol;
        // Sync streak and protocol always; restore active fast only if running
        await prefs.setInt('fasting_streak', fsStreak);
        await prefs.setString('fasting_protocol', fsProtocol);
        if (fsRunning && fsStartMs != null) {
          await prefs.setBool('fasting_running', true);
          await prefs.setInt('fasting_start', fsStartMs);
        }
        if (mounted) {
          setState(() {
            _streak = fsStreak;
            _selectedProtocol = fsProtocol;
            if (fsRunning && fsStartMs != null) {
              _startTime = DateTime.fromMillisecondsSinceEpoch(fsStartMs);
              _isRunning = true;
              _elapsed = DateTime.now().difference(_startTime!);
              _startTicker();
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveState() async {
    // Write locally immediately
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fasting_running', _isRunning);
    await prefs.setString('fasting_protocol', _selectedProtocol);
    await prefs.setInt('fasting_streak', _streak);
    if (_startTime != null) {
      await prefs.setInt(
          'fasting_start', _startTime!.millisecondsSinceEpoch);
    }
    // Background Firestore sync
    _syncToFirestore();
  }

  void _syncToFirestore() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fasting')
        .doc('state')
        .set({
      'isRunning': _isRunning,
      'startMs': _startTime?.millisecondsSinceEpoch,
      'protocol': _selectedProtocol,
      'streak': _streak,
      'updatedAt': FieldValue.serverTimestamp(),
    }).catchError((_) {});
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(_startTime!);
      });
    });
  }

  void _toggleTimer() {
    if (_isRunning) {
      _ticker?.cancel();
      setState(() {
        _isRunning = false;
        _elapsed = Duration.zero;
        _startTime = null;
      });
    } else {
      setState(() {
        _isRunning = true;
        _startTime = DateTime.now();
        _elapsed = Duration.zero;
      });
      _startTicker();
      _streak++;
    }
    _saveState();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining =
        _inFastingWindow ? _fastDuration - _elapsed : Duration.zero;

    return Scaffold(
      appBar: AppBar(title: const Text('Intermittent Fasting')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Protocol selector
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: _protocols.keys.map((p) {
                return ChoiceChip(
                  label: Text(p),
                  selected: _selectedProtocol == p,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: _selectedProtocol == p
                        ? Colors.white
                        : AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: _isRunning
                      ? null
                      : (_) => setState(() => _selectedProtocol = p),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            // Circular timer
            Center(
              child: CircularPercentIndicator(
                radius: 150,
                lineWidth: 16,
                percent: _progress,
                progressColor: AppColors.primary,
                backgroundColor: AppColors.lightGreen,
                circularStrokeCap: CircularStrokeCap.round,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isRunning ? _formatDuration(_elapsed) : '00:00:00',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isRunning ? _stateLabel : 'Not started',
                      style: const TextStyle(
                          color: AppColors.hintGreen, fontSize: 13),
                    ),
                    if (_isRunning && _inFastingWindow) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${_formatDuration(remaining)} left',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Last meal time
            Row(
              children: [
                const Text('Last meal at:',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: _lastMealTime,
                    );
                    if (t != null) setState(() => _lastMealTime = t);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.lightGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _lastMealTime.format(context),
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _toggleTimer,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isRunning ? AppColors.error : AppColors.primary,
              ),
              child: Text(_isRunning ? 'Stop Fast' : 'Start Fast'),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '🔥 $_streak day streak',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
