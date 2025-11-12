from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy import Column, Integer, String, Text, DateTime, select
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response
import os
from typing import Optional

# Database configuration - using asyncpg driver
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+asyncpg://admin:admin@postgres:5432/wikidb")

# Create async engine
engine = create_async_engine(DATABASE_URL, echo=True)
async_session_maker = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

Base = declarative_base()

# Prometheus metrics
users_created_total = Counter('users_created_total', 'Total number of users created')
posts_created_total = Counter('posts_created_total', 'Total number of posts created')

# Database models
class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    email = Column(String, unique=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)

class Post(Base):
    __tablename__ = "posts"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, index=True)
    content = Column(Text)
    author_id = Column(Integer)
    created_at = Column(DateTime, default=datetime.utcnow)

# Pydantic models
class UserCreate(BaseModel):
    username: str
    email: str

class UserResponse(BaseModel):
    id: int
    username: str
    email: str
    
    class Config:
        from_attributes = True

class PostCreate(BaseModel):
    title: str
    content: str
    author_id: int

class PostResponse(BaseModel):
    id: int
    title: str
    content: str
    author_id: int
    
    class Config:
        from_attributes = True

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

# Dependency to get async DB session
async def get_db():
    async with async_session_maker() as session:
        try:
            yield session
        finally:
            await session.close()

@app.get("/")
async def read_root():
    return {"message": "Wiki Service API - Async PostgreSQL", "version": "2.0"}

@app.post("/users/", response_model=UserResponse)
async def create_user(user: UserCreate):
    async with async_session_maker() as session:
        try:
            db_user = User(username=user.username, email=user.email)
            session.add(db_user)
            await session.commit()
            await session.refresh(db_user)
            users_created_total.inc()
            return db_user
        except Exception as e:
            await session.rollback()
            raise HTTPException(status_code=400, detail=str(e))

@app.get("/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: int):
    async with async_session_maker() as session:
        result = await session.execute(select(User).filter(User.id == user_id))
        user = result.scalar_one_or_none()
        if user is None:
            raise HTTPException(status_code=404, detail="User not found")
        return user

@app.get("/users/", response_model=list[UserResponse])
async def list_users(skip: int = 0, limit: int = 10):
    async with async_session_maker() as session:
        result = await session.execute(select(User).offset(skip).limit(limit))
        users = result.scalars().all()
        return users

@app.post("/posts/", response_model=PostResponse)
async def create_post(post: PostCreate):
    async with async_session_maker() as session:
        try:
            db_post = Post(title=post.title, content=post.content, author_id=post.author_id)
            session.add(db_post)
            await session.commit()
            await session.refresh(db_post)
            posts_created_total.inc()
            return db_post
        except Exception as e:
            await session.rollback()
            raise HTTPException(status_code=400, detail=str(e))

@app.get("/posts/{post_id}", response_model=PostResponse)
async def get_post(post_id: int):
    async with async_session_maker() as session:
        result = await session.execute(select(Post).filter(Post.id == post_id))
        post = result.scalar_one_or_none()
        if post is None:
            raise HTTPException(status_code=404, detail="Post not found")
        return post

@app.get("/posts/", response_model=list[PostResponse])
async def list_posts(skip: int = 0, limit: int = 10):
    async with async_session_maker() as session:
        result = await session.execute(select(Post).offset(skip).limit(limit))
        posts = result.scalars().all()
        return posts

@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

@app.get("/health")
async def health_check():
    """Health check endpoint for Kubernetes probes"""
    try:
        async with async_session_maker() as session:
            await session.execute(select(1))
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database connection failed: {str(e)}")
