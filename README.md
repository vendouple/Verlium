# Verlium

A cross-device (Windows + Android) research notebook modelled 1:1 on Google's Gemini Notebook (formerly NotebookLM), with bring-your-own models and an Oracle AI Database backend.

Verlium has two parts:

- **`server/`**: a FastAPI server (Python) that stores notebooks in Oracle and runs sources, chat and Studio jobs.
- **`app/`**: the Flutter client for Windows and Android. It talks to the server over HTTP.

The server must be running before the app can do anything.

## Prerequisites

| For | You need |
| --- | --- |
| Server | Python 3.11+ and an Oracle Autonomous AI Database (the Always Free tier works) |
| Windows app | [Flutter SDK](https://docs.flutter.dev/get-started/install/windows), Visual Studio Build Tools with **Desktop development with C++** and the **C++ ATL** component, and the NuGet CLI (`winget install --id Microsoft.NuGet -e`) |
| Android app | Flutter SDK and Android Studio (Android SDK) |
| Models | An OpenAI-compatible provider, for example [Pollinations](https://enter.pollinations.ai) |

## 1. Get the code

```bash
git clone https://github.com/vendouple/Verlium.git
cd Verlium
```

## 2. Set up the server

Create a virtual environment and install the server:

```bash
cd server
python -m venv .venv
.venv/Scripts/python -m pip install -e ".[dev]"
```

On macOS or Linux, use `.venv/bin/python` instead of `.venv/Scripts/python`.

Then configure it:

1. Create the Oracle database and copy its TLS connection string. [docs/SETUP.md](docs/SETUP.md) walks through this step by step.
2. Copy `.env.example` to `.env` and fill in `VERLIUM_DB_DSN`, `VERLIUM_DB_ADMIN_PASSWORD`, `VERLIUM_DB_PASSWORD`, `VERLIUM_API_TOKEN` and `VERLIUM_SECRET_KEY`. The file has commands that generate the token and the key.
3. Create the schema. The first time, run this as ADMIN so it also creates the `VERLIUM` user:

   ```bash
   .venv/Scripts/python -m verlium.migrate --bootstrap-user
   ```

   Later upgrades only need `.venv/Scripts/python -m verlium.migrate`, which is safe to re-run.

## 3. Run the server

From `server/` in Git Bash:

```bash
./run_dev.sh
```

This serves the API on port 8000 and restarts the server if it crashes. Output goes to `server/data_server.log`. Keep the window open; closing it stops the server.

Or run it directly, for example from PowerShell:

```bash
.venv/Scripts/python -m uvicorn verlium.main:app --host 0.0.0.0 --port 8000 --loop asyncio --http h11
```

The `--loop asyncio --http h11` flags avoid native uvloop/httptools builds, which have crashed under Python 3.14 on Windows.

To check that it's up, open http://localhost:8000/health. The API docs are at http://localhost:8000/docs.

The server doesn't reload code on its own. After you pull changes or edit `server/`, restart it. With `run_dev.sh`, stopping the Python process is enough, and the script starts it again.

## 4. Run the app from source

```bash
cd app
flutter pub get
flutter run -d windows
```

For Android, connect a device (or start an emulator) and run `flutter run`.

The first time the app opens, it asks for the server address and the API token:

- On the same PC: `http://localhost:8000`.
- On a phone: your PC's LAN address, for example `http://192.168.1.20:8000`.
- The token is the `VERLIUM_API_TOKEN` from `server/.env`.

Then add a model provider in **Settings → Models → Add provider**, use **Fetch models** for each role, and press **Test**.

## 5. Build the app

**Windows:**

```bash
cd app
flutter build windows --release
```

The app is built to `app/build/windows/x64/runner/Release/verlium.exe`. It needs the DLLs and the `data` folder next to it, so keep the `Release` folder together. To put it on your desktop, make a shortcut instead of moving the exe.

Close the app before rebuilding. Windows won't let the build overwrite an exe that is running.

**Android:**

```bash
cd app
flutter build apk --release
```

The APK is written to `app/build/app/outputs/flutter-apk/app-release.apk`.

## Daily use

1. Start the server (`server/run_dev.sh`).
2. Open `verlium.exe`.

## Tests

```bash
cd server && .venv/Scripts/python -m pytest -q
cd app && flutter test
```

## More

- [docs/SETUP.md](docs/SETUP.md): Oracle database setup, providers and production notes.
- `infra/`: systemd unit, Caddy config and keep-alive script for hosting the server on a VM.
