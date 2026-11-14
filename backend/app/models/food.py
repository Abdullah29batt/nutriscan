from pydantic import BaseModel, Field


class FoodPrediction(BaseModel):
    label: str = Field(description="Snake-case class label, e.g. 'apple_pie'")
    display_name: str = Field(description="Human-readable label, e.g. 'Apple Pie'")
    confidence: float = Field(ge=0.0, le=1.0, description="Model confidence score")


class NutritionData(BaseModel):
    calories: float = 0.0
    protein: float = 0.0
    carbs: float = 0.0
    fat: float = 0.0
    fiber: float = 0.0


class RecognitionResponse(BaseModel):
    predictions: list[FoodPrediction]
    top_label: str = Field(description="Label of the highest-confidence prediction")
    top_display_name: str
    nutrition: NutritionData | None = None
