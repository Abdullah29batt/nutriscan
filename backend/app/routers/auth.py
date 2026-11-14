import logging

from fastapi import APIRouter, Depends, HTTPException, status
from firebase_admin import auth as fb_auth

from app.core.security import get_current_user
from app.models.user import LoginRequest, RegisterRequest, UserInfo
from app.services import firestore_service

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])


@router.post(
    "/register",
    response_model=UserInfo,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new user with Firebase",
)
async def register(body: RegisterRequest) -> UserInfo:
    """
    Creates a Firebase Auth account and initialises a Firestore profile document.
    The client should then sign in with the Firebase SDK to obtain an ID token.
    """
    try:
        user = fb_auth.create_user(
            email=body.email,
            password=body.password,
            display_name=body.name,
        )
    except fb_auth.EmailAlreadyExistsError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists.",
        )
    except Exception as exc:
        logger.error("Firebase create_user failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        )

    await firestore_service.upsert_profile(user.uid, user.email, body.name)
    return UserInfo(uid=user.uid, email=user.email, name=body.name)


@router.post(
    "/login",
    response_model=UserInfo,
    summary="Verify Firebase ID token and return user info",
)
async def login(body: LoginRequest) -> UserInfo:
    """
    Accepts a Firebase ID token obtained from client-side Firebase sign-in.
    Verifies the token, ensures a Firestore profile exists, and returns user info.
    """
    from app.services.firebase_service import verify_firebase_token

    decoded = verify_firebase_token(body.id_token)
    if decoded is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase ID token.",
        )

    uid = decoded.get("uid", "")
    email = decoded.get("email")
    name = decoded.get("name")

    await firestore_service.upsert_profile(uid, email, name)
    return UserInfo(uid=uid, email=email, name=name, picture=decoded.get("picture"))


@router.get("/me", response_model=UserInfo, summary="Get current authenticated user")
async def get_me(token_data: dict = Depends(get_current_user)) -> UserInfo:
    """Returns profile information extracted from the Firebase ID token."""
    return UserInfo(
        uid=token_data.get("uid", ""),
        email=token_data.get("email"),
        name=token_data.get("name"),
        picture=token_data.get("picture"),
    )
