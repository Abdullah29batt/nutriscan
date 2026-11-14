import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

class HealthInfoScreen extends StatefulWidget {
  const HealthInfoScreen({super.key});

  @override
  State<HealthInfoScreen> createState() => _HealthInfoScreenState();
}

class _HealthInfoScreenState extends State<HealthInfoScreen> {
  static const _allergyOptions = [
    'Nuts', 'Shellfish', 'Dairy', 'Gluten', 'Eggs',
    'Soy', 'Fish', 'Sesame',
  ];
  static const _dietOptions = [
    'Vegetarian', 'Vegan', 'Keto', 'Paleo', 'Low-Carb',
    'Mediterranean', 'Halal', 'Kosher', 'Gluten-Free', 'Dairy-Free',
  ];
  static const _conditionOptions = [
    'Diabetes', 'Hypertension', 'High Cholesterol', 'Heart Disease',
    'GERD / Acid Reflux', 'Celiac Disease', 'IBS', 'Thyroid Disorder',
  ];

  Set<String> _allergies = {};
  Set<String> _dietRestrictions = {};
  Set<String> _conditions = {};
  final _notesController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Load local first (fast, offline-safe)
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _allergies = (prefs.getStringList('health_allergies') ?? []).toSet();
        _dietRestrictions = (prefs.getStringList('health_diet') ?? []).toSet();
        _conditions = (prefs.getStringList('health_conditions') ?? []).toSet();
        _notesController.text = prefs.getString('health_notes') ?? '';
        _loading = false;
      });
    }
    // Refresh from Firestore in background
    _refreshFromFirestore(prefs);
  }

  Future<void> _refreshFromFirestore(SharedPreferences prefs) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('profile')
          .doc('health_info')
          .get();
      if (!doc.exists || !mounted) return;
      final data = doc.data()!;
      final allergies =
          List<String>.from(data['allergies'] as List? ?? []);
      final diet =
          List<String>.from(data['dietRestrictions'] as List? ?? []);
      final conditions =
          List<String>.from(data['conditions'] as List? ?? []);
      final notes = data['notes'] as String? ?? '';
      // Persist to local so next launch is fast
      await prefs.setStringList('health_allergies', allergies);
      await prefs.setStringList('health_diet', diet);
      await prefs.setStringList('health_conditions', conditions);
      await prefs.setString('health_notes', notes);
      if (mounted) {
        setState(() {
          _allergies = allergies.toSet();
          _dietRestrictions = diet.toSet();
          _conditions = conditions.toSet();
          _notesController.text = notes;
        });
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // Write local immediately
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('health_allergies', _allergies.toList());
    await prefs.setStringList('health_diet', _dietRestrictions.toList());
    await prefs.setStringList('health_conditions', _conditions.toList());
    await prefs.setString('health_notes', _notesController.text.trim());
    // Background Firestore sync (don't await)
    _syncToFirestore();
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Health information saved!')),
      );
      Navigator.pop(context);
    }
  }

  void _syncToFirestore() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc('health_info')
        .set({
      'allergies': _allergies.toList(),
      'dietRestrictions': _dietRestrictions.toList(),
      'conditions': _conditions.toList(),
      'notes': _notesController.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Health Information')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
                icon: Icons.warning_amber_outlined, label: 'Allergies'),
            const SizedBox(height: 8),
            _ChipSelector(
              options: _allergyOptions,
              selected: _allergies,
              onToggle: (v) => setState(() => _allergies.contains(v)
                  ? _allergies.remove(v)
                  : _allergies.add(v)),
            ),
            const SizedBox(height: 20),
            _SectionHeader(
                icon: Icons.restaurant_menu_outlined,
                label: 'Dietary Restrictions'),
            const SizedBox(height: 8),
            _ChipSelector(
              options: _dietOptions,
              selected: _dietRestrictions,
              onToggle: (v) => setState(() => _dietRestrictions.contains(v)
                  ? _dietRestrictions.remove(v)
                  : _dietRestrictions.add(v)),
            ),
            const SizedBox(height: 20),
            _SectionHeader(
                icon: Icons.local_hospital_outlined,
                label: 'Medical Conditions'),
            const SizedBox(height: 8),
            _ChipSelector(
              options: _conditionOptions,
              selected: _conditions,
              onToggle: (v) => setState(() => _conditions.contains(v)
                  ? _conditions.remove(v)
                  : _conditions.add(v)),
            ),
            const SizedBox(height: 20),
            _SectionHeader(
                icon: Icons.note_alt_outlined,
                label: 'Notes & Medications'),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 4,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText:
                    'Medications, additional notes, or special requirements...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Text('Save Health Information'),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.hintGreen,
          ),
        ),
      ],
    );
  }
}

class _ChipSelector extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final void Function(String) onToggle;
  const _ChipSelector({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: options.map((opt) {
        final isSelected = selected.contains(opt);
        return FilterChip(
          label: Text(opt),
          selected: isSelected,
          selectedColor: AppColors.primary,
          checkmarkColor: Colors.white,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppColors.primary,
            fontWeight:
                isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
          backgroundColor: AppColors.lightGreen,
          side: BorderSide.none,
          onSelected: (_) => onToggle(opt),
        );
      }).toList(),
    );
  }
}
