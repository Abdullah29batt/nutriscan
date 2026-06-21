from pydantic import BaseModel


class SaveMealRequest(BaseModel):
    food_label: str
    display_name: str
    calories: float
    protein_g: float
    total_carbohydrate_g: float
    total_fat_g: float
    dietary_fiber_g: float | None = None
    sugars_g: float | None = None
    sodium_mg: float | None = None
    portion_grams: float = 100.0
    image_url: str | None = None
    notes: str | None = None


class MealEntry(BaseModel):
    id: str
    food_label: str
    display_name: str
    calories: float
    protein_g: float
    total_carbohydrate_g: float
    total_fat_g: float
    dietary_fiber_g: float | None = None
    sugars_g: float | None = None
    sodium_mg: float | None = None
    portion_grams: float
    image_url: str | None = None
    notes: str | None = None
    logged_at: str
