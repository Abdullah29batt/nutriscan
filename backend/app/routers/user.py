from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.security import get_current_user
from app.models.stats import DailyStats
from app.models.user import UpdateProfileRequest, UserProfile
from app.services import firestore_service

router = APIRouter(prefix="/user", tags=["user"])


@router.get("/profile", response_model=UserProfile, summary="Get user profile")
async def get_profile(user: dict = Depends(get_current_user)) -> UserProfile:
    """Returns the authenticated user's Firestore profile."""
    uid = user["uid"]
    profile = await firestore_service.get_profile(uid)
    if profile is None:
        # First-time: seed profile from token claims
        profile = await firestore_service.upsert_profile(
            uid, user.get("email"), user.get("name")
        )
    return UserProfile(**profile)


@router.put("/profile", response_model=UserProfile, summary="Update user profile")
async def update_profile(
    body: UpdateProfileRequest,
    user: dict = Depends(get_current_user),
) -> UserProfile:
    """Updates writable profile fields. Only provided (non-None) fields are changed."""
    updates = {k: v for k, v in body.model_dump().items() if v is not None}
    if not updates:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No fields provided to update.",
        )
    profile = await firestore_service.update_profile(user["uid"], updates)
    return UserProfile(**profile)


@router.get("/stats", response_model=DailyStats, summary="Get daily nutrition summary")
async def get_stats(
    date: str | None = Query(
        default=None,
        description="Date to summarise (YYYY-MM-DD). Defaults to today (UTC).",
    ),
    user: dict = Depends(get_current_user),
) -> DailyStats:
    """
    Aggregates all meals logged on the given date and returns daily nutrition totals.
    """
    from datetime import date as dt_date

    target_date = date or dt_date.today().isoformat()

    meals = await firestore_service.get_meals(user["uid"], date_filter=target_date)

    totals = DailyStats(
        date=target_date,
        meal_count=len(meals),
        total_calories=sum(m.get("calories", 0) or 0 for m in meals),
        total_protein_g=sum(m.get("protein_g", 0) or 0 for m in meals),
        total_carbohydrate_g=sum(m.get("total_carbohydrate_g", 0) or 0 for m in meals),
        total_fat_g=sum(m.get("total_fat_g", 0) or 0 for m in meals),
        total_fiber_g=sum(m.get("dietary_fiber_g", 0) or 0 for m in meals),
        total_sugar_g=sum(m.get("sugars_g", 0) or 0 for m in meals),
    )
    return totals
