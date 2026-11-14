from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

    # App
    app_name: str = "Food AI API"
    debug: bool = False

    # Firebase
    firebase_credentials_path: str = "firebase-credentials.json"

    # Gemini AI (replaces Nutritionix)
    gemini_api_key: str

    # Security
    secret_key: str = "graduation2026foodrecognitionapp"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 30

    # Model
    model_path: str = "../model.keras"
    model_image_size: int = 224
    model_top_k: int = 3


settings = Settings()