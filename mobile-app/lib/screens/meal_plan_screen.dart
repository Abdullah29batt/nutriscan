import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../theme/app_theme.dart';

class MealPlanScreen extends StatefulWidget {
  const MealPlanScreen({super.key});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  static const _slots = ['Breakfast', 'Lunch', 'Dinner'];

  // SharedPreferences keys for saved times
  static const _keyBreakfast = 'meal_plan_breakfast_time';
  static const _keyLunch     = 'meal_plan_lunch_time';
  static const _keyDinner    = 'meal_plan_dinner_time';

  final _db            = FirebaseFirestore.instance;
  final _notifications = FlutterLocalNotificationsPlugin();
  final _controllers   = List.generate(3, (_) => TextEditingController());

  bool _loading = true;
  bool _saving  = false;

  // Preferred meal times (persisted in SharedPreferences)
  late TimeOfDay _breakfastTime;
  late TimeOfDay _lunchTime;
  late TimeOfDay _dinnerTime;

  // Today / Tomorrow toggle (0 = Today, 1 = Tomorrow)
  int _dayIndex = 0;

  // Meal completion checkboxes
  final List<bool> _checked = [false, false, false];

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Set defaults before async load so late fields are never uninitialized.
    _breakfastTime = const TimeOfDay(hour: 8,  minute: 0);
    _lunchTime     = const TimeOfDay(hour: 13, minute: 0);
    _dinnerTime    = const TimeOfDay(hour: 19, minute: 0);
    _loadAll();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    await Future.wait([_loadTimes(), _loadPlan()]);
  }

  Future<void> _loadTimes() async {
    final prefs = await SharedPreferences.getInstance();

    TimeOfDay parseTime(String key, TimeOfDay fallback) {
      final stored = prefs.getString(key);
      if (stored == null) return fallback;
      final parts = stored.split(':');
      if (parts.length != 2) return fallback;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return fallback;
      return TimeOfDay(hour: h, minute: m);
    }

    if (mounted) {
      setState(() {
        _breakfastTime = parseTime(_keyBreakfast, const TimeOfDay(hour: 8,  minute: 0));
        _lunchTime     = parseTime(_keyLunch,     const TimeOfDay(hour: 13, minute: 0));
        _dinnerTime    = parseTime(_keyDinner,    const TimeOfDay(hour: 19, minute: 0));
      });
    }
  }

  Future<void> _saveTimes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBreakfast, '${_breakfastTime.hour}:${_breakfastTime.minute}');
    await prefs.setString(_keyLunch,     '${_lunchTime.hour}:${_lunchTime.minute}');
    await prefs.setString(_keyDinner,    '${_dinnerTime.hour}:${_dinnerTime.minute}');
  }

  Future<void> _loadPlan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final doc = await _db
          .collection('users')
          .doc(uid)
          .collection('meal_plans')
          .doc(_dateKey())
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        for (int i = 0; i < _slots.length; i++) {
          _controllers[i].text = data[_slotKey(i)] as String? ?? '';
        }
        if (mounted) {
          setState(() {
            _checked[0] = data['breakfast_taken'] as bool? ?? false;
            _checked[1] = data['lunch_taken']     as bool? ?? false;
            _checked[2] = data['dinner_taken']    as bool? ?? false;
          });
        }
      }
    } catch (e) {
      debugPrint('Load meal plan failed: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Save to Firestore ────────────────────────────────────────────────────────

  Future<void> _savePlan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('meal_plans')
          .doc(_dateKey())
          .set({
        'breakfast': _controllers[0].text.trim(),
        'lunch':     _controllers[1].text.trim(),
        'dinner':    _controllers[2].text.trim(),
        'breakfast_time': _fmtHHmm(_breakfastTime),
        'lunch_time':     _fmtHHmm(_lunchTime),
        'dinner_time':    _fmtHHmm(_dinnerTime),
        'breakfast_taken': _checked[0],
        'lunch_taken':     _checked[1],
        'dinner_taken':    _checked[2],
        'created_at': FieldValue.serverTimestamp(),
        'for_date':   _dayIndex == 0 ? 'today' : 'tomorrow',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meal plan saved!')),
        );
        await _scheduleMealPlanNotifications();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  /// Toggles one meal's taken state and immediately patches Firestore.
  /// Uses merge-set so it works even before the plan is fully saved.
  Future<void> _updateTaken(int i, bool value) async {
    setState(() => _checked[i] = value);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('meal_plans')
          .doc(_dateKey())
          .set({'${_slotKey(i)}_taken': value}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Update taken failed: $e');
    }
  }

  // ── Meal plan notifications ──────────────────────────────────────────────────

  Future<void> _scheduleMealPlanNotifications() async {
    // Request permission — no-op if already granted (Android 13+).
    final android = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    // Cancel previous meal-plan notifications to avoid duplicates.
    await _notifications.cancel(100);
    await _notifications.cancel(101);
    await _notifications.cancel(102);

    // Warn if any selected time has already passed when planning for Today.
    if (_dayIndex == 0 && mounted) {
      final now = TimeOfDay.now();
      final anyPassed = [_breakfastTime, _lunchTime, _dinnerTime].any((t) =>
          t.hour < now.hour ||
          (t.hour == now.hour && t.minute <= now.minute));
      if (anyPassed) {
        await _showPassedTimeWarning();
        // _dayIndex may now be 1 if the user tapped "Switch to Tomorrow".
      }
    }

    // Read meal names after the dialog (they may have been cleared if the
    // user switched to Tomorrow).
    final names = [
      _controllers[0].text.trim().isEmpty ? 'Breakfast' : _controllers[0].text.trim(),
      _controllers[1].text.trim().isEmpty ? 'Lunch'     : _controllers[1].text.trim(),
      _controllers[2].text.trim().isEmpty ? 'Dinner'    : _controllers[2].text.trim(),
    ];

    await _scheduleSingleMealNotification(
      id: 100, title: '🍳 Breakfast Time!',
      body: 'Time for your breakfast: ${names[0]}', time: _breakfastTime,
    );
    await _scheduleSingleMealNotification(
      id: 101, title: '🥗 Lunch Time!',
      body: 'Time for your lunch: ${names[1]}',     time: _lunchTime,
    );
    await _scheduleSingleMealNotification(
      id: 102, title: '🍽️ Dinner Time!',
      body: 'Time for your dinner: ${names[2]}',    time: _dinnerTime,
    );
  }

  Future<void> _showPassedTimeWarning() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Time Has Passed'),
        content: const Text(
          'This time has already passed today. Switch to Tomorrow?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _dayIndex = 1;
                for (final c in _controllers) {
                  c.clear();
                }
                for (int i = 0; i < _checked.length; i++) {
                  _checked[i] = false;
                }
                _loading = true;
              });
              _loadPlan();
            },
            child: const Text('Switch to Tomorrow'),
          ),
        ],
      ),
    );
  }

  Future<void> _scheduleSingleMealNotification({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
  }) async {
    try {
      final now         = DateTime.now();
      final base        = now.add(Duration(days: _dayIndex));
      final targetLocal = DateTime(base.year, base.month, base.day, time.hour, time.minute);
      if (targetLocal.isBefore(now)) return; // already passed — skip silently
      final target = tz.TZDateTime.from(targetLocal.toUtc(), tz.UTC);
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        target,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'nutriscan_reminders',
            'Meal Reminders',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'meal_plan',
      );
    } catch (e) {
      debugPrint('Meal plan notification $id failed: $e');
    }
  }

  // ── Time picker ──────────────────────────────────────────────────────────────

  Future<void> _pickTime(int slotIndex) async {
    final initial = _slotTime(slotIndex);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Set ${_slots[slotIndex]} time',
    );
    if (picked == null) return;
    setState(() {
      if (slotIndex == 0) _breakfastTime = picked;
      if (slotIndex == 1) _lunchTime     = picked;
      if (slotIndex == 2) _dinnerTime    = picked;
    });
    await _saveTimes();
  }

  TimeOfDay _slotTime(int i) {
    if (i == 0) return _breakfastTime;
    if (i == 1) return _lunchTime;
    return _dinnerTime;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  /// Returns the Firestore field prefix for slot [i]: breakfast / lunch / dinner.
  String _slotKey(int i) => _slots[i].toLowerCase();

  /// Formats a [TimeOfDay] as zero-padded "HH:mm" for Firestore storage.
  String _fmtHHmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _dateKey() {
    final date = DateTime.now().add(Duration(days: _dayIndex));
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formattedDate() {
    final date = DateTime.now().add(Duration(days: _dayIndex));
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const days   = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  String _formatTime(TimeOfDay t) => t.format(context);

  bool get _allChecked => _checked.every((c) => c);

  IconData _slotIcon(int i) {
    const icons = [
      Icons.wb_sunny_outlined,
      Icons.wb_cloudy_outlined,
      Icons.nights_stay_outlined,
    ];
    return icons[i];
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Meal Plan")),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Time pickers ──────────────────────────────────────────
                  _SectionLabel(label: 'Meal Times'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (int i = 0; i < 3; i++) ...[
                        Expanded(child: _TimePickerTile(
                          icon:    _slotIcon(i),
                          label:   _slots[i],
                          time:    _formatTime(_slotTime(i)),
                          onTap:   () => _pickTime(i),
                        )),
                        if (i < 2) const SizedBox(width: 8),
                      ],
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Today / Tomorrow toggle ───────────────────────────────
                  _SectionLabel(label: 'Plan for'),
                  const SizedBox(height: 10),
                  _DayToggle(
                    selected: _dayIndex,
                    onChanged: (idx) {
                      setState(() {
                        _dayIndex = idx;
                        for (final c in _controllers) {
                          c.clear();
                        }
                        for (int i = 0; i < _checked.length; i++) {
                          _checked[i] = false;
                        }
                        _loading = true;
                      });
                      _loadPlan();
                    },
                  ),

                  const SizedBox(height: 8),

                  // Date label
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.lightGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          _formattedDate(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Completion banner ─────────────────────────────────────
                  if (_allChecked) ...[
                    _CompletionBanner(),
                    const SizedBox(height: 16),
                  ],

                  // ── Meal slots ────────────────────────────────────────────
                  _SectionLabel(label: 'Meals'),
                  const SizedBox(height: 10),
                  if (_loading)
                    const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  else
                    for (int i = 0; i < _slots.length; i++) ...[
                      _MealSlot(
                        label:      _slots[i],
                        icon:       _slotIcon(i),
                        time:       _formatTime(_slotTime(i)),
                        controller: _controllers[i],
                        checked:    _checked[i],
                        onChecked:  (val) => _updateTaken(i, val ?? false),
                      ),
                      if (i < _slots.length - 1) const SizedBox(height: 12),
                    ],

                  const SizedBox(height: 28),

                  ElevatedButton.icon(
                    onPressed: _saving ? null : _savePlan,
                    icon: _saving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save Plan'),
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'Tip: Write what you plan to eat for each meal. '
                    'Check a meal off when you\'ve eaten it. '
                    'Your plan is saved per-day.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.hintGreen),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.hintGreen,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Tappable tile showing a meal's time; opens a time picker on tap.
class _TimePickerTile extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   time;
  final VoidCallback onTap;

  const _TimePickerTile({
    required this.icon,
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.cardGreen,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.lightGreen),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.hintGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 2),
            const Icon(Icons.edit_outlined, size: 12, color: AppColors.hintGreen),
          ],
        ),
      ),
    );
  }
}

/// Two-button toggle: Today | Tomorrow.
class _DayToggle extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _DayToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < 2; i++) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected == i ? AppColors.primary : AppColors.cardGreen,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected == i ? AppColors.primary : AppColors.lightGreen,
                  ),
                ),
                child: Text(
                  i == 0 ? 'Today' : 'Tomorrow',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected == i ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
          if (i == 0) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// Meal text field with a checkbox on the left and the scheduled time on the right.
class _MealSlot extends StatelessWidget {
  final String label;
  final IconData icon;
  final String time;
  final TextEditingController controller;
  final bool checked;
  final ValueChanged<bool?> onChecked;

  const _MealSlot({
    required this.label,
    required this.icon,
    required this.time,
    required this.controller,
    required this.checked,
    required this.onChecked,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
      decoration: BoxDecoration(
        color: checked ? AppColors.lightGreen : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: checked ? AppColors.primary.withAlpha(60) : AppColors.lightGreen,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox
          Checkbox(
            value: checked,
            onChanged: onChecked,
            activeColor: AppColors.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          // Text field + header
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.primary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.hintGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'What are you planning for $label?',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Green success banner shown when all 3 meals are checked.
class _CompletionBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withAlpha(80)),
      ),
      child: const Row(
        children: [
          Text('🎉', style: TextStyle(fontSize: 24)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Great job! You completed your meal plan today!',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
