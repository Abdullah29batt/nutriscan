import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.security import get_current_user
from app.models.coach import (
    HealthTipsRequest,
    HealthTipsResponse,
    MealFeedbackRequest,
    MealFeedbackResponse,
)
from app.services import coach_service

logger = logging.getLogger(__name__)

router = APIRouter(tags=["coach"])


@router.post(
    "/health/tips",
    response_model=HealthTipsResponse,
    summary="Get AI health tips based on today's meals",
)
async def get_health_tips(
    body: HealthTipsRequest,
    _user: dict = Depends(get_current_user),
) -> HealthTipsResponse:
    try:
        tips = await coach_service.health_tips(body.meals)
    except Exception as exc:
        logger.error("health_tips failed: %s", exc)
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "AI service unavailable")
    return HealthTipsResponse(tips=tips)


@router.post(
    "/ai/feedback",
    response_model=MealFeedbackResponse,
    summary="Get personalised AI feedback for a logged meal",
)
async def get_meal_feedback(
    body: MealFeedbackRequest,
    _user: dict = Depends(get_current_user),
) -> MealFeedbackResponse:
    try:
        feedback = await coach_service.meal_feedback(**body.model_dump())
    except Exception as exc:
        logger.error("meal_feedback failed: %s", exc)
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "AI service unavailable")
    return MealFeedbackResponse(feedback=feedback)
