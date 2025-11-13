from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from app.database import engine
from app.models import Base
from app.routes import router
import os

# FastAPI app
app = FastAPI(title="Wiki Service API - Async")

# Mount static files
static_path = os.path.join(os.path.dirname(__file__), "app", "static")
if os.path.exists(static_path):
    app.mount("/static", StaticFiles(directory=static_path), name="static")


# Startup event to create tables
@app.on_event("startup")
async def startup():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


# Shutdown event
@app.on_event("shutdown")
async def shutdown():
    await engine.dispose()


# Include routes
app.include_router(router)
