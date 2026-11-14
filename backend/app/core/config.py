from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # App
    app_name: str = "NutriScan API"
    debug: bool = False

    # Firebase Admin SDK (used to verify Firebase ID tokens and access Firestore).
    # Either point to a service-account file, or set FIREBASE_CREDENTIALS_JSON
    # to the file's JSON content (handy on Render/Railway).
    firebase_credentials_path: str = "firebase-credentials.json"

    # Gemini — the API key lives ONLY on the server, never in the mobile app.
    gemini_api_key: str
    gemini_model: str = "gemini-2.5-flash-lite"


settings = Settings()
