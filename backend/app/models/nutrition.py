from pydantic import BaseModel


class NutrientInfo(BaseModel):
    food_name: str | None = None
    serving_qty: float | None = None
    serving_unit: str | None = None
    serving_weight_grams: float | None = None
    calories: float | None = None
    total_fat_g: float | None = None
    saturated_fat_g: float | None = None
    cholesterol_mg: float | None = None
    sodium_mg: float | None = None
    total_carbohydrate_g: float | None = None
    dietary_fiber_g: float | None = None
    sugars_g: float | None = None
    protein_g: float | None = None
    photo_url: str | None = None


class NutritionResponse(BaseModel):
    query: str
    foods: list[NutrientInfo]


class NutritionRequest(BaseModel):
    query: str
