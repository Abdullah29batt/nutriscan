from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status

from app.core.security import get_current_user
from app.models.food import RecognitionResponse
from app.models.meal import MealEntry, SaveMealRequest
from app.services import ai_service, firestore_service

router = APIRouter(prefix="/food", tags=["food"])

_ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}
_MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MB


@router.post(
    "/recognize",
    response_model=RecognitionResponse,
    summary="Upload a food image and get AI predictions",
)
async def recognize_food(
    file: UploadFile = File(..., description="Food image (JPEG / PNG / WebP, max 10 MB)"),
    _user: dict = Depends(get_current_user),
) -> RecognitionResponse:
    if file.content_type not in _ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported file type '{file.content_type}'. Use JPEG, PNG, or WebP.",
        )

    image_bytes = await file.read()

    if len(image_bytes) > _MAX_FILE_SIZE:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File exceeds 10 MB limit.",
        )

    try:
        predictions = ai_service.predict(image_bytes)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Inference failed: {exc}",
        )

    top = predictions[0]
    nutrition_dict = ai_service.get_nutrition(top["label"])
    return RecognitionResponse(
        predictions=predictions,
        top_label=top["label"],
        top_display_name=top["display_name"],
        nutrition=nutrition_dict,
    )


# ── Meal history ───────────────────────────────────────────────────────────────

@router.post(
    "/history",
    response_model=MealEntry,
    status_code=status.HTTP_201_CREATED,
    summary="Save a meal to history",
)
async def save_meal(
    body: SaveMealRequest,
    user: dict = Depends(get_current_user),
) -> MealEntry:
    """Saves a recognised meal and its nutrition data to the user's Firestore history."""
    uid = user["uid"]
    meal_doc = {
        **body.model_dump(),
        "logged_at": datetime.now(timezone.utc).isoformat(),
    }
    saved = await firestore_service.save_meal(uid, meal_doc)
    return MealEntry(**saved)


@router.get(
    "/history",
    response_model=list[MealEntry],
    summary="Get meal history",
)
async def get_history(
    date: str | None = Query(
        default=None,
        description="Filter by date (YYYY-MM-DD). Omit to return all entries.",
    ),
    user: dict = Depends(get_current_user),
) -> list[MealEntry]:
    """Returns the user's meal log, newest first. Optionally filtered to a single day."""
    meals = await firestore_service.get_meals(user["uid"], date_filter=date)
    return [MealEntry(**m) for m in meals]


@router.delete(
    "/history/{meal_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a meal from history",
)
async def delete_meal(
    meal_id: str,
    user: dict = Depends(get_current_user),
) -> None:
    """Permanently removes a meal entry from the user's history."""
    deleted = await firestore_service.delete_meal(user["uid"], meal_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Meal not found.")
