from pydantic import BaseModel


class DailyStats(BaseModel):
    date: str              # YYYY-MM-DD
    meal_count: int
    total_calories: float
    total_protein_g: float
    total_carbohydrate_g: float
    total_fat_g: float
    total_fiber_g: float
    total_sugar_g: float
