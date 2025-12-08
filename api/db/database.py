from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from functools import lru_cache
import os

Base = declarative_base()


@lru_cache
def get_database_url() -> str:
    return os.getenv(
        "DATABASE_URL",
        "mysql+pymysql://root:localpass@localhost:3306/climbate"
    )


def get_engine():
    return create_engine(
        get_database_url(),
        pool_recycle=3600,
        pool_pre_ping=True,
    )


SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=get_engine())


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
