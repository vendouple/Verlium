import hmac

from cryptography.fernet import Fernet, InvalidToken
from fastapi import Header, HTTPException, Query

from .config import get_settings


def require_token(authorization: str = Header(default=""), token: str = Query(default="")) -> None:
    """Single-user bearer auth. `?token=` is accepted for media URLs that players fetch directly."""
    expected = get_settings().api_token
    if not expected:
        raise HTTPException(500, "VERLIUM_API_TOKEN is not configured")
    got = authorization.removeprefix("Bearer ").strip() or token
    if not hmac.compare_digest(got.encode(), expected.encode()):
        raise HTTPException(401, "Invalid token")


def _fernet() -> Fernet:
    key = get_settings().secret_key
    if not key:
        raise RuntimeError("VERLIUM_SECRET_KEY is not configured")
    return Fernet(key.encode())


def encrypt(value: str) -> str:
    return _fernet().encrypt(value.encode()).decode()


def decrypt(value: str | None) -> str:
    if not value:
        return ""
    try:
        return _fernet().decrypt(value.encode()).decode()
    except InvalidToken as e:
        raise RuntimeError("Stored API key cannot be decrypted; was VERLIUM_SECRET_KEY changed?") from e


def mask(key: str) -> str:
    if not key:
        return ""
    return key[:4] + "…" + key[-4:] if len(key) > 10 else "…"
