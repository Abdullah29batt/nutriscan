"""
Firestore CRUD operations for user profiles and meal history.
All public functions are async; sync helpers run in a thread pool via asyncio.to_thread.
"""

import asyncio
import logging
from datetime import datetime, timezone

from firebase_admin import firestore as fb_firestore

from app.services.firebase_service import _get_app

logger = logging.getLogger(__name__)


def _db():
    _get_app()  # ensure Firebase Admin is initialized
    return fb_firestore.client()


# ── User profiles ──────────────────────────────────────────────────────────────

def _upsert_profile_sync(uid: str, email: str | None, name: str | None) -> dict:
    db = _db()
    ref = db.collection("users").document(uid)
    doc = ref.get()
    if doc.exists:
        return doc.to_dict()
    profile = {
        "uid": uid,
        "email": email,
        "name": name,
        "picture": None,
        "height_cm": None,
        "weight_kg": None,
        "date_of_birth": None,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    ref.set(profile)
    return profile


async def upsert_profile(uid: str, email: str | None, name: str | None) -> dict:
    return await asyncio.to_thread(_upsert_profile_sync, uid, email, name)


def _get_profile_sync(uid: str) -> dict | None:
    doc = _db().collection("users").document(uid).get()
    return doc.to_dict() if doc.exists else None


async def get_profile(uid: str) -> dict | None:
    return await asyncio.to_thread(_get_profile_sync, uid)


def _update_profile_sync(uid: str, updates: dict) -> dict:
    ref = _db().collection("users").document(uid)
    ref.set(updates, merge=True)
    return ref.get().to_dict()


async def update_profile(uid: str, updates: dict) -> dict:
    return await asyncio.to_thread(_update_profile_sync, uid, updates)


# ── Meal history ───────────────────────────────────────────────────────────────

def _save_meal_sync(uid: str, meal: dict) -> dict:
    _, ref = _db().collection("users").document(uid).collection("meals").add(meal)
    saved = ref.get().to_dict()
    saved["id"] = ref.id
    return saved


async def save_meal(uid: str, meal: dict) -> dict:
    return await asyncio.to_thread(_save_meal_sync, uid, meal)


def _get_meals_sync(uid: str, date_filter: str | None) -> list[dict]:
    docs = _db().collection("users").document(uid).collection("meals").stream()
    results = []
    for doc in docs:
        data = doc.to_dict()
        data["id"] = doc.id
        if date_filter and not data.get("logged_at", "").startswith(date_filter):
            continue
        results.append(data)
    results.sort(key=lambda x: x.get("logged_at", ""), reverse=True)
    return results


async def get_meals(uid: str, date_filter: str | None = None) -> list[dict]:
    return await asyncio.to_thread(_get_meals_sync, uid, date_filter)


def _delete_meal_sync(uid: str, meal_id: str) -> bool:
    ref = _db().collection("users").document(uid).collection("meals").document(meal_id)
    if not ref.get().exists:
        return False
    ref.delete()
    return True


async def delete_meal(uid: str, meal_id: str) -> bool:
    return await asyncio.to_thread(_delete_meal_sync, uid, meal_id)
