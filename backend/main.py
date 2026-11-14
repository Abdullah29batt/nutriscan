from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import auth, food, nutrition, user

app = FastAPI(
    title="Food AI API",
    description="AI-powered food recognition with nutritional analysis.",
    version="1.0.0",
)

# ---------------------------------------------------------------------------
# CORS — adjust origins for production
# ---------------------------------------------------------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # tighten this for production (e.g. your Flutter app's domain)
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Routers
# ---------------------------------------------------------------------------
app.include_router(auth.router)
app.include_router(food.router)
app.include_router(nutrition.router)
app.include_router(user.router)


@app.get("/", tags=["health"])
async def health_check():
    return {"status": "ok", "service": "Food AI API"}
