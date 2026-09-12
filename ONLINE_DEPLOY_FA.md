# RPS Duel Online Alpha — راه‌اندازی نسخه آنلاین

این بسته دو بخش دارد:

1. فایل‌های Godot که باید روی ریشه پروژه Extract/Replace شوند.
2. پوشه `server/` که باید روی هاست Python اجرا شود.

## تست لوکال

در Windows:

```bat
cd server
start.bat
```

یا:

```bash
cd server
python -m pip install -r requirements.txt
python start_server.py
```

بعد این آدرس باید JSON برگرداند:

```text
http://127.0.0.1:8000/health
```

داخل بازی:
- ONLINE را باز کن.
- Server URL:
  `ws://127.0.0.1:8000/ws`
- Username بده.
- CONNECT را بزن.

برای تست Matchmaking دو نسخه بازی را با دو Username متفاوت اجرا کن.

---

## لایو کردن روی هاست Python

هاست باید این موارد را پشتیبانی کند:

- Python 3.10+
- اجرای دائمی ASGI process
- WebSocket
- HTTPS/SSL برای استفاده از `wss://`
- فضای Writable/Persistent برای SQLite

### فایل‌هایی که روی سرور نیاز داری

کل پوشه `server/` را آپلود کن.

### نصب

داخل پوشه server:

```bash
python -m pip install -r requirements.txt
```

### دستور اجرا

اگر پنل فیلد Start Command دارد:

```bash
uvicorn main:app --host 0.0.0.0 --port $PORT
```

اگر `$PORT` توسط هاست تعریف نمی‌شود، مثلاً:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

یا:

```bash
python start_server.py
```

### تست سرور

اگر دامنه آنلاین تو مثلاً این باشد:

```text
https://duel.example.com
```

این صفحه باید باز شود:

```text
https://duel.example.com/health
```

و پاسخ چیزی شبیه این باشد:

```json
{"ok":true,"service":"rps-duel-online","version":"0.1.0"}
```

### آدرس داخل Godot

اگر SSL داری:

```text
wss://duel.example.com/ws
```

اگر سرور تستی بدون SSL روی IP/Port داری:

```text
ws://YOUR-IP:8000/ws
```

برای نسخه منتشرشده بازی بهتر است حتماً `wss://` استفاده شود.

---

## اگر Nginx جلوی Uvicorn است

نمونه بخش WebSocket:

```nginx
location /ws {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 3600;
}

location / {
    proxy_pass http://127.0.0.1:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

SSL را روی همان دامنه فعال کن. بعد بازی باید به `wss://DOMAIN/ws` وصل شود.

---

## SQLite

فایل `rps_online.db` در اولین اجرا کنار `main.py` ساخته می‌شود.

اطلاعات فعلی:
- User
- Friend Code
- Friend Request/Friends
- Match history

اگر هاست filesystem موقتی/ephemeral دارد، برای production باید Persistent Disk فعال شود یا دیتابیس بعداً به PostgreSQL منتقل شود.

---

## نکته مهم Alpha

این نسخه برای Playtest دو نفره طراحی شده است.

Server در حال حاضر:
- Matchmaking
- Friends
- Friend Invite
- Room
- Reconnect
- Hidden-action relay
- Turn reveal
- Event ordering

را کنترل می‌کند.

Rule Engine اصلی هنوز در Godot اجرا می‌شود. پس برای Ranked ضدتقلب کامل، فاز بعد باید Server-authoritative باشد.
