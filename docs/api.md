# PlayTogether Server API 文档

本文档覆盖当前 MVP 的 HTTP 接口和 WebSocket 紧凑 JSON 协议。完整 OpenAPI 文档见 `docs/openapi.yaml`。

## 基础约定

- Base URL：`http://host:3000`
- WebSocket：`ws://host:3000/ws/:room_id`
- 请求/响应体默认 JSON；WebSocket 使用紧凑 JSON，字段名尽量短
- 时间字段均为毫秒时间戳
- `peer_id` 由服务端生成，客户端不要自造
- 若房间不存在，WebSocket 握手阶段直接返回错误体并结束

## HTTP 接口

### 创建房间

```http
POST /rooms
```

请求头：

```http
Content-Type: application/json
```

请求体：

```json
{"room_id":"123456","max_peers":10}
```

响应 201：

```json
{
  "room_id": "123456",
  "host_id": "",
  "max_peers": 10
}
```

说明：
- 创建后房间内还没有真实 peer
- `room_id` 为 `6-14` 位数字；若不传则由服务端生成 `6` 位数字房间号
- 第一个成功 WebSocket `join` 的 peer 自动成为 host
- 当前 `max_peers` 仅做字段返回，未强制限制
- 同一个数字房间号不能重复创建，重复创建会返回 `409`
- 非法房间号会返回 `400`

错误示例：

`400 invalid room id`

`409 room already exists`

### 获取房间状态

```http
GET /rooms/:room_id/state
```

响应 200：

```json
{
  "room_id": "123456",
  "host_id": "p1",
  "peers": {
    "p1": "Alice",
    "p2": "Bob"
  },
  "playback": {
    "status": "paused",
    "position_ms": 12000,
    "updated_at_ms": 1722837213000,
    "updated_by": "p1"
  }
}
```

说明：
- 适合外部观察房间状态
- 实时控制请走 WebSocket

## WebSocket 消息协议

### 连接流程

1. 客户端打开 `GET /ws/:room_id`
2. 客户端发送 `join`
3. 服务端返回 `init`
4. 后续仅处理 compact JSON `Text` 帧
5. 客户端可发送 `leave` 主动断开

连接后第一个消息必须是 `join`，否则服务端返回 `error` 并终止本次连接流程。

### 客户端 -> 服务端

```json
{"t":"join","nick":"Alice"}
```

```json
{"t":"leave"}
```

```json
{"t":"play"}
```

```json
{"t":"pause"}
```

```json
{"t":"seek","pos":30000}
```

```json
{"t":"host_transfer","to":"p2"}
```

### 服务端 -> 客户端

```json
{"t":"init","room":"123456","you":"p1","host":"p1","peers":{"p1":"Alice"},"play":{"s":"paused","pos":0,"by":"","ts":0}}
```

```json
{"t":"state","play":{"s":"playing","pos":12400,"by":"p1","ts":1722837213000}}
```

```json
{"t":"peer_joined","peer":"p2","nick":"Bob"}
```

```json
{"t":"peer_left","peer":"p2"}
```

```json
{"t":"host_changed","host":"p2","reason":"transfer"}
```

```json
{"t":"error","code":"not_owner","msg":"playback control denied"}
```

### 消息类型与字段

`init`
- `room`：房间 ID
- `you`：当前连接被分配的 `peer_id`
- `host`：当前 host 的 `peer_id`
- `peers`：`peer_id -> nickname`
- `play.s`：`playing` 或 `paused`
- `play.pos`：毫秒位置
- `play.by`：最后一次播放状态变更的 `peer_id`
- `play.ts`：最后一次变更的时间戳

`state`
- `play.s`
- `play.pos`
- `play.by`
- `play.ts`

`peer_joined`
- `peer`
- `nick`

`peer_left`
- `peer`

`host_changed`
- `host`
- `reason`：`transfer` 或 `host_disconnect`

`error`
- `code`
- `msg`

### 控制规则

- `play`、`pause`、`seek` 只接受当前 host
- `host_transfer` 只接受当前 host
- `to` 必须是房间内其他 peer
- 客户端可发送 `leave` 主动离开

## 错误码

`room_not_found`
`room_full`
`peer_not_found`
`not_owner`
`invalid_message`
`room_already_exists`
`invalid_room_id`

## 状态规则

- 第一个成功 `join` 的 peer 自动成为 host
- host 可转让给房间内其他 peer
- host 断开后，自动选举最早加入的在线 peer 成为新 host
- 房间为空时自动回收

## 示例流程

1. 创建房间

```bash
curl -X POST http://localhost:3000/rooms -H 'Content-Type: application/json' -d '{"room_id":"123456","max_peers":10}'
```

2. WebSocket join

```json
{"t":"join","nick":"Alice"}
```

3. Host 播放

```json
{"t":"play"}
```

4. Host 转让

```json
{"t":"host_transfer","to":"p2"}
```
