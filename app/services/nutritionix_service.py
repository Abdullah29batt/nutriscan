"""
Nutrition service using Gemini AI instead of Nutritionix.
Gemini provides nutrition estimates for any food including Egyptian cuisine.
"""

from google import genai
import json
from app.core.config import settings

_client = genai.Client(api_key=settings.gemini_api_key)


async def get_nutrition_from_gemini(food_name: str, portion_grams: float = 100) -> dict:
    """
    Get nutritional information for a food item using Gemini AI.
    Returns nutrition data per specified portion size.
    """
    prompt = f"""
    Provide nutritional information for {portion_grams}g of {food_name}.

    Respond ONLY with a valid JSON object in this exact format, no other text:
    {{
        "food_name": "{food_name}",
        "portion_grams": {portion_grams},
        "calories": <number>,
        "protein_g": <number>,
        "carbohydrates_g": <number>,
        "fat_g": <number>,
        "fiber_g": <number>,
        "sugar_g": <number>,
        "sodium_mg": <number>
    }}

    Use realistic nutritional values. All numbers should be floats.
    """

    try:
        response = await _client.aio.models.generate_content(
            model="gemini-1.5-flash",
            contents=prompt,
        )
        text = response.text.strip()

        # Clean up response
        if "```json" in text:
            text = text.split("```json")[1].split("```")[0].strip()
        elif "```" in text:
            text = text.split("```")[1].split("```")[0].strip()

        nutrition_data = json.loads(text)
        return nutrition_data

    except Exception as e:
        # Return default values if Gemini fails
        return {
            "food_name": food_name,
            "portion_grams": portion_grams,
            "calories": 0,
            "protein_g": 0,
            "carbohydrates_g": 0,
            "fat_g": 0,
            "fiber_g": 0,
            "sugar_g": 0,
            "sodium_mg": 0,
            "error": str(e)
        }


async def get_nutrition(food_name: str, portion_grams: float = 100) -> dict:
    """Main function to get nutrition data."""
    return await get_nutrition_from_gemini(food_name, portion_grams)