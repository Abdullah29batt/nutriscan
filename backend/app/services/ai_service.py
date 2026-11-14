import io
import json
import logging
import re

from google import genai
from PIL import Image

from app.core.config import settings

logger = logging.getLogger(__name__)

_client = genai.Client(api_key=settings.gemini_api_key)


def _generate(contents):
    return _client.models.generate_content(model=settings.gemini_model, contents=contents)


def predict(image_bytes: bytes) -> list[dict]:
    """Use Gemini Vision to identify food in the image.

    Returns a list of up to 3 dicts, each with keys:
        label        – snake_case identifier, e.g. 'apple_pie'
        display_name – human-readable name, e.g. 'Apple Pie'
        confidence   – float in [0, 1]
    """
    try:
        img = Image.open(io.BytesIO(image_bytes)).convert("RGB")

        response = _generate([
            "Identify the food in this image. "
            "Return ONLY a JSON array with exactly 3 items in this format: "
            '[{"label": "pizza", "display_name": "Pizza", "confidence": 0.95}]. '
            "Use snake_case for label. No extra text, just the JSON array.",
            img,
        ])

        text = response.text.strip()
        match = re.search(r'\[.*?\]', text, re.DOTALL)
        if match:
            results = json.loads(match.group())
            # Normalise and cap confidence to [0, 1]
            cleaned = []
            for item in results[:3]:
                cleaned.append({
                    "label": str(item.get("label", "unknown")),
                    "display_name": str(item.get("display_name", "Unknown Food")),
                    "confidence": max(0.0, min(1.0, float(item.get("confidence", 0.0)))),
                })
            return cleaned

    except Exception as e:
        logger.error(f"Gemini predict() failed: {e}")
        raise Exception(f"Food recognition failed: {e}")

    return [{"label": "unknown", "display_name": "Unknown Food", "confidence": 0.0}]


def get_nutrition(food_label: str) -> dict:
    """Use Gemini to estimate nutrition per 100 g for the given food label.

    Returns a dict with float values for:
        calories, protein, carbs, fat, fiber
    Falls back to zeros if the call fails.
    """
    try:
        response = _generate(
            f"Give estimated nutrition facts per 100g for: {food_label}. "
            "Return ONLY a JSON object with these exact numeric keys (no units, no text): "
            '{"calories": 0, "protein": 0, "carbs": 0, "fat": 0, "fiber": 0}.'
        )

        text = response.text.strip()
        match = re.search(r'\{.*?\}', text, re.DOTALL)
        if match:
            data = json.loads(match.group())
            return {
                "calories": float(data.get("calories", 0)),
                "protein":  float(data.get("protein", 0)),
                "carbs":    float(data.get("carbs", 0)),
                "fat":      float(data.get("fat", 0)),
                "fiber":    float(data.get("fiber", 0)),
            }

    except Exception as e:
        logger.error(f"Gemini get_nutrition() failed: {e}")

    return {"calories": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0, "fiber": 0.0}
