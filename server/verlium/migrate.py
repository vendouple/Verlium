"""Apply schema.sql. Usage:

    python -m verlium.migrate --bootstrap-user   # once, as ADMIN: creates the VERLIUM schema user
    python -m verlium.migrate                    # create/upgrade tables as VERLIUM
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

import oracledb

from .config import get_settings
from .db import connect_params

# ORA-00955 name already used, ORA-01430 column exists, ORA-02260/02261 key exists,
# ORA-01408 index on column list exists, ORA-01920 user exists, ORA-29879 domain index exists
IGNORABLE = {955, 1430, 2260, 2261, 1408, 1920, 29879}


def statements(sql: str) -> list[str]:
    parts = re.split(r"^\s*/\s*$", sql, flags=re.MULTILINE)
    out = []
    for p in parts:
        lines = [ln for ln in p.splitlines() if not ln.strip().startswith("--")]
        stmt = "\n".join(lines).strip()
        if stmt:
            out.append(stmt)
    return out


def run(conn: oracledb.Connection, stmts: list[str]) -> None:
    with conn.cursor() as cur:
        for stmt in stmts:
            head = re.sub(r'IDENTIFIED BY "[^"]*"', 'IDENTIFIED BY "***"', " ".join(stmt.split()))[:90]
            try:
                cur.execute(stmt)
                print(f"ok    {head}")
            except oracledb.DatabaseError as e:
                (err,) = e.args
                if err.code in IGNORABLE:
                    print(f"skip  {head}")
                else:
                    raise
    conn.commit()


def bootstrap_user() -> None:
    s = get_settings()
    if not s.db_admin_password or not s.db_password:
        raise SystemExit("Set VERLIUM_DB_ADMIN_PASSWORD and VERLIUM_DB_PASSWORD in .env first")
    user = s.db_user.upper()
    if not re.fullmatch(r"[A-Z][A-Z0-9_]{0,29}", user):
        raise SystemExit("VERLIUM_DB_USER must be a simple identifier")
    pwd = s.db_password.replace('"', "")
    with oracledb.connect(**connect_params("ADMIN", s.db_admin_password)) as conn:
        run(conn, [
            f'CREATE USER {user} IDENTIFIED BY "{pwd}"',
            f"GRANT CREATE SESSION, DB_DEVELOPER_ROLE, CTXAPP TO {user}",
            f"ALTER USER {user} QUOTA UNLIMITED ON DATA",
        ])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bootstrap-user", action="store_true")
    args = ap.parse_args()
    if args.bootstrap_user:
        bootstrap_user()
    sql = (Path(__file__).parent / "schema.sql").read_text(encoding="utf-8")
    with oracledb.connect(**connect_params()) as conn:
        run(conn, statements(sql))
    print("schema up to date")


if __name__ == "__main__":
    main()
