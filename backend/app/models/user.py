from pydantic import BaseModel


class UserInfo(BaseModel):
    uid: str
    email: str | None = None
    name: str | None = None
    picture: str | None = None


class UserProfile(BaseModel):
    uid: str
    email: str | None = None
    name: str | None = None
    picture: str | None = None
    height_cm: float | None = None
    weight_kg: float | None = None
    date_of_birth: str | None = None   # ISO date: YYYY-MM-DD
    created_at: str | None = None      # ISO datetime


class RegisterRequest(BaseModel):
    email: str
    password: str
    name: str


class LoginRequest(BaseModel):
    id_token: str


class UpdateProfileRequest(BaseModel):
    name: str | None = None
    picture: str | None = None
    height_cm: float | None = None
    weight_kg: float | None = None
    date_of_birth: str | None = None
