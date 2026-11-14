import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/meal_provider.dart';
import '../theme/app_theme.dart';
import 'results_screen.dart';

class CameraScreen extends StatefulWidget {
  final String? mealType;
  const CameraScreen({super.key, this.mealType});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (file != null) {
      setState(() => _selectedImage = File(file.path));
    }
  }

  Future<void> _analyze() async {
    if (_selectedImage == null) return;

    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    final mealProvider = context.read<MealProvider>();
    final success = await mealProvider.analyzeFood(_selectedImage!, user.uid);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultsScreen(mealType: widget.mealType),
        ),
      );
    } else if (mealProvider.noFoodDetected) {
      _showNoFoodDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mealProvider.error ?? 'Analysis failed'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showNoFoodDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.no_food_outlined,
                  size: 38, color: AppColors.error),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Food Detected',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'We couldn\'t identify any food in this photo.\nPlease take a clear, well-lit photo of a food item and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.hintGreen),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      setState(() => _selectedImage = null);
                    },
                    child: const Text('Clear Photo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _pickImage(ImageSource.camera);
                    },
                    child: const Text('Try Again'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOffline = context.watch<ConnectivityProvider>().isOffline;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Upload Image',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Premium offline banner (Feature 3)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, anim) => SizeTransition(
                  sizeFactor: anim,
                  axisAlignment: -1,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: isOffline
                    ? const _PremiumOfflineBanner(key: ValueKey('banner'))
                    : const SizedBox.shrink(key: ValueKey('empty')),
              ),
              GestureDetector(
                onTap: () => _pickImage(ImageSource.gallery),
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.hintGreen,
                      width: 2,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
                    color: AppColors.cardGreen,
                  ),
                  child: _selectedImage == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_upload_outlined,
                                size: 60, color: Colors.amber),
                            const SizedBox(height: 8),
                            Text(
                              'Tap to pick from Gallery',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'supported: JPG, PNG',
                              style: TextStyle(
                                  color: AppColors.hintGreen, fontSize: 12),
                            ),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(
                            _selectedImage!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Consumer<MealProvider>(
                builder: (_, provider, __) {
                  return Visibility(
                    visible: _selectedImage != null,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: LinearProgressIndicator(
                      value: provider.isAnalyzing ? null : 1.0,
                      backgroundColor: AppColors.lightGreen,
                      color: AppColors.primary,
                    ),
                  );
                },
              ),
              if (_selectedImage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.cardGreen,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          _selectedImage!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedImage!.path.split('/').last,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.primary, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.error),
                        onPressed: () =>
                            setState(() => _selectedImage = null),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: () => _pickImage(ImageSource.camera),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt,
                        color: Colors.white, size: 36),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Take a photo',
                  style: TextStyle(
                      color: AppColors.hintGreen, fontSize: 12),
                ),
              ),
              if (_selectedImage != null) ...[
                const SizedBox(height: 16),
                Consumer<MealProvider>(
                  builder: (_, provider, __) => ElevatedButton(
                    onPressed: provider.isAnalyzing ? null : _analyze,
                    child: provider.isAnalyzing
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              ),
                              SizedBox(width: 10),
                              Text('Analyzing...'),
                            ],
                          )
                        : const Text('Analyze Food'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Feature 3: premium offline banner ────────────────────────────────────────

class _PremiumOfflineBanner extends StatefulWidget {
  const _PremiumOfflineBanner({super.key});

  @override
  State<_PremiumOfflineBanner> createState() => _PremiumOfflineBannerState();
}

class _PremiumOfflineBannerState extends State<_PremiumOfflineBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E3B), Color(0xFF2E7D52)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E3B).withAlpha(80),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'NutriScan Edge AI Active',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Offline mode — your streak is safe!',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Opacity(
              opacity: _pulse.value,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF69F0AE),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
