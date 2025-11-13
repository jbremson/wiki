from pydantic import BaseModel


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
