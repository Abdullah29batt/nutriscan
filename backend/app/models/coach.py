from pydantic import BaseModel, Field


class HealthTipsRequest(BaseModel):
    meals: list[str] = Field(default_factory=list, max_length=50)


class HealthTipsResponse(BaseModel):
    tips: list[str]


class MealFeedbackRequest(BaseModel):
    food_name: str = Field(min_length=1, max_length=200)
    calories: float = Field(ge=0)
    protein: float = Field(ge=0)
    carbs: float = Field(ge=0)
    fat: float = Field(ge=0)
    calorie_goal: float = Field(gt=0)
    today_calories: float = Field(ge=0)
    allergies: list[str] = Field(default_factory=list)
    diet_restrictions: list[str] = Field(default_factory=list)
    health_goal: str = "Maintain weight"


class MealFeedbackResponse(BaseModel):
    feedback: str
