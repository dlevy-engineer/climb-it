from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import os

from routers import crags_router
from db.database import get_engine, Base


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: ensure tables exist
    Base.metadata.create_all(bind=get_engine())
    yield
    # Shutdown: cleanup if needed


app = FastAPI(
    title="Climbate API",
    description="API for the Climbate rock climbing safety app",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS configuration
cors_origins = os.getenv("CORS_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(crags_router)


@app.get("/health")
def health_check():
    return {"status": "healthy", "service": "climbate-api"}


@app.get("/")
def root():
    return {
        "message": "Welcome to Climbate API",
        "docs": "/docs",
        "health": "/health",
    }
