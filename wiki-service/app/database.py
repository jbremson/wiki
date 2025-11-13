from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
import os

# Database configuration - using asyncpg driver
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+asyncpg://admin:admin@postgres:5432/wikidb")

# Create async engine
engine = create_async_engine(DATABASE_URL, echo=True)
async_session_maker = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


# Dependency to get async DB session
async def get_db():
    async with async_session_maker() as session:
        try:
            yield session
        finally:
            await session.close()
