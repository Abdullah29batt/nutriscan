"""
Text-only Gemini helpers for the "nutrition coach" features of the app:
daily health tips and personalised meal feedback.

These used to run inside the Flutter app with an embedded API key; they now
run on the server so the key never ships inside the APK.
"""

import json
import logging
import re

from google import genai

from app.core.config import settings

logger = logging.getLogger(__name__)

_client = genai.Client(api_key=settings.gemini_api_key)


async def _generate(prompt: str) -> str:
    response = await _client.aio.models.generate_content(
        model=settings.gemini_model,
        contents=prompt,
    )
    return (response.text or "").strip()


async def health_tips(meals: list[str], count: int = 3) -> list[str]:
    """Return `count` short health tips based on the meals eaten today."""
    meals_text = ", ".join(meals) if meals else "nothing logged yet"
    prompt = (
        f"Today the user ate: {meals_text}. "
        f"Give exactly {count} short, practical, encouraging health tips (1-2 sentences each) "
        "based on these meals. Return ONLY a JSON array of strings, no extra text."
    )
    text = await _generate(prompt)

    match = re.search(r"\[.*\]", text, re.DOTALL)
    if match:
        try:
            tips = json.loads(match.group())
            cleaned = [str(t).strip() for t in tips if str(t).strip()]
            if cleaned:
                return cleaned[:count]
        except json.JSONDecodeError:
            logger.warning("Gemini returned malformed tips JSON: %s", text[:200])

    # Fallback: treat each non-empty line as a tip.
    lines = [l.strip(" -*•\t") for l in text.splitlines() if l.strip(" -*•\t")]
    if not lines:
        raise ValueError("Gemini returned no tips")
    return lines[:count]


async def meal_feedback(
    *,
    food_name: str,
    calories: float,
    protein: float,
    carbs: float,
    fat: float,
    calorie_goal: float,
    today_calories: float,
    allergies: list[str],
    diet_restrictions: list[str],
    health_goal: str,
) -> str:
    """Return 2-3 sentences of personalised feedback about a meal."""
    remaining = calorie_goal - today_calories
    allergy_text = ", ".join(a for a in allergies if a != "None") or "None"
    restriction_text = ", ".join(r for r in diet_restrictions if r != "None") or "None"

    prompt = (
        f"User goal: {health_goal}. Daily calorie target: {calorie_goal:.0f} kcal. "
        f"Consumed today: {today_calories:.0f} kcal ({remaining:.0f} remaining). "
        f"Allergies: {allergy_text}. Dietary restrictions: {restriction_text}. "
        f"They just ate: {food_name} ({calories:.0f} kcal, {protein:.1f}g protein, "
        f"{carbs:.1f}g carbs, {fat:.1f}g fat). "
        "Give a SHORT 2-3 sentence personalised feedback about this meal in relation to their goal. "
        "Be encouraging but honest. If the meal conflicts with their allergies or restrictions, "
        "warn them. No bullet points, no intro text."
    )
    text = await _generate(prompt)
    if not text:
        raise ValueError("Gemini returned empty feedback")
    return text
