from contextlib import asynccontextmanager

from fastapi import FastAPI

from .routes import auth, health, sync
from .runtime_schema import apply_runtime_migrations


@asynccontextmanager
async def lifespan(app: FastAPI):
    apply_runtime_migrations()
    yield


app = FastAPI(
    title="Personal Todo Sync API",
    version="0.1.0",
    description="Tasks-first sync API for the Personal Todo Flutter app.",
    lifespan=lifespan,
)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(sync.router)
