from fastapi import APIRouter, HTTPException
from sqlalchemy import select
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response

from app.models import User, Post
from app.schemas import UserCreate, UserResponse, PostCreate, PostResponse
from app.database import async_session_maker
from app.metrics import users_created_total, posts_created_total

router = APIRouter()


@router.get("/")
async def read_root():
    return {"message": "Wiki Service API - Async PostgreSQL", "version": "2.0"}


@router.post("/users/", response_model=UserResponse)
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


@router.get("/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: int):
    async with async_session_maker() as session:
        result = await session.execute(select(User).filter(User.id == user_id))
        user = result.scalar_one_or_none()
        if user is None:
            raise HTTPException(status_code=404, detail="User not found")
        return user


@router.get("/users/", response_model=list[UserResponse])
async def list_users(skip: int = 0, limit: int = 10):
    async with async_session_maker() as session:
        result = await session.execute(select(User).offset(skip).limit(limit))
        users = result.scalars().all()
        return users


@router.post("/posts/", response_model=PostResponse)
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


@router.get("/posts/{post_id}", response_model=PostResponse)
async def get_post(post_id: int):
    async with async_session_maker() as session:
        result = await session.execute(select(Post).filter(Post.id == post_id))
        post = result.scalar_one_or_none()
        if post is None:
            raise HTTPException(status_code=404, detail="Post not found")
        return post


@router.get("/posts/", response_model=list[PostResponse])
async def list_posts(skip: int = 0, limit: int = 10):
    async with async_session_maker() as session:
        result = await session.execute(select(Post).offset(skip).limit(limit))
        posts = result.scalars().all()
        return posts


@router.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@router.get("/health")
async def health_check():
    """Health check endpoint for Kubernetes probes"""
    try:
        async with async_session_maker() as session:
            await session.execute(select(1))
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database connection failed: {str(e)}")
