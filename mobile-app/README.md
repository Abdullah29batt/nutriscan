# NutriScan — Mobile App (Flutter)

Flutter app for scanning meals, tracking calories and macros, and managing diet goals.

- **Recognition:** online via the backend (`/food/recognize`, Gemini Vision). Offline fallback via the on-device **EfficientNetV2M** TFLite model (108 classes).
- **Nutrition:** an on-device TF-IDF → MLP regressor (`nutrition_model.tflite` with `vectorizer.json` and `scaler.json`).
- **Features:** history, favourites, water/weight/streak tracking, fasting timer, meal planning, BMI/BMR/TDEE calculator, AI meal feedback and health tips (via the backend), dark mode.

## Setup

1. **Firebase:** these files are not committed. Generate them for your own Firebase project:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure      # creates lib/firebase_options.dart and android/app/google-services.json
   ```
2. **Classifier model:** download `food_model.tflite` (55.5 MB) from the repo's GitHub Releases into `assets/`.
3. **Run:**
   ```bash
   flutter pub get
   flutter run --dart-define=API_BASE_URL=http://<your-ip>:8000
   ```
   Without `API_BASE_URL`, the app uses the deployed backend URL set in `lib/services/api_service.dart`.

## Structure

```
lib/
├── models/      meal, user profile, habit
├── providers/   auth, meals (online→offline recognition), nutrition goals, theme, connectivity
├── screens/     21 screens (camera, results, history, profile, …)
├── services/    api_service (backend), gemini_service (AI coach via backend),
│                tflite_service, nutrition_tflite_service, meal_service, notifications
├── theme/
└── widgets/
```

No API keys are stored in the app. All Gemini calls go through the authenticated backend.
