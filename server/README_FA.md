# RPS Duel Online Server

این پوشه مستقل روی هاست Python اجرا می‌شود.

## اجرای لوکال

```bash
cd server
python -m pip install -r requirements.txt
python start_server.py
```

Health check:

`http://127.0.0.1:8000/health`

WebSocket:

`ws://127.0.0.1:8000/ws`

روی هاست HTTPS از آدرس `wss://YOUR-DOMAIN/ws` استفاده کن.

## Command پیشنهادی هاست

```bash
uvicorn main:app --host 0.0.0.0 --port $PORT
```

SQLite به صورت خودکار در `server/rps_online.db` ساخته می‌شود.
