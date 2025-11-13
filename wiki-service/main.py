from fastapi import FastAPI
from app.database import engine
from app.models import Base
from app.routes import router

# FastAPI app
app = FastAPI(title="Wiki Service API - Async")


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
