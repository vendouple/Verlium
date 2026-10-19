# Verlium setup

## 1. Oracle Autonomous AI Database (Always Free)

You can use one free database for development and the other for production.

1. In the OCI Console, go to **Oracle AI Database → Autonomous AI Database → Create**.
   - Display name / database name: `verlium`
   - Workload: **Transaction Processing** (or "AI Database" / JSON, whichever your console shows)
   - Turn on **Always Free**. Version: **26ai**.
   - Set the **ADMIN password** and keep it safe.
   - Network access: **Secure access from allowed IPs and VCNs only**. Add your current public IP. Later, also add the A1 VM's public IP.
   - **Uncheck "Require mutual TLS (mTLS) authentication"**, so the server connects with plain TLS and no wallet file is needed.
2. When it's provisioned, open **Database connection**, choose **TLS** authentication, and copy the connection string for `verlium_low`.
3. In `server/`, copy `.env.example` to `.env` and fill in:
   - `VERLIUM_DB_DSN` (the string from step 2)
   - `VERLIUM_DB_ADMIN_PASSWORD`
   - `VERLIUM_DB_PASSWORD`: a new password for the app's own `VERLIUM` user. It needs 12+ characters, upper and lower case, and a digit.
   - `VERLIUM_API_TOKEN` and `VERLIUM_SECRET_KEY`: use the generator commands in the file.
4. Create the schema:

```bash
cd server
.venv/Scripts/python -m verlium.migrate --bootstrap-user
```

`--bootstrap-user` runs once as ADMIN and creates `VERLIUM`. Re-running `python -m verlium.migrate` is safe at any time. After the bootstrap you can delete `VERLIUM_DB_ADMIN_PASSWORD` from `.env`.

## 2. Run the server (development)

```bash
cd server
.venv/Scripts/python -m uvicorn verlium.main:app --reload --port 8000
```

- Health check: `GET http://localhost:8000/health`
- API docs: http://localhost:8000/docs. Every `/api/*` call needs `Authorization: Bearer <VERLIUM_API_TOKEN>`.

## 3. Add Pollinations as a provider

In the app, go to **Settings → Models → Add provider**:

- Base URL: `https://gen.pollinations.ai/v1`
- API key: your `sk_` key from enter.pollinations.ai

The key is encrypted with `VERLIUM_SECRET_KEY` before it is stored in Oracle. Then use **Fetch models** for each role and press **Test**.

## 4. Production on the A1 VM (later phase)

See `infra/` (to be added): systemd units for uvicorn and the worker, Caddy for HTTPS, and a keep-alive timer so Oracle doesn't reclaim an idle Always Free VM.

## Building the Windows app

Prerequisites: the Flutter SDK, Visual Studio Build Tools with "Desktop development with C++" and the **C++ ATL** component, and the NuGet CLI (the inline-visual WebView plugin downloads WebView2 with it):

```
winget install --id Microsoft.NuGet -e
cd app
flutter build windows --release   # → build\windows\x64\runner\Release\verlium.exe
```
