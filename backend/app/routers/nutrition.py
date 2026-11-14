from fastapi import APIRouter, Depends, HTTPException, status
from app.core.security import get_current_user
from app.models.nutrition import NutritionRequest, NutritionResponse, NutrientInfo
from app.services import gemini_nutrition_service

router = APIRouter(prefix="/nutrition", tags=["nutrition"])


@router.post(
    "/lookup",
    response_model=NutritionResponse,
    summary="Get nutrition facts for a food query",
)
async def lookup_nutrition(
    body: NutritionRequest,
    _user: dict = Depends(get_current_user),
) -> NutritionResponse:
    """
    Fetches nutrition facts from Gemini AI for the given food query.
    Requires a valid Firebase ID token in the Authorization header.
    """
    raw = await gemini_nutrition_service.get_nutrition(body.query)

    if "error" in raw:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=raw.get("error"),
        )

    food_item = NutrientInfo(
        food_name=raw.get("food_name", body.query),
        calories=raw.get("calories", 0),
        protein_g=raw.get("protein_g", 0),
        total_carbohydrate_g=raw.get("carbohydrates_g", 0),
        total_fat_g=raw.get("fat_g", 0),
        dietary_fiber_g=raw.get("fiber_g", 0),
        sugars_g=raw.get("sugar_g", 0),
        sodium_mg=raw.get("sodium_mg", 0),
    )

    return NutritionResponse(query=body.query, foods=[food_item])


@router.post(
    "/recognize-and-lookup",
    response_model=NutritionResponse,
    summary="Get nutrition facts for a recognised food label",
)
async def recognize_and_lookup(
    body: NutritionRequest,
    _user: dict = Depends(get_current_user),
) -> NutritionResponse:
    """
    Accepts the top food label from /food/recognize
    and immediately fetches its nutrition data from Gemini AI.
    """
    return await lookup_nutrition(body, _user)