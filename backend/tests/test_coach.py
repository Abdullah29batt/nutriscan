"""
Tests for the coach endpoints (/health/tips, /ai/feedback).

Gemini and Firebase are mocked, so these run offline with no credentials:
    cd backend
    pip install -r requirements-dev.txt
    pytest
"""

import os

os.environ.setdefault("GEMINI_API_KEY", "test-key")

import pytest
from fastapi.testclient import TestClient

from app.core.security import get_current_user
from app.services import coach_service
from main import app


@pytest.fixture
def client():
    app.dependency_overrides[get_current_user] = lambda: {"uid": "test-user"}
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_health_tips_ok(client, monkeypatch):
    async def fake_health_tips(meals, count=3):
        assert meals == ["koshari", "banana"]
        return ["Drink water.", "Add vegetables.", "Watch portions."]

    monkeypatch.setattr(coach_service, "health_tips", fake_health_tips)
    r = client.post("/health/tips", json={"meals": ["koshari", "banana"]})
    assert r.status_code == 200
    assert r.json() == {"tips": ["Drink water.", "Add vegetables.", "Watch portions."]}


def test_health_tips_ai_failure_returns_502(client, monkeypatch):
    async def boom(meals, count=3):
        raise RuntimeError("quota exceeded")

    monkeypatch.setattr(coach_service, "health_tips", boom)
    r = client.post("/health/tips", json={"meals": []})
    assert r.status_code == 502


def test_meal_feedback_ok(client, monkeypatch):
    async def fake_feedback(**kwargs):
        assert kwargs["food_name"] == "kunafa"
        return "Tasty, but high in sugar."

    monkeypatch.setattr(coach_service, "meal_feedback", fake_feedback)
    r = client.post(
        "/ai/feedback",
        json={
            "food_name": "kunafa",
            "calories": 380,
            "protein": 8,
            "carbs": 55,
            "fat": 15,
            "calorie_goal": 2000,
            "today_calories": 1200,
            "allergies": ["Nuts"],
            "diet_restrictions": [],
            "health_goal": "Lose weight",
        },
    )
    assert r.status_code == 200
    assert r.json() == {"feedback": "Tasty, but high in sugar."}


def test_meal_feedback_validates_input(client):
    r = client.post("/ai/feedback", json={"food_name": "", "calories": -1})
    assert r.status_code == 422


def test_endpoints_require_auth():
    """Without the dependency override, a missing bearer token is rejected."""
    app.dependency_overrides.clear()
    c = TestClient(app)
    assert c.post("/health/tips", json={"meals": []}).status_code in (401, 403)
    assert c.post("/ai/feedback", json={}).status_code in (401, 403)
