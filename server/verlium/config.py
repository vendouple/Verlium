from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="VERLIUM_", env_file=".env", extra="ignore")

    db_dsn: str = ""
    db_user: str = "VERLIUM"
    db_password: str = ""
    db_admin_password: str = ""
    db_wallet_dir: str = ""
    db_wallet_password: str = ""
    db_pool_max: int = 8

    api_token: str = ""
    secret_key: str = ""
    data_dir: Path = Path("./data")

    # Ingestion
    chunk_chars: int = 1200
    chunk_overlap: int = 200
    embed_batch: int = 32  # Pollinations caps input arrays at 32


@lru_cache
def get_settings() -> Settings:
    return Settings()
