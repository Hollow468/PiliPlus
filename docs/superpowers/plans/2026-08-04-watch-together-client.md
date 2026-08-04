# Watch Together Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved watch-together client for the new Rust/WebSocket backend, and switch the existing “一起看” UI from page-style flow to a bottom drawer dialog while keeping the current video page entry point.

**Architecture:** Add a small protocol client for compact JSON messages, rewire the hollow `PlayerSyncPlayController` to own a real session, and keep UI as a dialog that consumes the controller’s observable room state.

**Tech Stack:** Flutter, Dart, WebSocket in `lib/services/player`, GetX controller in `lib/pages/player/controller`, bottom-sheet dialog in `lib/pages/player/syncplay_sheet.dart`.

---

### Task 1: Add compact JSON protocol model

**Files:**
- Create: `lib/services/player/watch_together_message.dart`
- Test: `test/watch_together_message_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
void main() {
  test('encodes join and decodes init', () {
    final encoded = ClientMessage.join(nick: 'Alice').toJson();
    expect(encoded, {'t': 'join', 'nick': 'Alice'});

    final message = ServerMessage.parse({'t': 'init', 'room': 'r1', 'you': 'p1', 'host': 'p1', 'peers': {'p1': 'Alice'}, 'play': {'s': 'paused', 'pos': 0, 'by': '', 'ts': 0}});
    expect(message.room, 'r1');
    expect(message.peers['p1'], 'Alice');
    expect(message.play?.status, PlayStatus.paused);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/watch_together_message_test.dart -v`
Expected: FAIL with `ServerMessage.parse` / message model missing

- [ ] **Step 3: Write minimal implementation**

```dart
enum PlayStatus { playing, paused }

class PlaySnapshot {
  const PlaySnapshot({required this.status, required this.positionMs, this.updatedBy, this.updatedAtMs});
  final PlayStatus status;
  final int positionMs;
  final String? updatedBy;
  final int? updatedAtMs;

  factory PlaySnapshot.fromJson(Map<String, dynamic> json) {
    return PlaySnapshot(
      status: json['s'] == 'playing' ? PlayStatus.playing : PlayStatus.paused,
      positionMs: (json['pos'] as int?) ?? 0,
      updatedBy: json['by'] as String?,
      updatedAtMs: json['ts'] as int?,
    );
  }
}

class ServerMessage {
  const ServerMessage.init({required this.room, required this.you, required this.host, required this.peers, required this.play})
      : type = 'init', error = null, code = null;
  const ServerMessage.state({required this.play, this.peers, this.host}) : type = 'state', room = null, you = null, error = null, code = null;
  const ServerMessage.peerJoined({required this.peer, required this.nick}) : type = 'peer_joined', room = null, you = null, host = null, play = null, error = null, code = null;
  const ServerMessage.peerLeft({required this.peer}) : type = 'peer_left', room = null, you = null, host = null, play = null, nick = null, error = null, code = null;
  const ServerMessage.hostChanged({required this.host, this.reason}) : type = 'host_changed', room = null, you = null, play = null, error = null, code = null;
  const ServerMessage.error({required this.code, required this.message}) : type = 'error', room = null, you = null, host = null, play = null, peer = null, nick = null, reason = null;

  final String type;
  final String? room;
  final String? you;
  final String? host;
  final Map<String, String>? peers;
  final PlaySnapshot? play;
  final String? peer;
  final String? nick;
  final String? reason;
  final String? code;
  final String? message;

  factory ServerMessage.parse(Map<String, dynamic> json) {
    final type = json['t'] as String;
    return switch (type) {
      'init' => ServerMessage.init(room: json['room'] as String, you: json['you'] as String, host: json['host'] as String, peers: Map<String, String>.from(json['peers'] as Map), play: PlaySnapshot.fromJson(Map<String, dynamic>.from(json['play'] as Map))),
      'state' => ServerMessage.state(play: PlaySnapshot.fromJson(Map<String, dynamic>.from(json['play'] as Map)), peers: json['peers'] != null ? Map<String, String>.from(json['peers'] as Map) : null, host: json['host'] as String?),
      'peer_joined' => ServerMessage.peerJoined(peer: json['peer'] as String, nick: json['nick'] as String),
      'peer_left' => ServerMessage.peerLeft(peer: json['peer'] as String),
      'host_changed' => ServerMessage.hostChanged(host: json['host'] as String, reason: json['reason'] as String?),
      'error' => ServerMessage.error(code: json['code'] as String, message: json['msg'] as String),
      _ => throw FormatException('unknown message type $type'),
    };
  }
}

class ClientMessage {
  const ClientMessage._();
  static Map<String, dynamic> join({required String nick}) => {'t': 'join', 'nick': nick};
  static Map<String, dynamic> leave() => const {'t': 'leave'};
  static Map<String, dynamic> play() => const {'t': 'play'};
  static Map<String, dynamic> pause() => const {'t': 'pause'};
  static Map<String, dynamic> seek({required int positionMs}) => {'t': 'seek', 'pos': positionMs};
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/watch_together_message_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/player/watch_together_message.dart test/watch_together_message_test.dart
git commit -m "feat: add watch-together compact json messages"
```

---

### Task 2: Implement WebSocket watch-together client

**Files:**
- Create: `lib/services/player/watch_together_client.dart`
- Test: `test/watch_together_client_test.dart`
- Modify: `lib/services/player/syncplay_endpoint.dart`

- [ ] **Step 1: Write the failing test**

```dart
void main() {
  test('connects and routes init/state messages', () async {
    final channel = WebSocketChannelForTest();
    final client = WatchTogetherClient.createForTest(channel: channel);
    channel.respondText({'t': 'init', 'room': 'r1', 'you': 'p1', 'host': 'p1', 'peers': {'p1': 'Alice'}, 'play': {'s': 'paused', 'pos': 5, 'by': '', 'ts': 0}});

    await client.connect(endPoint: SyncPlayEndPoint(host: 'host', port: 8998), room: 'r1', username: 'Alice');
    final init = client.messages.firstWhere((message) => message.type == 'init');
    expect(init.room, 'r1');

    channel.sendText({'t': 'state', 'play': {'s': 'playing', 'pos': 1000, 'by': 'p1', 'ts': 1}});
    final state = client.messages.firstWhere((message) => message.type == 'state');
    expect(state.play?.status, PlayStatus.playing);
    expect(state.play?.positionMs, 1000);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/watch_together_client_test.dart -v`
Expected: FAIL with missing `WatchTogetherClient`

- [ ] **Step 3: Write minimal implementation**

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/player/watch_together_message.dart';
import 'package:PiliPlus/services/player/syncplay_endpoint.dart';

class WatchTogetherClient {
  WatchTogetherClient._({required this.endPoint, required this.room, required this.username, required this.webSocketFactory, required this.httpClientFactory})
      : _webSocketFactory = webSocketFactory,
        _httpClientFactory = httpClientFactory;

  factory WatchTogetherClient.createForTest({required WebSocketChannelForTest channel, required SyncPlayEndPoint endPoint, required String room, required String username}) {
    return WatchTogetherClient._(
      endPoint: endPoint,
      room: room,
      username: username,
      webSocketFactory: (Uri uri) => Stream<WebSocketMessage>.value(TextMessage(utf8.encode(json.encode({'t': 'init', 'room': room, 'you': 'p1', 'host': 'p1', 'peers': {'p1': username}, 'play': {'s': 'paused', 'pos': 0, 'by': '', 'ts': 0}}))) as Stream<WebSocketMessage>,
      httpClientFactory: () => _FakeHttpClient(createdRoomId: room),
    );
  }

  final SyncPlayEndPoint endPoint;
  final String room;
  final String username;
  final WebSocketChannel Function(Uri uri) _webSocketFactory;
  final HttpClient Function() _httpClientFactory;

  final StreamController<ServerMessage> _controller = StreamController<ServerMessage>.broadcast();
  Stream<ServerMessage> get messages => _controller.stream;
  bool get isConnected => _socket != null && !_socket!.closeCode!.isNegative;

  WebSocketChannel? _socket;
  HttpClientRequest? _roomRequest;
  Timer? _staleTimer;

  Future<void> connect() async {
    final client = _httpClientFactory();
    final request = await client.postUrl(Uri.parse('http://${endPoint.host}:${endPoint.port}/rooms'));
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode('{}'));
    final response = await request.close();
    final body = await response.stream.bytesToString();
    final jsonBody = json.decode(body) as Map<String, dynamic>;
    final roomId = jsonBody['room_id'] as String? ?? room;
    final uri = Uri.parse('ws://${endPoint.host}:${endPoint.port}/ws/$roomId');
    final socket = _webSocketFactory(uri);
    _socket = socket;
    _staleTimer?.cancel();
    _staleTimer = Timer(const Duration(minutes: 5), () {
      if (isConnected) {
        unawaited(disconnect());
      }
    });
    socket.stream.listen((event) {
      final text = event is! TextMessage ? '' : utf8.decode(event.bytes);
      final decoded = json.decode(text) as Map<String, dynamic>;
      _controller.add(ServerMessage.parse(decoded));
    }, onError: (Object error,StackTrace stackTrace) {
      _controller.addError(error, stackTrace);
    }, onDone: () {
      _controller.close();
    });
    socket.sink.add(json.encode(ClientMessage.join(nick: username)));
  }

  Future<void> disconnect() async {
    await _staleTimer?.cancel();
    _staleTimer = null;
    if (_socket != null) {
      try {
        _socket!.sink.add(json.encode(ClientMessage.leave()));
      } catch (_) {}
      await _socket!.sink.close();
      _socket = null;
    }
    await _controller.close();
  }
}

extension on int {
  bool get isNegative => this < 0;
}

class WebSocketChannelForTest implements WebSocketChannel {
  WebSocketChannelForTest({Stream<WebSocketMessage>? stream}) : _stream = stream ?? const Stream<WebSocketMessage>.empty();
  final Stream<WebSocketMessage> _stream;
  final List<TextMessage> _sent = [];
  List<TextMessage> get sent => _sent;

  @override
  Stream<WebSocketMessage> get stream => _stream;
  @override
  Sink<WebSocketMessage> get sink => _TestSink(this);

  void respondText(Map<String, dynamic> json) {
    _sent.last.bytes = utf8.encode(json.encode(json));
  }
}

class _TestSink implements Sink<WebSocketMessage> {
  _TestSink(this.channel);
  final WebSocketChannelForTest channel;
  @override
  void add(WebSocketMessage data) {
    if (data is TextMessage) channel._sent.add(TextMessage(data.bytes));
  }
  @override
  void close() {}
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({required this.createdRoomId});
  final String createdRoomId;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _FakeHttpClientRequest(createdRoomId: createdRoomId);
  @override
  bool get autoUncompress => false;
  @override
  set autoUncompress(bool value) {}
  @override
  Future<void> close({bool force = false}) async {}
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) async => throw UnsupportedError('deleteUrl');
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => throw UnsupportedError('getUrl');
  @override
  Future<HttpClientRequest> headUrl(Uri url) async => throw UnsupportedError('headUrl');
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => throw UnsupportedError('openUrl');
  @override
  Future<HttpClientRequest> patchUrl(Uri url) async => throw UnsupportedError('patchUrl');
  @override
  Future<HttpClientRequest> post(Uri url, {List<int>? body}) async => throw UnsupportedError('post');
  @override
  Future<HttpClientRequest> putUrl(Uri url) async => throw UnsupportedError('putUrl');
  @override
  Future<HttpClientRequest> put(Uri url, {List<int>? body}) async => throw UnsupportedError('put');
  @override
  Future<HttpClientRequest> openRequest({String method = 'GET', String? password, bool followRedirects = true, int maxRedirects = 5, String? username}) async => throw UnsupportedError('openRequest');
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) async => throw UnsupportedError('delete');
  @override
  Future<HttpClientRequest> get(String host, int port, String path) async => throw UnsupportedError('get');
  @override
  Future<HttpClientRequest> head(String host, int port, String path) async => throw UnsupportedError('head');
  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) async => throw UnsupportedError('open');
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) async => throw UnsupportedError('patch');
  @override
  Future<HttpClientRequest> post(String host, int port, String path, {List<int>? body}) async => throw UnsupportedError('post');
  @override
  Future<HttpClientRequest> put(String host, int port, String path, {List<int>? body}) async => throw UnsupportedError('put');
  @override
  Future<HttpClientRequest> openUrl(String method, String url) async => throw UnsupportedError('openUrl');
}

class _FakeHttpClientRequest extends HttpClientRequest {
  _FakeHttpClientRequest({required this.createdRoomId});
  final String createdRoomId;
  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse(createdRoomId: createdRoomId);
  @override
  HttpClientHeaders get headers => _FakeHttpClientHeaders();
  @override
  set headers(HttpClientHeaders value) {}
  @override
  List<int> get buffer => throw UnsupportedError('buffer');
  @override
  set buffer(List<int> value) {}
  @override
  Encoding get encoding => utf8;
  @override
  set encoding(Encoding value) {}
  @override
  bool get done => false;
  @override
  int get contentLength => -1;
  @override
  set contentLength(int value) {}
  @override
  bool get persistentConnection => true;
  @override
  set persistentConnection(bool value) {}
  @override
  bool get bufferedOutput => false;
  @override
  set bufferedOutput(bool value) {}
  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<HttpClientResponse> redirect(List<Uri>? follows, {bool closeOrMoveDelay = true, int maxRedirects = 5}) async => throw UnsupportedError('redirect');
  @override
  void write(String content) {}
  @override
  void writeAll(Iterable<String> contents) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? object = '']) {}
  @override
  void flush() {}
  @override
  void abort() {}
}

class _FakeHttpClientResponse extends HttpClientResponse {
  _FakeHttpClientResponse({required this.createdRoomId});
  final String createdRoomId;
  @override
  HttpClientRequest get request => throw UnsupportedError('request');
  @override
  int get statusCode => 201;
  @override
  X509Certificate? get certificate => null;
  @override
  String get reasonPhrase => 'created';
  @override
  int get contentLength => -1;
  @override
  List<Cookie> get cookies => <Cookie>[];
  @override
  HttpConnectionInfo get connectionInfo => throw UnsupportedError('connectionInfo');
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => true;
  @override
  Future<String> toString() async => 'FakeResponse';
  @override
  HttpClientHeaders get headers => _FakeHttpClientHeaders();
  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event) onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final bytes = utf8.encode(json.encode({'room_id': createdRoomId}));
    return Stream<List<int>>.value(bytes).listen(onData, onDone: onDone, onError: onError, cancelOnError: cancelOnError);
  }
}

class _FakeHttpClientHeaders implements HttpClientHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void clear() {}
  @override
  List<String>? operator [](String name) => null;
  @override
  void forEach(void Function(String name, String value) f) {}
  @override
  bool get isKeepAlive => false;
  @override
  set isKeepAlive(bool value) {}
  @override
  bool get isPersistentConnection => true;
  @override
  bool get chunkedTransferEncoding => false;
  @override
  String? get(String name, {String defaultValue = ''}) => null;
  @override
  DateTime? date() => null;
  @override
  DateTime? expires() => null;
  @override
  String? ifModifiedSince() => null;
  @override
  DateTime? ifUnmodifiedSince() => null;
  @override
  int? maxAge() => null;
  @override
  DateTime? parsed(HttpDate date) => null;
  @override
  String? value(String name) => null;
  @override
  List<String> values(String name) => <String>[];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/watch_together_client_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/player/watch_together_client.dart test/watch_together_client_test.dart lib/services/player/syncplay_endpoint.dart
git commit -m "feat: add watch-together websocket client"
```

---

### Task 3: Rewire controller to new backend

**Files:**
- Modify: `lib/pages/player/controller/player_syncplay_controller.dart`
- Test: `test/player_syncplay_controller_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
void main() {
  test('createRoom opens session and exits room clears state', () async {
    final client = WatchTogetherClientFake();
    final controller = PlayerSyncPlayController(
      bangumiId: () => 1,
      currentEpisode: () => 1,
      currentRoad: () => 1,
      playing: () => false,
      currentPosition: () => Duration.zero,
      playerPosition: () => Duration.zero,
      duration: () => Duration.zero,
      pause: ({bool enableSync = true}) => Future.value(),
      play: ({bool enableSync = true}) => Future.value(),
      seek: (Duration position, {bool enableSync = true}) => Future.value(),
      changeEpisode: (int episode, {int? currentRoad, int? offset}) => Future.value(),
    );
    controller.clientFactory = (_) => client;

    await controller.createRoom('123456', 'Alice');
    expect(controller.hasSession, isTrue);
    expect(controller.syncplayRoom.value, '123456');

    await controller.exitRoom();
    expect(controller.hasSession, isFalse);
    expect(controller.syncplayRoom.value, '');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/player_syncplay_controller_test.dart -v`
Expected: FAIL with missing factory/hooks

- [ ] **Step 3: Write minimal implementation**

```dart
import 'dart:async';
import 'package:PiliPlus/services/player/syncplay_endpoint.dart';
import 'package:PiliPlus/services/player/watch_together_client.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class WatchTogetherClientFake implements WatchTogetherClient {
  WatchTogetherClientFake();
  bool disconnected = false;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async { disconnected = true; }
  @override
  Stream<ServerMessage> get messages => const Stream.empty();
  @override
  SyncPlayEndPoint get endPoint => const SyncPlayEndPoint(host: 'host', port: 80);
  @override
  String get room => '123456';
  @override
  String get username => 'Alice';
}

class PlayerSyncPlayController extends GetxController {
  PlayerSyncPlayController({
    required this.bangumiId,
    required this.currentEpisode,
    required this.currentRoad,
    required this.playing,
    required this.currentPosition,
    required this.playerPosition,
    required this.duration,
    required this.pause,
    required this.play,
    required this.seek,
    required this.changeEpisode,
  });

  final int Function() bangumiId;
  final int Function() currentEpisode;
  final int Function() currentRoad;
  final bool Function() playing;
  final Duration Function() currentPosition;
  final Duration Function() playerPosition;
  final Duration Function() duration;
  final Future<void> Function({bool enableSync}) pause;
  final Future<void> Function({bool enableSync}) play;
  final Future<void> Function(Duration duration, {bool enableSync}) seek;
  final Future<void> Function(int episode, {int? currentRoad, int? offset}) changeEpisode;
  WatchTogetherClient Function(SyncPlayEndPoint endPoint, String room, String username)? clientFactory;

  @override
  void onInit() {
    super.onInit();
    _currentFileName.value = "${bangumiId()}[${currentEpisode()}]";
  }

  @override
  void onClose() {
    unawaited(dispose());
    super.onClose();
  }

  final RxString syncplayRoom = ''.obs;
  final RxInt syncplayClientRtt = 0.obs;
  WatchTogetherClient? _client;
  bool get hasSession => _client != null;
  final RxString _currentFileName = ''.obs;
  Timer? _staleSessionTimer;

  Future<void> createRoom(String room, String username) async {
    final endPointString = GStorage.setting.get(SettingBoxKey.syncPlayEndPoint, defaultValue: defaultSyncPlayEndPoint) ?? defaultSyncPlayEndPoint;
    final parsed = parseSyncPlayEndPoint(endPointString);
    if (parsed == null) {
      SmartDialog.showToast('一起看: 服务器地址不合法 $endPointString');
      return;
    }
    await exitRoom();
    final client = (clientFactory ?? WatchTogetherClient.new)(parsed, room, username);
    _client = client;
    _currentFileName.value = "${bangumiId()}[${currentEpisode()}]";
    _staleSessionTimer?.cancel();
    _staleSessionTimer = Timer(const Duration(minutes: 5), () {
      if (identical(_client, client)) {
        exitRoom();
        SmartDialog.showToast('一起看: 连接超时');
      }
    });
    client.messages.listen((message) {
      if (!identical(_client, client)) return;
      _onMessage(message);
    }, onError: (Object error,StackTrace stackTrace) {
      if (!identical(_client, client)) return;
        logger.e('一起看: $error', error: error, stackTrace: stackTrace);
        SmartDialog.showToast('一起看: 连接异常');
        exitRoom();
    }, onDone: () {
      if (!identical(_client, client)) return;
      exitRoom();
    });
    try {
      await client.connect();
      syncplayRoom.value = room;
      GStorage.setting.put(SettingBoxKey.syncPlayUserName, username);
    } catch (e) {
      logger.e('一起看: $e', error: e);
      await client.disconnect();
      _client = null;
      syncplayRoom.value = '';
      syncplayClientRtt.value = 0;
      SmartDialog.showToast('一起看: 连接失败');
      rethrow;
    }
  }

  void _onMessage(ServerMessage message) {
    switch (message.type) {
      case 'init':
        syncplayClientRtt.value = 0;
      case 'state':
        final play = message.play;
        if (play == null) break;
        final shouldPlay = play.status == PlayStatus.playing;
        final target = Duration(milliseconds: play.positionMs);
        final diff = (playerPosition().inMilliseconds - target.inMilliseconds).abs();
        if (shouldPlay != playing()) {
          if (shouldPlay) {
            unawaited(play(enableSync: false));
          } else {
            unawaited(pause(enableSync: false));
          }
        }
        if (diff > 1000 && duration().inMilliseconds > 0) {
          unawaited(seek(target, enableSync: false));
        }
        syncplayClientRtt.value = (play.updatedAtMs == null) ? 0 : (DateTime.now().millisecondsSinceEpoch - play.updatedAtMs!).abs();
      case 'peer_joined':
      case 'peer_left':
      case 'host_changed':
        break;
      case 'error':
        SmartDialog.showToast('一起看: ${message.message}');
    }
  }

  Future<void> sendPlayback({bool? enablePlay}) async {
    final client = _client;
    if (client == null) return;
    if (enablePlay == true) {
      client.sink.add(ClientMessage.play());
    } else if (enablePlay == false) {
      client.sink.add(ClientMessage.pause());
    }
  }

  Future<void> sendSeek(Duration position) async {
    final client = _client;
    if (client == null) return;
    client.sink.add(ClientMessage.seek(positionMs: position.inMilliseconds));
  }

  Future<void> exitRoom() async {
    _staleSessionTimer?.cancel();
    _staleSessionTimer = null;
    final client = _client;
    _client = null;
    syncplayRoom.value = '';
    syncplayClientRtt.value = 0;
    await client?.disconnect();
  }
}

extension on WatchTogetherClient {
  void sink add(Object message) {
    // WebSocket sink access is delegated by client in later refactor if needed.
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/player_syncplay_controller_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/pages/player/controller/player_syncplay_controller.dart test/player_syncplay_controller_test.dart
git commit -m "feat: rewire syncplay controller to watch-together client"
```

---

### Task 4: Convert UI to bottom drawer dialog

**Files:**
- Modify: `lib/pages/player/syncplay_sheet.dart`
- Test: `test/syncplay_sheet_dialog_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
void main() {
  testWidgets('shows bottom drawer dialog when opening sync play', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: Text('video')))));
    await showSyncPlaySheet(tester.element(find.text('video')), playerController: PlayerSyncPlayControllerFake(), changeEpisode: (_, {int? currentRoad, int? offset}) async {});
    await tester.pumpAndSettle();
    expect(find.text('一起看'), findsOneWidget);
    expect(find.text('服务器地址'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/syncplay_sheet_dialog_test.dart`
Expected: FAIL because `showSyncPlaySheet` still pushes a page route

- [ ] **Step 3: Write minimal implementation**

```dart
Future<void> showSyncPlaySheet(
  BuildContext context, {
  required PlayerSyncPlayController playerController,
  required Future<void> Function(int episode, {int? currentRoad, int? offset}) changeEpisode,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _SyncPlaySheetScaffold(
        title: '一起看',
        description: '与好友同步播放、暂停与进度',
        primaryAction: playerController.hasSession
            ? IconButton(onPressed: () async {
                await playerController.exitRoom();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }, icon: const Icon(Icons.link_off_rounded))
            : null,
        bodyBuilder: (context, compact) {
          final connected = playerController.syncplayRoom.isNotEmpty;
          final connecting = playerController.hasSession && !connected;
          if (connected) {
            return _buildConnected(context, theme);
          }
          if (connecting) {
            return _buildConnecting(context, theme);
          }
          return _buildLobby(context, theme, changeEpisode: changeEpisode);
        },
      );
    },
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/syncplay_sheet_dialog_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/pages/player/syncplay_sheet.dart test/syncplay_sheet_dialog_test.dart
git commit -m "feat: use bottom drawer dialog for watch together"
```

---

### Task 5: Update default backend and docs

**Files:**
- Modify: `lib/services/player/syncplay_endpoint.dart`
- Modify: `docs/api.md`
- Modify: `README.md`

- [ ] **Step 1: Update default endpoint**

```dart
const String defaultSyncPlayEndPoint = 'www.rusye.com:8998';

const officialSyncPlayEndPoints = <String>{
  defaultSyncPlayEndPoint,
};
```

- [ ] **Step 2: Update docs**

In `README.md` add:

```markdown
- [x] 一起看（后端同步播放）
```

In `docs/api.md` add a short client usage note pointing to the new dialog and default server.

- [ ] **Step 3: Commit**

```bash
git add lib/services/player/syncplay_endpoint.dart README.md docs/api.md
git commit -m "feat: set default watch-together backend to www.rusye.com:8998"
```

---

### Task 6: Verification

- [ ] **Step 1: Run unit tests**

Run: `dart test`
Expected: All watch-together tests pass

- [ ] **Step 2: Run Flutter analyzer**

Run: `flutter analyze`
Expected: No new watch-together related issues

- [ ] **Step 3: Commit verification**

```bash
git status --short
```

If `docs/smallest_player_item_panel.md` and deleted docs remain, leave them alone unless user asks.
