import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/habit_model.dart';
import '../theme/app_theme.dart';

class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key});

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  List<HabitModel> _habits = [];

  static const _prefsKey = 'habits_list';

  @override
  void initState() {
    super.initState();
    _loadHabits();
  }

  Future<void> _loadHabits() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        setState(() {
          _habits = list
              .map((e) =>
                  HabitModel.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        });
        return;
      } catch (_) {}
    }
    // Default sample habits
    setState(() {
      _habits = [
        HabitModel(
            id: const Uuid().v4(),
            name: 'Drink Water',
            emoji: '💧',
            time: '9:00 AM'),
        HabitModel(
            id: const Uuid().v4(),
            name: 'Read',
            emoji: '📖',
            time: '12:00 PM'),
        HabitModel(
            id: const Uuid().v4(),
            name: 'Go for a Walk',
            emoji: '🚶',
            time: '6:00 PM'),
        HabitModel(
            id: const Uuid().v4(),
            name: 'Drink Water',
            emoji: '💧',
            time: '8:00 PM'),
      ];
    });
    _saveHabits();
  }

  Future<void> _saveHabits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_habits.map((h) => h.toJson()).toList()));
  }

  void _toggleHabit(int index, bool value) {
    setState(() => _habits[index].isEnabled = value);
    _saveHabits();
  }

  void _deleteHabit(int index) {
    setState(() => _habits.removeAt(index));
    _saveHabits();
  }

  Future<void> _showAddSheet() async {
    TimeOfDay selectedTime = TimeOfDay.now();
    final emojiController = TextEditingController();
    final nameController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setS) {
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'New Habit',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: selectedTime,
                    );
                    if (t != null) setS(() => selectedTime = t);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.cardGreen,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.hintGreen),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time,
                            color: AppColors.primary),
                        const SizedBox(width: 12),
                        Text(
                          selectedTime.format(ctx),
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emojiController,
                  decoration: const InputDecoration(hintText: 'Emoji'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration:
                      const InputDecoration(hintText: 'Habit name'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    final habit = HabitModel(
                      id: const Uuid().v4(),
                      name: name,
                      emoji: emojiController.text.trim().isEmpty
                          ? '✅'
                          : emojiController.text.trim(),
                      time: selectedTime.format(ctx),
                    );
                    setState(() => _habits.add(habit));
                    _saveHabits();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Habits')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Text(
              'Add Your Habits',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _habits.isEmpty
                ? Center(
                    child: Text(
                      'No habits yet. Tap + to add one.',
                      style: TextStyle(color: AppColors.hintGreen),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: _habits.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final h = _habits[i];
                      return Dismissible(
                        key: Key(h.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => _deleteHabit(i),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete_outline,
                              color: Colors.white),
                        ),
                        child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.lightGreen,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Text(h.time,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                    fontSize: 13)),
                            const SizedBox(width: 8),
                            Text(h.emoji,
                                style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(h.name,
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: AppColors.hintGreen, size: 20),
                              onPressed: () {},
                            ),
                            Switch(
                              value: h.isEnabled,
                              onChanged: (v) => _toggleHabit(i, v),
                            ),
                          ],
                        ),
                      ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
