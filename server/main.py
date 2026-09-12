from __future__ import annotations

import asyncio
import json
import secrets
import sqlite3
import string
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

APP_DIR = Path(__file__).resolve().parent
DB_PATH = APP_DIR / "rps_online.db"
TOKEN_BYTES = 24
FRIEND_CODE_LEN = 7
MATCH_RECONNECT_SECONDS = 60
INVITE_TTL_SECONDS = 120

app = FastAPI(title="RPS Duel Online", version="0.1.0")


def db_connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    with db_connect() as conn:
        conn.executescript(
            """
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                token TEXT NOT NULL UNIQUE,
                username TEXT NOT NULL,
                friend_code TEXT NOT NULL UNIQUE,
                created_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS friendships (
                user_low INTEGER NOT NULL,
                user_high INTEGER NOT NULL,
                status TEXT NOT NULL,
                requested_by INTEGER NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY(user_low, user_high)
            );
            CREATE TABLE IF NOT EXISTS match_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                match_id TEXT NOT NULL,
                player_one_id INTEGER NOT NULL,
                player_two_id INTEGER NOT NULL,
                mode TEXT NOT NULL,
                winner_id INTEGER,
                ended_at REAL NOT NULL
            );
            """
        )


def clean_username(raw: Any) -> str:
    text = str(raw or "Player").strip()
    text = " ".join(text.split())
    if len(text) < 2:
        text = "Player"
    return text[:24]


def make_friend_code() -> str:
    alphabet = string.ascii_uppercase + string.digits
    while True:
        code = "".join(secrets.choice(alphabet) for _ in range(FRIEND_CODE_LEN))
        with db_connect() as conn:
            found = conn.execute(
                "SELECT 1 FROM users WHERE friend_code = ?", (code,)
            ).fetchone()
        if not found:
            return code


def get_or_create_user(token: str | None, username: str) -> dict[str, Any]:
    if token:
        with db_connect() as conn:
            row = conn.execute(
                "SELECT id, token, username, friend_code FROM users WHERE token = ?",
                (token,),
            ).fetchone()
        if row:
            return dict(row)

    new_token = secrets.token_urlsafe(TOKEN_BYTES)
    friend_code = make_friend_code()
    username = clean_username(username)
    with db_connect() as conn:
        cur = conn.execute(
            "INSERT INTO users(token, username, friend_code, created_at) VALUES (?, ?, ?, ?)",
            (new_token, username, friend_code, time.time()),
        )
        user_id = int(cur.lastrowid)
    return {
        "id": user_id,
        "token": new_token,
        "username": username,
        "friend_code": friend_code,
    }


def user_public(user_id: int) -> dict[str, Any] | None:
    with db_connect() as conn:
        row = conn.execute(
            "SELECT id, username, friend_code FROM users WHERE id = ?", (user_id,)
        ).fetchone()
    return dict(row) if row else None


def friend_pair(a: int, b: int) -> tuple[int, int]:
    return (a, b) if a < b else (b, a)


@dataclass
class QueueEntry:
    user_id: int
    mode: str
    setup: dict[str, Any]
    joined_at: float = field(default_factory=time.time)


@dataclass
class Invite:
    invite_id: str
    sender_id: int
    receiver_id: int
    mode: str
    sender_setup: dict[str, Any]
    created_at: float = field(default_factory=time.time)


@dataclass
class Room:
    match_id: str
    mode: str
    seed: int
    players: dict[int, int]
    setups: dict[int, dict[str, Any]]
    turn: int = 1
    hidden_actions: dict[int, list[dict[str, Any]]] = field(
        default_factory=lambda: {1: [], 2: []}
    )
    ready_meta: dict[int, dict[str, Any]] = field(default_factory=dict)
    event_seq: int = 0
    disconnected_at: dict[int, float] = field(default_factory=dict)

    def seat_for(self, user_id: int) -> int | None:
        for seat, uid in self.players.items():
            if uid == user_id:
                return seat
        return None

    def other_seat(self, seat: int) -> int:
        return 2 if seat == 1 else 1

    def next_seq(self) -> int:
        self.event_seq += 1
        return self.event_seq


class OnlineState:
    def __init__(self) -> None:
        self.connections: dict[int, WebSocket] = {}
        self.queues: dict[str, list[QueueEntry]] = {"normal": [], "rush": []}
        self.rooms: dict[str, Room] = {}
        self.user_room: dict[int, str] = {}
        self.invites: dict[str, Invite] = {}
        self.lock = asyncio.Lock()

    async def send(self, user_id: int, payload: dict[str, Any]) -> bool:
        ws = self.connections.get(user_id)
        if ws is None:
            return False
        try:
            await ws.send_json(payload)
            return True
        except Exception:
            return False

    async def send_room(self, room: Room, payload: dict[str, Any]) -> None:
        for user_id in room.players.values():
            await self.send(user_id, payload)

    async def send_friend_lists(self, *user_ids: int) -> None:
        for uid in set(user_ids):
            if uid in self.connections:
                await self.send(uid, build_friend_list(uid))


state = OnlineState()


def build_friend_list(user_id: int) -> dict[str, Any]:
    with db_connect() as conn:
        rows = conn.execute(
            """
            SELECT user_low, user_high, status, requested_by
            FROM friendships
            WHERE user_low = ? OR user_high = ?
            ORDER BY updated_at DESC
            """,
            (user_id, user_id),
        ).fetchall()

    friends: list[dict[str, Any]] = []
    incoming: list[dict[str, Any]] = []
    outgoing: list[dict[str, Any]] = []
    for row in rows:
        other_id = int(row["user_high"] if row["user_low"] == user_id else row["user_low"])
        other = user_public(other_id)
        if other is None:
            continue
        other["online"] = other_id in state.connections
        if row["status"] == "accepted":
            friends.append(other)
        elif int(row["requested_by"]) == user_id:
            outgoing.append(other)
        else:
            incoming.append(other)
    return {
        "type": "friend_list",
        "friends": friends,
        "incoming": incoming,
        "outgoing": outgoing,
    }


def normalize_setup(raw: Any, mode: str) -> dict[str, Any]:
    data = raw if isinstance(raw, dict) else {}
    if mode == "rush":
        return {"deck_index": 1, "hero_kind": "none", "hero_slot": "none"}

    deck_index = int(data.get("deck_index", 1))
    if deck_index not in (1, 2, 3):
        deck_index = 1
    hero_kind = str(data.get("hero_kind", "rostam")).lower()
    if hero_kind not in ("rostam", "tahmineh", "afrasiab"):
        hero_kind = "rostam"
    hero_slot = str(data.get("hero_slot", "front_left")).lower()
    valid_slots = {
        "front_left",
        "front_middle_0",
        "front_middle_1",
        "front_right",
        "back_left",
        "back_middle_0",
        "back_middle_1",
        "back_right",
    }
    if hero_slot not in valid_slots:
        hero_slot = "front_left"
    return {
        "deck_index": deck_index,
        "hero_kind": hero_kind,
        "hero_slot": hero_slot,
    }


async def create_room(
    player_one_id: int,
    player_two_id: int,
    mode: str,
    p1_setup: dict[str, Any],
    p2_setup: dict[str, Any],
) -> Room:
    match_id = secrets.token_hex(8)
    room = Room(
        match_id=match_id,
        mode=mode,
        seed=secrets.randbits(31),
        players={1: player_one_id, 2: player_two_id},
        setups={1: normalize_setup(p1_setup, mode), 2: normalize_setup(p2_setup, mode)},
    )
    state.rooms[match_id] = room
    state.user_room[player_one_id] = match_id
    state.user_room[player_two_id] = match_id

    payload_base = {
        "type": "match_found",
        "match_id": match_id,
        "mode": mode,
        "match_seed": room.seed,
        "players": {
            "1": {**(user_public(player_one_id) or {}), "setup": room.setups[1]},
            "2": {**(user_public(player_two_id) or {}), "setup": room.setups[2]},
        },
        "turn": room.turn,
    }
    await state.send(player_one_id, {**payload_base, "seat": 1})
    await state.send(player_two_id, {**payload_base, "seat": 2})
    return room


async def leave_matchmaking(user_id: int) -> None:
    for mode in list(state.queues.keys()):
        state.queues[mode] = [e for e in state.queues[mode] if e.user_id != user_id]


async def handle_matchmaking_join(user_id: int, message: dict[str, Any]) -> None:
    mode = str(message.get("mode", "normal")).lower()
    if mode not in ("normal", "rush"):
        mode = "normal"
    setup = normalize_setup(message.get("setup"), mode)

    async with state.lock:
        await leave_matchmaking(user_id)
        if user_id in state.user_room:
            await state.send(user_id, {"type": "error", "message": "Already in a match."})
            return

        queue = state.queues.setdefault(mode, [])
        opponent: QueueEntry | None = None
        while queue:
            candidate = queue.pop(0)
            if candidate.user_id == user_id:
                continue
            if candidate.user_id not in state.connections:
                continue
            if candidate.user_id in state.user_room:
                continue
            opponent = candidate
            break

        if opponent is None:
            queue.append(QueueEntry(user_id=user_id, mode=mode, setup=setup))
            await state.send(user_id, {"type": "matchmaking_waiting", "mode": mode})
            return

        # Oldest waiting player receives seat 1 for deterministic ordering.
        await create_room(opponent.user_id, user_id, mode, opponent.setup, setup)


async def handle_friend_request(user_id: int, message: dict[str, Any]) -> None:
    code = str(message.get("friend_code", "")).strip().upper()
    with db_connect() as conn:
        other = conn.execute(
            "SELECT id FROM users WHERE friend_code = ?", (code,)
        ).fetchone()
        if not other:
            await state.send(user_id, {"type": "error", "message": "Friend code not found."})
            return
        other_id = int(other["id"])
        if other_id == user_id:
            await state.send(user_id, {"type": "error", "message": "You cannot add yourself."})
            return
        low, high = friend_pair(user_id, other_id)
        existing = conn.execute(
            "SELECT status FROM friendships WHERE user_low=? AND user_high=?",
            (low, high),
        ).fetchone()
        if existing and existing["status"] == "accepted":
            await state.send(user_id, {"type": "error", "message": "Already friends."})
            return
        conn.execute(
            """
            INSERT INTO friendships(user_low, user_high, status, requested_by, updated_at)
            VALUES(?, ?, 'pending', ?, ?)
            ON CONFLICT(user_low, user_high)
            DO UPDATE SET status='pending', requested_by=excluded.requested_by, updated_at=excluded.updated_at
            """,
            (low, high, user_id, time.time()),
        )
    await state.send_friend_lists(user_id, other_id)
    await state.send(other_id, {"type": "friend_request_received", "from": user_public(user_id)})


async def handle_friend_accept(user_id: int, message: dict[str, Any]) -> None:
    other_id = int(message.get("user_id", 0))
    low, high = friend_pair(user_id, other_id)
    with db_connect() as conn:
        row = conn.execute(
            "SELECT status, requested_by FROM friendships WHERE user_low=? AND user_high=?",
            (low, high),
        ).fetchone()
        if not row or row["status"] != "pending" or int(row["requested_by"]) == user_id:
            await state.send(user_id, {"type": "error", "message": "No incoming friend request."})
            return
        conn.execute(
            "UPDATE friendships SET status='accepted', updated_at=? WHERE user_low=? AND user_high=?",
            (time.time(), low, high),
        )
    await state.send_friend_lists(user_id, other_id)


def are_friends(a: int, b: int) -> bool:
    low, high = friend_pair(a, b)
    with db_connect() as conn:
        row = conn.execute(
            "SELECT status FROM friendships WHERE user_low=? AND user_high=?",
            (low, high),
        ).fetchone()
    return bool(row and row["status"] == "accepted")


async def handle_match_invite(user_id: int, message: dict[str, Any]) -> None:
    receiver_id = int(message.get("user_id", 0))
    if not are_friends(user_id, receiver_id):
        await state.send(user_id, {"type": "error", "message": "You can only invite friends."})
        return
    if receiver_id not in state.connections:
        await state.send(user_id, {"type": "error", "message": "Friend is offline."})
        return
    mode = str(message.get("mode", "normal")).lower()
    if mode not in ("normal", "rush"):
        mode = "normal"
    invite = Invite(
        invite_id=secrets.token_hex(6),
        sender_id=user_id,
        receiver_id=receiver_id,
        mode=mode,
        sender_setup=normalize_setup(message.get("setup"), mode),
    )
    state.invites[invite.invite_id] = invite
    await state.send(
        receiver_id,
        {
            "type": "match_invite_received",
            "invite_id": invite.invite_id,
            "from": user_public(user_id),
            "mode": mode,
        },
    )
    await state.send(user_id, {"type": "match_invite_sent", "invite_id": invite.invite_id})


async def handle_match_invite_accept(user_id: int, message: dict[str, Any]) -> None:
    invite_id = str(message.get("invite_id", ""))
    invite = state.invites.get(invite_id)
    if not invite or invite.receiver_id != user_id:
        await state.send(user_id, {"type": "error", "message": "Invite is no longer valid."})
        return
    if time.time() - invite.created_at > INVITE_TTL_SECONDS:
        state.invites.pop(invite_id, None)
        await state.send(user_id, {"type": "error", "message": "Invite expired."})
        return
    if invite.sender_id not in state.connections:
        await state.send(user_id, {"type": "error", "message": "Inviter is offline."})
        return

    async with state.lock:
        await leave_matchmaking(invite.sender_id)
        await leave_matchmaking(user_id)
        if invite.sender_id in state.user_room or user_id in state.user_room:
            await state.send(user_id, {"type": "error", "message": "One player is already in a match."})
            return
        receiver_setup = normalize_setup(message.get("setup"), invite.mode)
        await create_room(
            invite.sender_id,
            user_id,
            invite.mode,
            invite.sender_setup,
            receiver_setup,
        )
        state.invites.pop(invite_id, None)


async def handle_hidden_action(user_id: int, message: dict[str, Any]) -> None:
    match_id = state.user_room.get(user_id)
    room = state.rooms.get(match_id or "")
    if room is None:
        return
    seat = room.seat_for(user_id)
    if seat is None:
        return
    turn = int(message.get("turn", -1))
    if turn != room.turn:
        await state.send(user_id, {"type": "error", "message": "Turn number mismatch."})
        return
    action = message.get("action")
    if not isinstance(action, dict):
        return
    # Tiny relay packets only; never accept giant client payloads.
    raw_size = len(json.dumps(action, separators=(",", ":")))
    if raw_size > 2048:
        await state.send(user_id, {"type": "error", "message": "Action packet is too large."})
        return
    room.hidden_actions[seat].append(action)
    await state.send(user_id, {"type": "hidden_action_ok", "turn": room.turn})


async def handle_turn_ready(user_id: int, message: dict[str, Any]) -> None:
    match_id = state.user_room.get(user_id)
    room = state.rooms.get(match_id or "")
    if room is None:
        return
    seat = room.seat_for(user_id)
    if seat is None:
        return
    turn = int(message.get("turn", -1))
    if turn != room.turn:
        await state.send(user_id, {"type": "error", "message": "Turn number mismatch."})
        return
    keep_ids = message.get("keep_ids", [])
    if not isinstance(keep_ids, list):
        keep_ids = []
    keep_ids = [int(x) for x in keep_ids[:3]]
    room.ready_meta[seat] = {"keep_ids": keep_ids}

    other = room.other_seat(seat)
    await state.send(room.players[other], {"type": "opponent_ready", "turn": room.turn})

    if 1 not in room.ready_meta or 2 not in room.ready_meta:
        return

    payload = {
        "type": "turn_reveal",
        "match_id": room.match_id,
        "turn": room.turn,
        "event_seq": room.next_seq(),
        "actions": {
            "1": list(room.hidden_actions[1]),
            "2": list(room.hidden_actions[2]),
        },
        "meta": {
            "1": dict(room.ready_meta[1]),
            "2": dict(room.ready_meta[2]),
        },
        "battle_seed": secrets.randbits(31),
        "next_turn_seed": secrets.randbits(31),
    }
    await state.send_room(room, payload)
    room.hidden_actions = {1: [], 2: []}
    room.ready_meta = {}
    room.turn += 1


async def handle_public_action(user_id: int, message: dict[str, Any]) -> None:
    match_id = state.user_room.get(user_id)
    room = state.rooms.get(match_id or "")
    if room is None:
        return
    seat = room.seat_for(user_id)
    if seat is None:
        return
    action = message.get("action")
    if not isinstance(action, dict):
        return
    if len(json.dumps(action, separators=(",", ":"))) > 2048:
        return
    other = room.other_seat(seat)
    await state.send(
        room.players[other],
        {
            "type": "public_action",
            "match_id": room.match_id,
            "turn": room.turn,
            "event_seq": room.next_seq(),
            "sender_seat": seat,
            "action": action,
        },
    )


async def handle_match_end(user_id: int, message: dict[str, Any]) -> None:
    match_id = state.user_room.get(user_id)
    room = state.rooms.get(match_id or "")
    if room is None:
        return
    winner_seat = int(message.get("winner_seat", 0))
    winner_id = room.players.get(winner_seat) if winner_seat in (1, 2) else None
    with db_connect() as conn:
        conn.execute(
            "INSERT INTO match_history(match_id, player_one_id, player_two_id, mode, winner_id, ended_at) VALUES(?, ?, ?, ?, ?, ?)",
            (
                room.match_id,
                room.players[1],
                room.players[2],
                room.mode,
                winner_id,
                time.time(),
            ),
        )
    await state.send_room(room, {"type": "match_closed", "match_id": room.match_id})
    for uid in room.players.values():
        state.user_room.pop(uid, None)
    state.rooms.pop(room.match_id, None)


async def handle_message(user_id: int, message: dict[str, Any]) -> None:
    msg_type = str(message.get("type", ""))
    if msg_type == "ping":
        await state.send(user_id, {"type": "pong", "time": time.time()})
    elif msg_type == "friend_list":
        await state.send(user_id, build_friend_list(user_id))
    elif msg_type == "friend_request":
        await handle_friend_request(user_id, message)
    elif msg_type == "friend_accept":
        await handle_friend_accept(user_id, message)
    elif msg_type == "matchmaking_join":
        await handle_matchmaking_join(user_id, message)
    elif msg_type == "matchmaking_cancel":
        await leave_matchmaking(user_id)
        await state.send(user_id, {"type": "matchmaking_cancelled"})
    elif msg_type == "match_invite":
        await handle_match_invite(user_id, message)
    elif msg_type == "match_invite_accept":
        await handle_match_invite_accept(user_id, message)
    elif msg_type == "hidden_action":
        await handle_hidden_action(user_id, message)
    elif msg_type == "turn_ready":
        await handle_turn_ready(user_id, message)
    elif msg_type == "public_action":
        await handle_public_action(user_id, message)
    elif msg_type == "match_end":
        await handle_match_end(user_id, message)
    else:
        await state.send(user_id, {"type": "error", "message": f"Unknown message: {msg_type}"})


@app.on_event("startup")
def startup() -> None:
    init_db()


@app.get("/health")
def health() -> JSONResponse:
    return JSONResponse({"ok": True, "service": "rps-duel-online", "version": "0.1.0"})


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    await websocket.accept()
    user_id: int | None = None
    try:
        first = await asyncio.wait_for(websocket.receive_json(), timeout=10.0)
        if not isinstance(first, dict) or first.get("type") != "hello":
            await websocket.send_json({"type": "error", "message": "First packet must be hello."})
            await websocket.close(code=1008)
            return

        user = get_or_create_user(
            str(first.get("token", "")) or None,
            clean_username(first.get("username", "Player")),
        )
        user_id = int(user["id"])

        previous = state.connections.get(user_id)
        if previous is not None and previous is not websocket:
            try:
                await previous.close(code=4001)
            except Exception:
                pass
        state.connections[user_id] = websocket

        await websocket.send_json(
            {
                "type": "hello_ok",
                "token": user["token"],
                "user": {
                    "id": user["id"],
                    "username": user["username"],
                    "friend_code": user["friend_code"],
                },
            }
        )
        await state.send(user_id, build_friend_list(user_id))

        room_id = state.user_room.get(user_id)
        room = state.rooms.get(room_id or "")
        if room is not None:
            seat = room.seat_for(user_id)
            room.disconnected_at.pop(seat or 0, None)
            await state.send(
                user_id,
                {
                    "type": "match_resume",
                    "match_id": room.match_id,
                    "mode": room.mode,
                    "match_seed": room.seed,
                    "seat": seat,
                    "turn": room.turn,
                    "players": {
                        "1": {**(user_public(room.players[1]) or {}), "setup": room.setups[1]},
                        "2": {**(user_public(room.players[2]) or {}), "setup": room.setups[2]},
                    },
                },
            )
            other_seat = room.other_seat(seat or 1)
            await state.send(room.players[other_seat], {"type": "opponent_reconnected"})

        # Notify online status only to friends.
        friend_payload = build_friend_list(user_id)
        for friend in friend_payload["friends"]:
            await state.send_friend_lists(int(friend["id"]), user_id)

        while True:
            message = await websocket.receive_json()
            if isinstance(message, dict):
                await handle_message(user_id, message)

    except (WebSocketDisconnect, asyncio.TimeoutError):
        pass
    except Exception as exc:
        try:
            await websocket.send_json({"type": "error", "message": f"Server error: {exc}"})
        except Exception:
            pass
    finally:
        if user_id is not None and state.connections.get(user_id) is websocket:
            state.connections.pop(user_id, None)
            await leave_matchmaking(user_id)
            room_id = state.user_room.get(user_id)
            room = state.rooms.get(room_id or "")
            if room is not None:
                seat = room.seat_for(user_id)
                if seat is not None:
                    room.disconnected_at[seat] = time.time()
                    other_seat = room.other_seat(seat)
                    await state.send(
                        room.players[other_seat],
                        {
                            "type": "opponent_disconnected",
                            "reconnect_seconds": MATCH_RECONNECT_SECONDS,
                        },
                    )
            friend_payload = build_friend_list(user_id)
            for friend in friend_payload["friends"]:
                await state.send_friend_lists(int(friend["id"]))
