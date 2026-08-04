# Watch Together Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved Rust Axum WebSocket watch-together MVP with multi-room support, host-only playback controls, and host transfer using compact JSON.

**Architecture:** In-memory room registry keyed by room id, per-room state mutations behind a single writer (host), and one WS route per room broadcasting authoritative state snapshots plus lifecycle events.

**Tech Stack:** Rust, Axum, Tokio, Tower HTTP, DashMap, Serde JSON

---

### Task 1: Initialize Rust project and app shell

**Files:**
- Create: `Cargo.toml`
- Create: `src/main.rs`
- Create: `src/app.rs`
- Create: `src/room/mod.rs`
- Create: `src/ws/mod.rs`

- [ ] **Step 1: Create project skeleton and placeholders**

```toml
# Cargo.toml
[package]
name = "play-together"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = { version = "0.8", features = ["json", "macros", "ws"] }
tokio = { version = "1.43", features = ["full"] }
tower = "0.5"
tower-http = { version = "0.6", features = ["cors", "trace"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
uuid = { version = "1.11", features = ["v4"] }
dashmap = "6"
tracing-subscriber = "0.3"
```

```rust
// src/main.rs
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt().init();
    let app = play_together::app::create_app();
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await?;
    axum::serve(listener, app.into_make_service()).await?;
    Ok(())
}
```

```rust
// src/app.rs
use axum::routing::get;
use room::manager::RoomManager;

pub mod room;
pub mod ws;

#[derive(Clone)]
pub struct AppState {
    pub rooms: RoomManager,
}

pub fn create_app() -> axum::Router<AppState> {
    let state = AppState {
        rooms: RoomManager::default(),
    };

    axum::Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/rooms/:room_id/state", get(room::manager::room_state))
        .route("/ws/:room_id", get(ws::handler::ws_handler))
        .with_state(state)
}
```

```rust
// src/room/mod.rs
pub mod manager;
pub mod model;
pub mod playback;
```

```rust
// src/ws/mod.rs
pub mod handler;
pub mod message;
```

- [ ] **Step 2: Verify compile**

Run: `cargo check`
Expected: succeeds with no errors

- [ ] **Step 3: Commit**

Run:
```bash
git add Cargo.toml src/**/*.rs
git commit -m "chore: scaffold project"
```

---

### Task 2: Room model and in-memory manager

**Files:**
- Create: `src/room/model.rs`
- Create: `src/room/manager.rs`

- [ ] **Step 1: Write failing test**

Create: `tests/room_model_tests.rs`

```rust
use play_together::room::model::{now_ms, Peer, PlaybackState, Room};

#[test]
fn new_room_builds_initial_room() {
    let room = Room::new("room-1".into(), "host-1".into());
    assert_eq!(room.room_id, "room-1");
    assert_eq!(room.host_id, "host-1");
    assert_eq!(room.peers.len(), 1);
    assert!(room.peers.contains_key("host-1"));
    assert_eq!(room.playback.status, play_together::room::model::PlaybackStatus::Paused);
    assert_eq!(room.playback.position_ms, 0);
}

#[test]
fn now_ms_returns_current_millis() {
    let before = now_ms();
    let after = now_ms() + 5_000;
    let current = now_ms();
    assert!(current >= before && current <= after);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test room_model_tests -- --nocapture`
Expected: fails with file not found or unresolved imports

- [ ] **Step 3: Implement room model and manager**

```rust
// src/room/model.rs
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaybackStatus {
    Playing,
    Paused,
}

#[derive(Debug, Clone)]
pub struct PlaybackState {
    pub status: PlaybackStatus,
    pub position_ms: u64,
    pub updated_at_ms: u64,
    pub updated_by: String,
}

#[derive(Debug, Clone)]
pub struct Peer {
    pub peer_id: String,
    pub nickname: String,
    pub connected_at_ms: u64,
    pub last_seen_ms: u64,
}

#[derive(Debug, Clone)]
pub struct Room {
    pub room_id: String,
    pub host_id: String,
    pub peers: HashMap<String, Peer>,
    pub playback: PlaybackState,
    pub created_at_ms: u64,
}

impl Room {
    pub fn new(room_id: String, host_id: String) -> Self {
        let now = now_ms();
        let mut peers = HashMap::new();
        peers.insert(
            host_id.clone(),
            Peer {
                peer_id: host_id.clone(),
                nickname: String::new(),
                connected_at_ms: now,
                last_seen_ms: now,
            },
        );

        Self {
            room_id,
            host_id,
            peers,
            playback: PlaybackState {
                status: PlaybackStatus::Paused,
                position_ms: 0,
                updated_at_ms: now,
                updated_by: String::new(),
            },
            created_at_ms: now,
        }
    }
}

pub fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system time")
        .as_millis() as u64
}
```

```rust
// src/room/manager.rs
use std::sync::Arc;
use dashmap::DashMap;
use parking_lot::RwLock;
use play_together::room::model::{now_ms, Peer, Room};

#[derive(Default)]
pub struct RoomManager {
    rooms: DashMap<String, Arc<RwLock<Room>>>,
}

impl RoomManager {
    pub fn create_room(&self, room_id: String) -> Arc<RwLock<Room>> {
        let host_id = format!("host-{}", room_id);
        let room = Arc::new(RwLock::new(Room::new(room_id.clone(), host_id)));
        self.rooms.insert(room_id, room.clone());
        room
    }

    pub fn get_room(&self, room_id: &str) -> Option<Arc<RwLock<Room>>> {
        self.rooms.get(room_id).map(|entry| entry.value().clone())
    }

    pub fn remove_room(&self, room_id: &str) {
        self.rooms.remove(room_id);
    }

    pub fn touch_peer(&self, room: &Arc<RwLock<Room>>, peer_id: &str) {
        if let Some(mut peer) = room.write().peers.get_mut(peer_id) {
            peer.last_seen_ms = now_ms();
        }
    }

    pub fn peer_snapshot(&self, room: &Arc<RwLock<Room>>) -> Vec<PeerSummary> {
        room.read()
            .peers
            .values()
            .map(|peer| PeerSummary {
                peer_id: peer.peer_id.clone(),
                nickname: peer.nickname.clone(),
            })
            .collect()
    }
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct PeerSummary {
    pub peer_id: String,
    pub nickname: String,
}

pub async fn room_state(
    axum::extract::State(state): axum::extract::State<crate::app::AppState>,
    axum::extract::Path(room_id): axum::extract::Path<String>,
) -> impl axum::response::IntoResponse {
    let room = match state.rooms.get_room(&room_id) {
        Some(room) => room,
        None => {
            return (axum::http::StatusCode::NOT_FOUND, "room not found").into_response();
        }
    };

    let guard = room.read();
    let payload = serde_json::json!({
        "room_id": guard.room_id,
        "host_id": guard.host_id,
        "peers": guard.peers.keys().cloned().collect::<Vec<_>>(),
        "playback": {
            "status": format!("{:?}", guard.playback.status).to_lowercase(),
            "position_ms": guard.playback.position_ms,
            "updated_at_ms": guard.playback.updated_at_ms,
            "updated_by": &guard.playback.updated_by,
        }
    });

    (axum::http::StatusCode::OK, axum::Json(payload)).into_response()
}
```

- [ ] **Step 4: Run tests to verify**

Run: `cargo test room_model_tests -- --nocapture`
Expected: PASS

- [ ] **Step 5: Commit**

Run:
```bash
git add src/room/model.rs src/room/manager.rs tests/room_model_tests.rs
git commit -m "feat: add room model and manager"
```

---

### Task 3: Playback state machine with host authority

**Files:**
- Create: `src/room/playback.rs`
- Modify: `src/room/model.rs`

- [ ] **Step 1: Write failing test**

Create: `tests/playback_tests.rs`

```rust
use play_together::room::model::{now_ms, PlaybackStatus, Room};
use play_together::room::playback::PlaybackError;

#[test]
fn only_host_can_play() {
    let room = Room::new("room-1".into(), "host-1".into());
    let mut ctx = play_together::room::playback::PlaybackContext::new(room);
    assert!(ctx.apply_play("host-1").is_ok());
    assert!(matches!(ctx.room.playback.status, PlaybackStatus::Playing));
    assert!(matches!(ctx.apply_play("peer-2"), Err(PlaybackError::NotOwner)));
}

#[test]
fn seek_updates_state() {
    let room = Room::new("room-1".into(), "host-1".into());
    let mut ctx = play_together::room::playback::PlaybackContext::new(room);
    ctx.apply_seek("host-1", 1500).unwrap();
    assert_eq!(ctx.room.playback.position_ms, 1500);
    assert_eq!(ctx.room.playback.updated_by, "host-1");
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test playback_tests -- --nocapture`
Expected: fails with unresolved imports

- [ ] **Step 3: Implement playback module**

```rust
// src/room/playback.rs
use crate::room::model::{now_ms, PlaybackStatus, PlaybackState, Room};

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum PlaybackError {
    #[error("not owner")]
    NotOwner,
}

#[derive(Debug, Clone)]
pub struct PlaybackContext {
    pub room: Room,
}

impl PlaybackContext {
    pub fn new(room: Room) -> Self {
        Self { room }
    }

    pub fn apply_play(&mut self, peer_id: &str) -> Result<(), PlaybackError> {
        self.ensure_owner(peer_id)?;
        self.room.playback.status = PlaybackStatus::Playing;
        self.mark_updated(peer_id);
        Ok(())
    }

    pub fn apply_pause(&mut self, peer_id: &str) -> Result<(), PlaybackError> {
        self.ensure_owner(peer_id)?;
        self.room.playback.status = PlaybackStatus::Paused;
        self.mark_updated(peer_id);
        Ok(())
    }

    pub fn apply_seek(&mut self, peer_id: &str, position_ms: u64) -> Result<(), PlaybackError> {
        self.ensure_owner(peer_id)?;
        self.room.playback.position_ms = position_ms;
        self.mark_updated(peer_id);
        Ok(())
    }

    fn ensure_owner(&self, peer_id: &str) -> Result<(), PlaybackError> {
        if self.room.host_id == peer_id {
            Ok(())
        } else {
            Err(PlaybackError::NotOwner)
        }
    }

    fn mark_updated(&mut self, peer_id: &str) {
        let now = now_ms();
        self.room.playback.updated_at_ms = now;
        self.room.playback.updated_by = peer_id.to_string();
    }
}
```

Update `src/room/model.rs` `PlaybackStatus` derive:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaybackStatus {
    Playing,
    Paused,
}
```

- [ ] **Step 4: Run tests to verify**

Run: `cargo test playback_tests -- --nocapture`
Expected: PASS

- [ ] **Step 5: Commit**

Run:
```bash
git add src/room/playback.rs src/room/model.rs tests/playback_tests.rs
git commit -m "feat: add host-only playback state machine"
```

---

### Task 4: Compact WebSocket protocol types

**Files:**
- Create: `src/ws/message.rs`
- Modify: `src/ws/handler.rs`

- [ ] **Step 1: Write failing test**

Create: `tests/message_tests.rs`

```rust
use play_together::ws::message::ClientMessage;

#[test]
fn join_message_deserializes() {
    let json = r#"{"t":"join","nick":"Alice"}"#;
    let message: ClientMessage = serde_json::from_str(json).expect("parse");
    assert!(matches!(message, ClientMessage::Join { nick } if nick == "Alice"));
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test message_tests -- --nocapture`
Expected: fails with unresolved import

- [ ] **Step 3: Implement message types**

```rust
// src/ws/message.rs
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ServerMessage {
    Init {
        room: String,
        you: String,
        host: String,
        peers: Vec<PeerSummary>,
        play: PlaySnapshot,
    },
    State {
        play: PlaySnapshot,
    },
    PeerJoined {
        peer: String,
        nick: String,
    },
    PeerLeft {
        peer: String,
    },
    HostChanged {
        host: String,
        reason: String,
    },
    Error {
        code: String,
        msg: String,
    },
}

#[derive(Debug, Clone, Serialize)]
pub struct PeerSummary {
    pub id: String,
    pub nick: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct PlaySnapshot {
    pub s: String,
    pub pos: u64,
    pub by: String,
    pub ts: u64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "t", rename_all = "snake_case")]
pub enum ClientMessage {
    Join {
        nick: String,
    },
    Leave,
    Play,
    Pause,
    Seek {
        pos: u64,
    },
    HostTransfer {
        to: String,
    },
}
```

- [ ] **Step 4: Run tests to verify**

Run: `cargo test message_tests -- --nocapture`
Expected: PASS

- [ ] **Step 5: Commit**

Run:
```bash
git add src/ws/message.rs tests/message_tests.rs
git commit -m "feat: add WebSocket message protocol"
```

---

### Task 5: WebSocket join/leave/host transfer flow

**Files:**
- Create: `src/ws/handler.rs`
- Modify: `src/ws/mod.rs`

- [ ] **Step 1: Write failing test**

Create: `tests/ws_flow_tests.rs`

```rust
use axum::{body::Body, Router};
use play_together::app::{create_app, AppState};
use play_together::room::manager::RoomManager;
use tower::ServiceExt;

#[tokio::test]
async fn ws_join_returns_init_text_frame() {
    let app = create_app();
    let state = AppState {
        rooms: RoomManager::default(),
    };
    state.rooms.create_room("room-1".into());

    let response = app
        .clone()
        .oneshot(
            axum::http::Request::builder()
                .uri("/ws/room-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), axum::http::StatusCode::SWITCHING_PROTOCOLS);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test ws_flow_tests::ws_join_returns_init_text_frame -- --nocapture`
Expected: FAIL because handler returns unimplemented placeholder

- [ ] **Step 3: Implement WebSocket handler**

```rust
// src/ws/handler.rs
use std::sync::Arc;
use axum::{
    extract::{ws::WebSocket, State, Path},
    response::Response,
};
use futures::{SinkExt, StreamExt};
use tokio::sync::RwLock;
use play_together::app::AppState;
use play_together::room::manager::{self, PeerSummary};
use play_together::ws::message::{ClientMessage, PlaySnapshot, ServerMessage};

pub async fn ws_handler(
    state: State<AppState>,
    Path(room_id): Path<String>,
    ws: WebSocket,
) -> Response {
    let room = match state.rooms.get_room(&room_id) {
        Some(room) => room,
        None => {
            return error_response("room_not_found", "room not found");
        }
    };

    let (mut sender, mut receiver) = ws.split();
    let peer_id = uuid::Uuid::new_v4().to_string();
    let peer_nick = format!("peer-{}", &peer_id[..4]);
    state.rooms.upsert_peer(&room, peer_id.clone(), peer_nick.clone());
    let init = build_init_message(&room_id, &peer_id, &room, peer_nick.clone()).await;

    if sender
        .send(axum::extract::ws::Message::Text(
            serde_json::to_string(&init).unwrap(),
        ))
        .await
        .is_err()
    {
        return Response::new(axum::body::Body::empty());
    }

    while let Some(Ok(message)) = receiver.next().await {
        match message {
            axum::extract::ws::Message::Text(text) => {
                let client_message: ClientMessage = match serde_json::from_str(&text) {
                    Ok(message) => message,
                    Err(err) => {
                        send_error(&mut sender, "invalid_message", err.to_string()).await;
                        continue;
                    }
                };

                match client_message {
                    ClientMessage::Leave => {
                        break;
                    }
                    ClientMessage::HostTransfer { to } => {
                        handle_host_transfer(&state, &room_id, &room, &peer_id, to, &mut sender)
                            .await;
                    }
                    ClientMessage::Play => {
                        handle_playback_action(
                            &state,
                            &room_id,
                            &room,
                            &peer_id,
                            &mut sender,
                            |ctx| ctx.apply_play(&peer_id),
                            "playing",
                        )
                        .await;
                    }
                    ClientMessage::Pause => {
                        handle_playback_action(
                            &state,
                            &room_id,
                            &room,
                            &peer_id,
                            &mut sender,
                            |ctx| ctx.apply_pause(&peer_id),
                            "paused",
                        )
                        .await;
                    }
                    ClientMessage::Seek { pos } => {
                        handle_playback_action(
                            &state,
                            &room_id,
                            &room,
                            &peer_id,
                            &mut sender,
                            |ctx| ctx.apply_seek(&peer_id, pos),
                            "seek",
                        )
                        .await;
                    }
                    ClientMessage::Join => {
                        send_error(&mut sender, "invalid_message", "join must be first").await;
                    }
                }
            }
            axum::extract::ws::Message::Close(_) => break,
            _ => {}
        }
    }

    Response::new(axum::body::Body::empty())
}

async fn build_init_message(
    room_id: &str,
    peer_id: &str,
    room: &Arc<parking_lot::RwLock<play_together::room::model::Room>>,
    peer_nick: String,
) -> ServerMessage {
    let host_id = room.read().host_id.clone();
    let peers = manager::peer_snapshot(room);
    let play = current_play_snapshot(&room);

    ServerMessage::Init {
        room: room_id.to_string(),
        you: peer_id.to_string(),
        host: host_id,
        peers,
        play,
    }
}

async fn handle_host_transfer(
    state: &AppState,
    room_id: &str,
    room: &Arc<parking_lot::RwLock<play_together::room::model::Room>>,
    peer_id: &str,
    to: String,
    sender: &mut futures::stream::SplitSink<WebSocket, axum::extract::ws::Message>,
) {
    let mut room_guard = room.write();
    if room_guard.host_id != peer_id {
        let message = error_message("not_owner", "host transfer denied");
        send_json(sender, &message).await;
        return;
    }

    if !room_guard.peers.contains_key(&to) {
        let message = error_message("peer_not_found", "target peer missing");
        send_json(sender, &message).await;
        return;
    }

    room_guard.host_id = to.clone();
    let response = ServerMessage::HostChanged {
        host: to,
        reason: "transfer".to_string(),
    };
    let _ = sender.send(axum::extract::ws::Message::Text(serde_json::to_string(&response).unwrap())).await;
}

async fn handle_playback_action<F>(
    state: &AppState,
    room_id: &str,
    room: &Arc<parking_lot::RwLock<play_together::room::model::Room>>,
    peer_id: &str,
    sender: &mut futures::stream::SplitSink<WebSocket, axum::extract::ws::Message>,
    apply: F,
    label: &str,
) where
    F: FnOnce(&mut play_together::room::playback::PlaybackContext) -> Result<(), play_together::room::playback::PlaybackError>,
{
    let mut room_guard = room.write();
    if room_guard.host_id != peer_id {
        let message = error_message("not_owner", "playback control denied");
        send_json(sender, &message).await;
        return;
    }

    let mut context = play_together::room::playback::PlaybackContext::new(room_guard.clone());
    if let Err(err) = apply(&mut context) {
        let message = error_message("playback_error", err.to_string());
        send_json(sender, &message).await;
        return;
    }

    *room_guard = context.room;
    let snapshot = current_play_snapshot(room);
    let response = ServerMessage::State { play: snapshot };
    let _ = sender.send(axum::extract::ws::Message::Text(serde_json::to_string(&response).unwrap())).await;
}

pub fn current_play_snapshot(
    room: &Arc<parking_lot::RwLock<play_together::room::model::Room>>,
) -> PlaySnapshot {
    let guard = room.read();
    PlaySnapshot {
        s: match guard.playback.status {
            play_together::room::model::PlaybackStatus::Playing => "playing".into(),
            play_together::room::model::PlaybackStatus::Paused => "paused".into(),
        },
        pos: guard.playback.position_ms,
        by: guard.playback.updated_by.clone(),
        ts: guard.playback.updated_at_ms,
    }
}

fn error_response(code: &str, message: &str) -> Response {
    let message = ServerMessage::Error {
        code: code.to_string(),
        msg: message.to_string(),
    };
    let body = serde_json::to_string(&message).unwrap();
    Response::new(axum::body::Body::from(body))
}

async fn send_error(
    sender: &mut futures::stream::SplitSink<WebSocket, axum::extract::ws::Message>,
    code: &str,
    message: impl Into<String>,
) {
    let message = error_message(code, message);
    send_json(sender, &message).await;
}

async fn send_json(
    sender: &mut futures::stream::SplitSink<WebSocket, axum::extract::ws::Message>,
    message: &ServerMessage,
) {
    let _ = sender
        .send(axum::extract::ws::Message::Text(serde_json::to_string(message).unwrap()))
        .await;
}

fn error_message(code: &str, message: impl Into<String>) -> ServerMessage {
    ServerMessage::Error {
        code: code.to_string(),
        msg: message.into(),
    }
}
```

```rust
// src/ws/mod.rs
pub mod handler;
pub mod message;
```

- [ ] **Step 4: Run tests to verify**

Run: `cargo test ws_flow_tests -- --nocapture`
Expected: PASS

- [ ] **Step 5: Commit**

Run:
```bash
git add src/ws/handler.rs src/ws/message.rs tests/ws_flow_tests.rs
git commit -m "feat: add WebSocket join/leave and host transfer"
```

---

### Task 6: Broadcast peers and finalize handler

**Files:**
- Modify: `src/ws/handler.rs`
- Modify: `src/room/manager.rs`

- [ ] **Step 1: Write failing test**

Create: `tests/ws_broadcast_tests.rs`

```rust
use std::sync::Arc;
use axum::{body::Body, Router};
use futures::{SinkExt, StreamExt};
use play_together::app::{create_app, AppState};
use play_together::room::manager::RoomManager;
use tokio::sync::RwLock;
use tower::ServiceExt;

#[tokio::test]
async fn join_returns_init_with_peers() {
    let app = create_app();
    let state = AppState {
        rooms: RoomManager::default(),
    };
    let room = state.rooms.create_room("room-1".into());
    {
        let mut guard = room.write();
        guard.peers.insert(
            "peer-2".into(),
            play_together::room::model::Peer {
                peer_id: "peer-2".into(),
                nickname: "Bob".into(),
                connected_at_ms: play_together::room::model::now_ms(),
                last_seen_ms: play_together::room::model::now_ms(),
            },
        );
    }

    let response = app
        .clone()
        .oneshot(
            axum::http::Request::builder()
                .uri("/ws/room-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), axum::http::StatusCode::SWITCHING_PROTOCOLS);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test ws_broadcast_tests::join_returns_init_with_peers -- --nocapture`
Expected: FAIL if snapshot does not include peers correctly

- [ ] **Step 3: Update handler and manager**

In `src/ws/handler.rs`, update `ServerMessage::Init` to use `manager::peer_snapshot(&room)`.
Ensure `RoomManager::upsert_peer` adds missing peers without replacing existing metadata unless needed.

```rust
// src/room/manager.rs add/update
impl RoomManager {
    pub fn upsert_peer(&self, room: &Arc<RwLock<Room>>, peer_id: String, nickname: String) {
        let mut guard = room.write();
        let now = now_ms();
        guard.peers.entry(peer_id.clone()).or_insert_with(|| Peer {
            peer_id,
            nickname,
            connected_at_ms: now,
            last_seen_ms: now,
        });
    }
}
```

- [ ] **Step 4: Run tests to verify**

Run: `cargo test ws_broadcast_tests -- --nocapture`
Expected: PASS

- [ ] **Step 5: Commit**

Run:
```bash
git add src/ws/handler.rs src/room/manager.rs tests/ws_broadcast_tests.rs
git commit -m "feat: broadcast peer snapshots in init"
```

---

### Task 7: Integration coverage for core flows

**Files:**
- Create: `tests/integration_tests.rs`

- [ ] **Step 1: Write integration test**

```rust
use axum::{body::Body, Router};
use play_together::app::{create_app, AppState};
use play_together::room::manager::RoomManager;
use tower::ServiceExt;

#[tokio::test]
async fn health_returns_ok() {
    let app = create_app();
    let response = app
        .clone()
        .oneshot(
            axum::http::Request::builder()
                .uri("/health")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), axum::http::StatusCode::OK);
    let body = axum::body::to_string(response.into_body()).await.unwrap();
    assert_eq!(body, "ok");
}

#[tokio::test]
async fn room_state_route_lists_peers() {
    let app = create_app();
    let state = AppState {
        rooms: RoomManager::default(),
    };
    state.rooms.create_room("room-1".into());

    let response = app
        .clone()
        .oneshot(
            axum::http::Request::builder()
                .uri("/rooms/room-1/state")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), axum::http::StatusCode::OK);
}
```

- [ ] **Step 2: Run integration tests**

Run: `cargo test integration_tests -- --nocapture`
Expected: PASS

- [ ] **Step 3: Run full test suite**

Run: `cargo test --workspace`
Expected: all tests pass

- [ ] **Step 4: Commit**

Run:
```bash
git add tests/integration_tests.rs
git commit -m "test: add integration tests"
```

---

### Task 8: Documentation and review

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write README**

```markdown
# Play Together Server

Rust Axum WebSocket sync server for watch-together experiences.

## Run

```bash
cargo run
```

## Connect

```bash
ws://localhost:3000/ws/<room_id>
```

## Protocol

See `docs/superpowers/specs/2026-08-04-watch-together-server-design.md` for compact JSON message formats.
```

- [ ] **Step 2: Self-review**

Run through `docs/superpowers/specs/2026-08-04-watch-together-server-design.md` and ensure each requirement has been implemented or scheduled.

- [ ] **Step 3: Commit**

Run:
```bash
git add README.md
git commit -m "docs: add README"
```

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-04-watch-together-server.md`.

Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
