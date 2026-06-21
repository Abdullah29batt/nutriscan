import json
import logging
import os

import firebase_admin
from firebase_admin import auth, credentials

from app.core.config import settings

logger = logging.getLogger(__name__)

# Initialise Firebase Admin SDK once at import time.
_app: firebase_admin.App | None = None


def _get_app() -> firebase_admin.App:
    global _app
    if _app is None:
        creds_json = os.environ.get("FIREBASE_CREDENTIALS_JSON")
        if creds_json:
            creds_dict = json.loads(creds_json)
            cred = credentials.Certificate(creds_dict)
        else:
            cred = credentials.Certificate(settings.firebase_credentials_path)
        _app = firebase_admin.initialize_app(cred)
    return _app


def verify_firebase_token(id_token: str) -> dict | None:
    """
    Verify a Firebase ID token.

    Returns the decoded token claims dict on success, or None if the token
    is invalid / expired.
    """
    try:
        _get_app()
        decoded = auth.verify_id_token(id_token)
        return decoded
    except Exception as exc:
        logger.warning("Firebase token verification failed: %s", exc)
        return None
