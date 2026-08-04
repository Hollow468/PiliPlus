# Watch Together Client Design

## Goal

Replace the removed SyncPlay client with a minimal watch-together client that talks to the new Rust/WebSocket backend documented in `docs/api.md`, and reuse the existing “一起看” UI in a bottom-sheet dialog.

## In Scope

- Create/join room via `POST /rooms` + `ws://www.rusye.com:8998/ws/:room_id`
- Receive authoritative `state` snapshots and drive local player `play`/`pause`/`seek`
- Send local playback actions only when this peer is host
- Show room, peers, host, and RTT in the existing UI
- Replace page-style UI with bottom drawer dialog

## Out Of Scope (Post-MVP)

- Chat, host transfer UI, episode sync, complex reconnection/backoff

## Architecture

- `WatchTogetherClient`: owns WebSocket lifecycle and message protocol
- `PlayerSyncPlayController`: owns session state and player synchronization
- `syncplay_sheet.dart`: dialog UI only, consumes controller state

## Default Backend

- Host: `www.rusye.com:8998`
- Protocol: `docs/api.md`
- Remove `syncplay.pl` from official endpoints

## UI Changes

- Replace `showSyncPlaySheet` route stack with `showModalBottomSheet`/`showGeneralDialog`
- Keep existing create/join/server-config flows
- Update copy from "同步播放、暂停与选集" to "同步播放、暂停与进度"

## Message Protocol

Use compact JSON from `docs/api.md`:

```json
{"t":"join","nick":"Alice"}
{"t":"leave"}
{"t":"play"}
{"t":"pause"}
{"t":"seek","pos":30000}
```

Server authoritative state:

```json
{"t":"init","room":"r1","you":"p1","host":"p1","peers":{"p1":"Alice"},"play":{"s":"paused","pos":0,"by":"","ts":0}}
{"t":"state","play":{"s":"playing","pos":12400,"by":"p1","ts":1722837213000}}
```

## Files

- Create: `lib/services/player/watch_together_client.dart`
- Modify: `lib/pages/player/controller/player_syncplay_controller.dart`
- Modify: `lib/pages/player/syncplay_sheet.dart`
- Modify: `lib/services/player/syncplay_endpoint.dart`

## Error Handling

- Invalid room/server address -> toast
- WebSocket error/close -> exit room + toast
- Server `error` message -> toast + optional session reset

## Testing

- `WatchTogetherClient` unit tests for encode/decode of compact JSON messages
- Controller tests for `createRoom` and `state` application with fake client
