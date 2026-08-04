# Watch Together Server Design

## Goal

Build a Rust Axum WebSocket server for a watch-together sync service.

## In Scope (MVP)

- Multi-room support
- Playback control: `play`, `pause`, `seek`
- Host transfer mechanism
- Compact JSON over WebSocket

## Out Of Scope (Post-MVP)

- Account system
- Room persistence
- Media file hosting
- Multi-node/replication
- End-to-end encrypted rooms

## Architecture

- HTTP routes for room creation/state inspection
- One WebSocket endpoint per room for all real-time events
- Server acts as authoritative state machine for playback and host ownership
- Clients receive state snapshots and send actions only

## WebSocket Message Protocol

Use compact JSON with short field names.

### Server to Client

```json
{"t":"init","room":"r1","you":"p1","host":"p1","peers":{"p1":"Alice"},"play":{"s":"paused","pos":0}}
{"t":"state","play":{"s":"playing","pos":12400,"by":"p1","ts":1722837213000}}
{"t":"peer_joined","peer":"p2","nick":"Bob"}
{"t":"peer_left","peer":"p2"}
{"t":"host_changed","host":"p2","reason":"transfer"}
{"t":"error","code":"not_owner","msg":"playback control denied"}
```

### Client to Server

```json
{"t":"join","nick":"Alice"}
{"t":"leave"}
{"t":"play"}
{"t":"pause"}
{"t":"seek","pos":30000}
{"t":"host_transfer","to":"p2"}
```

### Field Semantics

- `t`: message type
- `room`: room id
- `you`: assigned peer id for the connection
- `host`: current host peer id
- `peers`: map of `peer_id -> nickname`
- `play.s`: playback status, `playing` or `paused`
- `play.pos`: playback position in milliseconds
- `play.by`: peer id that last changed playback state
- `play.ts`: server timestamp in milliseconds
- `pos`: seek target in milliseconds
- `to`: target peer id for host transfer
- `reason`: host change reason, such as `transfer` or `host_disconnect`
- `code`: machine-readable error code
- `msg`: human-readable error description

## Room State Model

```rust
struct Peer {
    peer_id: String,
    nickname: String,
    connected_at: u64,
    last_seen: u64,
}

enum PlaybackStatus {
    Playing,
    Paused,
}

struct PlaybackState {
    status: PlaybackStatus,
    position_ms: u64,
    updated_at: u64,
    updated_by: String,
}

struct Room {
    room_id: String,
    host_id: String,
    peers: HashMap<String, Peer>,
    playback: PlaybackState,
    created_at: u64,
}
```

## Playback Control Rules

- `play`, `pause`, and `seek` are only accepted from the current host.
- The server updates `position_ms`, `status`, `updated_at`, and `updated_by`.
- New peers receive the latest snapshot in `init`, then authoritative deltas via `state`.
- Clients remain responsible for local buffering and playback smoothing.

## Host Transfer Rules

- `host_transfer` must be sent by the current host.
- The target peer must exist in the room and cannot be the sender.
- After successful transfer, the old host becomes a normal peer.
- If the host disconnects unexpectedly, start a short lease timer before election.
- Election selects the earliest joined online peer.
- A reconnecting old host does not regain host privileges automatically.

## Multi-Room Management

- Use an in-memory registry with one state container per room.
- Each room is independent; operations on one room must not affect another.
- Room lifecycle:
  - create on demand
  - destroy or recycle when empty for configured TTL
  - cap peer count per room to limit blast radius

## Concurrency Model

- Protect room state with per-room write serialization.
- Allow concurrent reads across rooms.
- Avoid global locks during message routing.

## HTTP API

```http
POST /rooms
GET /rooms/:id/state
```

```json
POST /rooms
{"max_peers": 10}

GET /rooms/:id/state
{
  "room_id": "r1",
  "host_id": "p1",
  "peers": {"p1":"Alice","p2":"Bob"},
  "playback": {"status":"paused","position_ms":12000}
}
```

## WebSocket Route

```http
GET /ws/:room_id
```

Connection flow:

1. Client opens WS with room id.
2. Client sends `join`.
3. Server sends `init` or `error`.
4. Server broadcasts peer lifecycle events.
5. Server processes playback actions from host only.

## Error Handling

- `room_not_found`
- `room_full`
- `peer_not_found`
- `not_owner`
- `invalid_message`

## Directory Plan

```text
src/
  main.rs
  app.rs
  room/
    model.rs
    manager.rs
    playback.rs
  ws/
    handler.rs
    message.rs
```

## Implementation Order

1. Room model and manager
2. HTTP room create/state routes
3. WebSocket join/leave/broadcast
4. Playback controls with host checks
5. Host transfer and disconnect election
6. Integration tests and load checks

## Testing

- Unit tests for host-only playback mutations
- Unit tests for host transfer invalidation of old host
- Integration tests for multi-peer room broadcast ordering
- Integration tests for host disconnect election
- Negative tests for invalid room ids and malformed messages

