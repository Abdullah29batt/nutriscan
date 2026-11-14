# NutriScan — Model Training

Both models were trained in Kaggle notebooks (GPU, TensorFlow 2.19).

## Notebooks

| Notebook | Model | Output |
|---|---|---|
| [`01_food_classifier_efficientnetv2m.ipynb`](notebooks/01_food_classifier_efficientnetv2m.ipynb) | EfficientNetV2M image classifier, 108 classes | `food_model.tflite` (55.5 MB, in GitHub Releases) |
| [`02_nutrition_regressor.ipynb`](notebooks/02_nutrition_regressor.ipynb) | TF-IDF (char 2–4-grams, 3,000 features) → Dense 512-256-128-64-5 | `nutrition_model.tflite` (6.5 MB), `vectorizer.json`, `scaler.json` |

## 1 · Food classifier

**Data:** 85,310 images in 108 classes, split 80/20 with seed 42 into 68,248 train and 17,062 validation images.

| Source (Kaggle) | Images | Notes |
|---|---|---|
| Food-101 (`kmader/food41`) | 80,000 | 80 of 101 classes kept |
| Arabic Food 101 (`araraltawil/arabic-food-101`) | 3,333 | 17 new classes, others merged |
| Egyptian food (`abdullahmohammed29/egyptian-food`) | 504 | bamya, fattah, molokhia (+ merged koshari, kunafa) |
| Fruit 101 (`araraltawil/fruit-101-dataset`) | 1,473 | 8 fruit classes |

**Training:** EfficientNetV2M (ImageNet weights, 224×224 input, 55.2 M params) with a Dense 1024-512-256 head. Augmentation: random crop, flip, brightness, contrast, saturation and hue, plus MixUp. AdamW with cosine decay and warm-up, label smoothing, mixed precision.

1. Head only, backbone frozen (15 epochs, LR 1e-3)
2. Top 200 backbone layers unfrozen (25 epochs, LR 3e-5)
3. Full fine-tune (15 epochs, LR 5e-6)

**Result:** 81.41 % top-1 / 94.14 % top-5 on validation. The training log saved in the notebook stops during Phase 2 at 81.14 % / 94.06 %.

## 2 · Nutrition regressor

**Data:** USDA FoodData Central Foundation Foods, the Global Food & Nutrition Database 2026, and 134 hand-curated foods (all 108 classes, including Egyptian/Arabic dishes). Targets are calories, protein, carbs, fat and fiber per 100 g.

| Report | Train / val | Mean R² | MAE | Calories MAPE |
|---|---|---|---|---|
| [`nutrition_eval_v1_initial.json`](results/nutrition_eval_v1_initial.json) | 24,018 / 4,239 | 0.620 | 20.74 | 46.5 % |
| [`nutrition_eval_v2_final.json`](results/nutrition_eval_v2_final.json) | 39,720 / 7,010 | **0.808** | **13.37** | **30.8 %** |

The final run filtered USDA compound foods (e.g. "banana bread") and repeated each custom food ×10.

> **Note:** the notebook in this folder is the **initial** run, and its outputs match `v1`. The notebook for the final run is not included, so the `v2` numbers come from its saved report.
> MAPE for protein, carbs and fiber in the JSON reports is very large because many true values are near zero. Use MAE/R² for those nutrients.

## Large files (not in git)

| File | Where |
|---|---|
| `food_model.tflite` (55.5 MB) | GitHub Releases |
| Training datasets | the Kaggle datasets linked above |
