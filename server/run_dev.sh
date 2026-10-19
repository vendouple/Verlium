#!/usr/bin/env bash
# Dev runner: restarts the server if it exits. Uses the pure-Python event loop and HTTP parser
# (uvloop/httptools native builds have crashed under Python 3.14 on Windows).
cd "$(dirname "$0")"
while true; do
  .venv/Scripts/python -m uvicorn verlium.main:app --host 0.0.0.0 --port 8000 --loop asyncio --http h11 >> data_server.log 2>&1
  echo "$(date -Is) server exited with $?, restarting in 2s" >> data_server.log
  sleep 2
done
