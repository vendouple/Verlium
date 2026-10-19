"""Content-addressed blob store. Filesystem for now; OCI Object Storage adapter later (same interface)."""
from __future__ import annotations

import hashlib
import re
from pathlib import Path

from .config import get_settings

KEY_RE = re.compile(r"[0-9a-f]{64}(\.[a-z0-9]{1,8})?")


def _root() -> Path:
    root = get_settings().data_dir / "blobs"
    root.mkdir(parents=True, exist_ok=True)
    return root


def path_for(key: str) -> Path:
    if not KEY_RE.fullmatch(key or ""):
        raise ValueError("bad blob key")
    return _root() / key[:2] / key


def put(data: bytes, ext: str = "") -> tuple[str, str]:
    """Store bytes; returns (blob_key, sha256). Identical content is stored once."""
    sha = hashlib.sha256(data).hexdigest()
    key = sha + (("." + ext.lstrip(".").lower()) if ext and ext.lstrip(".").isalnum() else "")
    p = path_for(key)
    if not p.exists():
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = p.with_suffix(p.suffix + ".tmp")
        tmp.write_bytes(data)
        tmp.replace(p)
    return key, sha


def get(key: str) -> bytes:
    return path_for(key).read_bytes()
