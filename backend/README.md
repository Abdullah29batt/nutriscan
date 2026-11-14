# NutriScan — Backend (FastAPI)

REST API for the NutriScan app. It handles authentication (Firebase ID tokens), food recognition and nutrition lookup via Gemini, meal history and profile in Firestore, and the AI coach (health tips, meal feedback).

## Run locally

```bash
python -m venv venv && source venv/bin/activate     # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env                                # set GEMINI_API_KEY
# put the Firebase service-account JSON at ./firebase-credentials.json
#   (or set FIREBASE_CREDENTIALS_JSON to its content)
uvicorn main:app --reload
```

Docs: <http://localhost:8000/docs>

## Configuration (`.env`)

| Variable | Required | Description |
|---|---|---|
| `GEMINI_API_KEY` | ✅ | Google Gemini API key |
| `GEMINI_MODEL` | – | Defaults to `gemini-2.5-flash-lite` |
| `FIREBASE_CREDENTIALS_PATH` | ✅* | Path to the service-account JSON |
| `FIREBASE_CREDENTIALS_JSON` | ✅* | Alternative: the JSON content (for PaaS hosting) |

\* one of the two.

## Tests

```bash
pip install -r requirements-dev.txt
pytest
```

Gemini and Firebase are mocked, so the tests need no credentials or network.

## Layout

```
app/
├── core/       config (pydantic-settings), Firebase-JWT auth dependency
├── models/     Pydantic request/response schemas
├── routers/    auth, food, nutrition, user, coach
└── services/   ai_service (Gemini Vision), gemini_nutrition_service,
                coach_service, firebase_service, firestore_service
```

## Deploy

`render.yaml` deploys to Render. Set `GEMINI_API_KEY` and `FIREBASE_CREDENTIALS_JSON` as environment variables in the dashboard.
