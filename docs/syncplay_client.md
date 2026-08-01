# SyncplayClient 相关实现说明

> 提取范围：`lib/services/player/syncplay_client.dart`、`lib/services/player/syncplay_endpoint.dart`、`test/syncplay_endpoint_test.dart`
>
> 备注：`SyncplayClient` 协议设计遵循 [SyncPlay Protocol](https://syncplay.pl/about/protocol/)。

## 1. 职责总览

`SyncplayClient` 是一个“单次连接”的 SyncPlay 协议客户端，只负责：

- 建立 TCP/TLS 长连接
- 发送 `Hello`、`Set`、`State`、`Chat`
- 解析服务端消息并分发给业务层关心的流：
  - `onGeneralMessage`
  - `onRoomMessage`
  - `onChatMessage`
  - `onFileChangedMessage`
  - `onPositionChangedMessage`

它不保存房间号到磁盘，也不决定 UI 行为；连接状态和用户名属于临时内存状态。

## 2. 核心类型

```dart
// lib/services/player/syncplay_client.dart
class SyncplayException implements Exception {
  final String message;
  SyncplayException(this.message);

  @override
  String toString() => message;
}

class SyncplayConnectionException extends SyncplayException {
  SyncplayConnectionException(super.message);
}

class SyncplayProtocolException extends SyncplayException {
  SyncplayProtocolException(super.message);
}

abstract class SyncplayMessage {
  Map<String, dynamic> toJson();
}

class HelloMessage extends SyncplayMessage {
  final String username;
  final String version;
  final String room;

  HelloMessage({
    required this.username,
    required this.version,
    required this.room,
  });

  @override
  Map<String, dynamic> toJson() => {
        'Hello': {
          'username': username,
          'room': {
            'name': room,
          },
          'version': version,
          'features': {
            'sharedPlaylists': true,
            'chat': true,
            'featureList': true,
            'readiness': true,
            'managedRooms': false,
          }
        },
      };
}

class StateMessage extends SyncplayMessage {
  final double position;
  final bool paused;
  final bool? doSeek;
  final String? setBy;

  // Syncplay control message.
  final int? clientAck;
  final int? serverAck;

  // latency calculation
  double clientLatencyCalculation;
  double? latencyCalculation;
  final double clientRtt;

  StateMessage({
    required this.position,
    required this.paused,
    this.setBy,
    this.doSeek,
    this.clientAck,
    this.serverAck,
    required this.clientLatencyCalculation,
    this.latencyCalculation,
    this.clientRtt = 0.0,
  });

  @override
  Map<String, dynamic> toJson() => {
        'State': {
          if (clientAck != null || serverAck != null)
            'ignoringOnTheFly': {
              if (clientAck != null) 'client': clientAck,
              if (serverAck != null) 'server': serverAck,
            },
          'ping': {
            'clientRtt': clientRtt,
            'clientLatencyCalculation': clientLatencyCalculation,
            if (latencyCalculation != null)
              'latencyCalculation': latencyCalculation,
          },
          'playstate': {
            'position': position,
            'paused': paused,
            if (setBy != null) 'setBy': setBy,
            'doSeek': doSeek,
          },
        },
      };
}

class SetMessage extends SyncplayMessage {
  final double? duration;
  final String? fileName;
  final String? username;
  final int? size;
  final String? setBy;
  final String? room;
  final bool? setJoined;
  final bool? setReady;

  SetMessage({
    this.duration,
    this.fileName,
    this.username,
    this.size,
    this.setBy,
    this.room,
    this.setJoined,
    this.setReady,
  });

  @override
  Map<String, dynamic> toJson() {
    if (setJoined != null && room != null && username != null) {
      return {
        "Set": {
          room: {
            "room": {"name": room},
            "event": {"joined": true}
          },
        }
      };
    }
    if (setReady != null) {
      return {
        'Set': {
          "ready": {"isReady": true, "manuallyInitiated": false}
        }
      };
    }
    return {
      'Set': {
        if (fileName != null)
          'file': {
            'duration': duration,
            'name': fileName,
            'size': size,
          },
        if (room != null)
          "user": {
            setBy: {
              "room": {"name": room},
            },
          },
      },
    };
  }
}

class ChatMessage extends SyncplayMessage {
  final String message;

  ChatMessage({
    required this.message,
  });

  @override
  Map<String, dynamic> toJson() => {'Chat': message};
}

class _TLSMessage extends SyncplayMessage {
  final String message;

  _TLSMessage({
    required this.message,
  });

  @override
  Map<String, dynamic> toJson() => {
        'TLS': {
          'startTLS': message,
        },
      };
}
```

## 3. 连接生命周期

```dart
// lib/services/player/syncplay_client.dart
class SyncplayClient {
  final String _host;
  final int _port;
  bool _connectCalled = false;
  bool _closed = false;
  bool _isTLS = false;
  RawSocket? _socket;
  // Retained across STARTTLS so a stalled RawSecureSocket can be force-closed.
  RawSocket? _transportSocket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  Completer<void>? _tlsHandshakeCompleter;
  final List<int> _pendingWrites = [];
  Completer<void>? _pendingWriteCompleter;
  Timer? _pendingWriteTimer;
  String? _username;
  String? _currentRoom;
  String? _currentFileName;
  double _currentPositon = 0.0;
  bool _isPaused = true;
  StreamController<Map<String, dynamic>>? _generalMessageController =
      StreamController.broadcast();
  StreamController<Map<String, dynamic>>? _roomMessageController =
      StreamController.broadcast();
  StreamController<Map<String, dynamic>>? _chatMessageController =
      StreamController.broadcast();
  StreamController<Map<String, dynamic>>? _flieChangedMessageController =
      StreamController.broadcast();
  StreamController<Map<String, dynamic>>? _positionChangedMessageController =
      StreamController.broadcast();
  double? _lastLatencyCalculation;

  // Network status
  double _clientRtt = 0.0;
  double _serverRtt = 0.0;
  double _avrRtt = 0.0;
  double _fd = 0.0;

  // IgnoringOnTheFly
  int _clientIgnoringOnTheFly = 0;
  int _serverIgnoringOnTheFly = 0;

  bool get isConnected =>
      !_closed && _socket != null && (_tlsHandshakeCompleter == null || _isTLS);
  String? get username => _username;
  String? get currentFileName => _currentFileName;

  Stream<Map<String, dynamic>> get onGeneralMessage {
    _generalMessageController ??= StreamController.broadcast();
    return _generalMessageController!.stream;
  }

  Stream<Map<String, dynamic>> get onRoomMessage {
    _roomMessageController ??= StreamController.broadcast();
    return _roomMessageController!.stream;
  }

  Stream<Map<String, dynamic>> get onChatMessage {
    _chatMessageController ??= StreamController.broadcast();
    return _chatMessageController!.stream;
  }


  Stream<Map<String, dynamic>> get onFileChangedMessage {
    _flieChangedMessageController ??= StreamController.broadcast();
    return _flieChangedMessageController!.stream;
  }

  Stream<Map<String, dynamic>> get onPositionChangedMessage {
    _positionChangedMessageController ??= StreamController.broadcast();
    return _positionChangedMessageController!.stream;
  }

  SyncplayClient({required String host, required int port})
      : _host = host,
        _port = port;

  /// Opens the connection using the TLS policy selected by the caller.
  Future<void> connect({required bool enableTLS}) async {
    if (_closed) {
      throw StateError('SyncplayClient cannot connect after disconnect');
    }
    if (_connectCalled) {
      throw StateError('SyncplayClient.connect may only be called once');
    }
    _connectCalled = true;
    try {
      final socket = await RawSocket.connect(_host, _port);
      if (_closed) {
        await _forceCloseSocket(socket);
        throw SyncplayConnectionException('SyncPlay: connection closed');
      }
      _socket = socket;
      _transportSocket = socket;
      _setupSocketHandlers(socket);
      if (enableTLS) {
        final handshakeCompleter = Completer<void>();
        _tlsHandshakeCompleter = handshakeCompleter;
        try {
          await Future.wait<void>(
            [
              _requestTLS(),
              handshakeCompleter.future,
            ],
            eagerError: true,
          ).timeout(_tlsHandshakeTimeout);
          if (_socket == null || !_isTLS) {
            throw SyncplayConnectionException(
              'SyncPlay: TLS connection closed during upgrade',
            );
          }
        } on TimeoutException {
          throw SyncplayConnectionException(
            'SyncPlay: TLS connection upgrade timed out',
          );
        } finally {
          _tlsHandshakeCompleter = null;
        }
      }
    } catch (error, stackTrace) {
      if (!_closed) {
        await _closeSockets(
          pendingWriteError: error,
          stackTrace: stackTrace,
        );
      }
      if (error is SyncplayException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (error is SocketException) {
        Error.throwWithStackTrace(
          SyncplayConnectionException(
            'SyncPlay: connection failed: ${error.message}',
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(
        SyncplayConnectionException('SyncPlay: connection failed: $error'),
        stackTrace,
      );
    }
  }

  Future<void> _requestTLS() async {
    if (_socket == null) {
      throw SyncplayConnectionException(
        'SyncPlay: cannot request TLS before connecting',
      );
    }
    await _sendMessage(_TLSMessage(message: 'send'));
  }

  Future<void> joinRoom(String room, String username) async {
    await _sendMessage(HelloMessage(
      username: username,
      version: '1.7.0',
      room: room,
    ));
  }

  Future<void> sendChatMessage(String message) async {
    if (_currentRoom == null || _username == null) {
      _generalMessageController?.addError(
        SyncplayProtocolException(
            'SyncPlay: send chat message failed, not in a room'),
      );
      return;
    }
    await _sendMessage(ChatMessage(
      message: message,
    ));
  }

  Future<void> setSyncPlayPlaying(
      String bangumiName, double duration, int size) async {
    if (_currentRoom == null || _username == null) {
      _generalMessageController?.addError(
        SyncplayProtocolException(
            'SyncPlay: set playing bangumi failed, not in a room'),
      );
      return;
    }
    await _sendMessage(SetMessage(
        duration: duration,
        fileName: bangumiName,
        size: size,
        setBy: _username ?? '',
        room: _currentRoom ?? ''));
  }

  Future<void> sendSyncPlaySyncRequest({bool? doSeek}) {
    return _sendState(
      position: _currentPositon,
      paused: _isPaused,
      doSeek: doSeek,
      stateChange: true,
    );
  }

  Future<void> disconnect() async {
    if (_closed) {
      return;
    }
    _closed = true;
    final exception =
        SyncplayConnectionException('SyncPlay: connection closed');
    _completeTLSHandshakeError(exception);
    await _closeSockets(pendingWriteError: exception);
    await _generalMessageController?.close();
    _generalMessageController = null;
    await _roomMessageController?.close();
    _roomMessageController = null;
    await _chatMessageController?.close();
    _chatMessageController = null;
    await _flieChangedMessageController?.close();
    _flieChangedMessageController = null;
    await _positionChangedMessageController?.close();
    _positionChangedMessageController = null;
    _currentRoom = null;
    _username = null;
    _currentFileName = null;
    _currentPositon = 0.0;
    _isPaused = true;
    _lastLatencyCalculation = null;
    _clientIgnoringOnTheFly = 0;
    _serverIgnoringOnTheFly = 0;
    _clientRtt = 0.0;
    _serverRtt = 0.0;
    _avrRtt = 0.0;
    _fd = 0.0;
  }

  void setPosition(double position) {
    _currentPositon = position;
  }

  void setPaused(bool paused) {
    _isPaused = paused;
  }

  Future<void> _closeSockets({
    Object? pendingWriteError,
    StackTrace? stackTrace,
  }) async {
    final socket = _socket;
    final transportSocket = _transportSocket;
    final subscription = _socketSubscription;
    _socket = null;
    _transportSocket = null;
    _socketSubscription = null;
    _isTLS = false;
    _failPendingWrites(
      pendingWriteError ??
          SyncplayConnectionException('SyncPlay: connection closed'),
      stackTrace,
    );
    try {
      await subscription?.cancel();
    } catch (_) {}

    // RawSecureSocket.close() can wait for buffered TLS writes indefinitely.
    // Closing its retained transport is the force-close path in that case.
    if (transportSocket != null) {
      await _forceCloseSocket(transportSocket);
    }
    if (socket != null &&
        !identical(socket, transportSocket) &&
        socket is! RawSecureSocket) {
      await _forceCloseSocket(socket);
    }
  }

  Future<void> _forceCloseSocket(RawSocket socket) async {
    try {
      socket.shutdown(SocketDirection.both);
    } catch (_) {}
    try {
      await socket.close();
    } catch (_) {}
  }
}
```

## 4. 消息解析与状态同步

```dart
// lib/services/player/syncplay_client.dart
void _handleMessage(dynamic data, RawSocket sourceSocket) {
  final json = data as Map<String, dynamic>;
  if (json.containsKey('TLS')) {
    final tlsData = json['TLS'];
    if (tlsData is! Map || !tlsData.containsKey('startTLS')) {
      _completeTLSHandshakeError(
        SyncplayProtocolException('SyncPlay: invalid TLS response'),
      );
    } else if (tlsData['startTLS'] == 'true') {
      unawaited(_upgradeToTLS(sourceSocket));
    } else {
      _completeTLSHandshakeError(
        SyncplayConnectionException('SyncPlay: server rejected TLS connection upgrade'),
      );
    }
    return;
  }
  if (json.containsKey('Hello')) {
    if (json['Hello'].containsKey('room') &&
        json['Hello']['room'].containsKey('name')) {
      _username = json['Hello']['username'];
      _currentRoom = json['Hello']['room']['name'];
      _runInBackground(_setReady());
    }
    _generalMessageController?.add({
      'username': json['Hello']['username'],
      'room': json['Hello']['room']['name'],
    });
    return;
  }
  if (json.containsKey('State')) {
    if (json['State'].containsKey('ping')) {
      _lastLatencyCalculation =
          json['State']['ping']['latencyCalculation']?.toDouble();
      if (json['State']['ping'].containsKey('serverRtt')) {
        _serverRtt = json['State']['ping']['serverRtt']?.toDouble() ?? 0.0;
      }
      _updateClientRttAndFd(
          json['State']["ping"]["clientLatencyCalculation"], _serverRtt);
    }
    if (json['State'].containsKey('ignoringOnTheFly')) {
      var ignoringOnTheFly = json['State']['ignoringOnTheFly'];
      if (ignoringOnTheFly.containsKey('server')) {
        _serverIgnoringOnTheFly = ignoringOnTheFly['server'];
        _clientIgnoringOnTheFly = 0;
      } else if (ignoringOnTheFly.containsKey('client')) {
        if (ignoringOnTheFly['client'] == _clientIgnoringOnTheFly) {
          _clientIgnoringOnTheFly = 0;
        }
      }
    }
    if (_clientIgnoringOnTheFly == 0) {
      _currentPositon = (json['State']['playstate']['paused'] ?? true)
          ? (json['State']['playstate']['position']?.toDouble() ?? 0.0)
          : ((json['State']['playstate']['position']?.toDouble() ?? 0.0) +
              _fd);
      _isPaused = json['State']['playstate']['paused'] ?? true;
      _positionChangedMessageController?.add({
        'calculatedPositon': (json['State']['playstate']['paused'] ?? true)
            ? (json['State']['playstate']['position']?.toDouble() ?? 0.0)
            : ((json['State']['playstate']['position']?.toDouble() ?? 0.0) +
                _fd),
        'position': json['State']['playstate']['position']?.toDouble() ?? 0.0,
        'paused': json['State']['playstate']['paused'] ?? true,
        'doSeek': json['State']['playstate']['doSeek'] ?? false,
        'setBy': json['State']['playstate']['setBy'] ?? '',
        'clientRtt': _clientRtt,
        'serverRtt': _serverRtt,
        'avrRtt': _avrRtt,
        'fd': _fd,
      });
    }
    _runInBackground(
      _sendState(
        position: _currentPositon,
        paused: _isPaused,
      ),
    );
    return;
  }
  if (json.containsKey('Set')) {
    if (json['Set'].containsKey('playlistIndex')) {
      _roomMessageController?.add({
        'type': 'init',
        'username': json['Set']['playlistIndex']['user'] ?? '',
      });
      return;
    }
    if (json['Set'].containsKey('user')) {
      Map<String, dynamic> userMap = data['Set']['user'];
      userMap.forEach((username, details) {
        if (!details.containsKey('event')) {
          return;
        }
        var event = details['event'].keys.first ?? 'unknown';
        _roomMessageController?.add({
          'type': event,
          'username': username,
        });
      });
      for (var username in userMap.keys) {
        var userData = userMap[username];
        if (userData is Map && userData.containsKey('file')) {
          var fileData = userData['file'];
          var fileName = fileData['name'];
          _currentFileName = fileName;
          _flieChangedMessageController?.add({
            'name': fileName,
            'setBy': username,
          });
        }
      }
    }
    return;
  }
  if (json.containsKey('Chat')) {
    if (json['Chat'].containsKey('message') &&
        json['Chat'].containsKey('username')) {
      _chatMessageController?.add({
        'message': json['Chat']['message'],
        'username': json['Chat']['username'],
      });
    }
    return;
  }
  _generalMessageController?.addError(
    SyncplayProtocolException('SyncPlay: unknown message type'),
  );
}
```

## 5. 延迟/前向补偿

```dart
// lib/services/player/syncplay_client.dart
const double _pingMovingAverageWeight = 0.85;

void _updateClientRttAndFd(double? timestamp, double senderRtt) {
  if (timestamp == null) return;

  // Calculate RTT: current time minus the passed timestamp
  double newClientRtt =
      DateTime.now().millisecondsSinceEpoch / 1000.0 - timestamp;

  // If the new RTT is less than 0, it means the server is not responding
  if (newClientRtt < 0 || senderRtt < 0) return;
  _clientRtt = newClientRtt;

  // If it's the first time calculating, initialize the average RTT
  if (_avrRtt == 0) {
    _avrRtt = _clientRtt;
  }

  // Use moving average to update RTT, smooth the delay data
  _avrRtt = _avrRtt * _pingMovingAverageWeight +
      _clientRtt * (1 - _pingMovingAverageWeight);

  // Calculate the forward delay based on the sender's RTT
  if (senderRtt < _clientRtt) {
    _fd = _avrRtt / 2 + (_clientRtt - senderRtt);
  } else {
    _fd = _avrRtt / 2;
  }
}
```

## 6. 服务器地址持久化

```dart
// lib/services/player/syncplay_endpoint.dart
const String defaultSyncPlayEndPoint = 'syncplay.pl:8996';

/// Official public endpoints that must use STARTTLS.
const Set<String> officialSyncPlayEndPoints = {
  'syncplay.pl:8995',
  defaultSyncPlayEndPoint,
  'syncplay.pl:8997',
  'syncplay.pl:8998',
  'syncplay.pl:8999',
};

class SyncPlayEndPoint {
  final String host;
  final int port;

  const SyncPlayEndPoint({required this.host, required this.port});
}

SyncPlayEndPoint? parseSyncPlayEndPoint(String endPoint) {
  final input = endPoint.trim();
  if (input.isEmpty) {
    return null;
  }

  String host = '';
  String portStr = '';

  if (input.startsWith('[')) {
    final closeIndex = input.indexOf(']');
    if (closeIndex == -1) {
      return null;
    }
    host = input.substring(1, closeIndex);
    final rest = input.substring(closeIndex + 1);
    if (!rest.startsWith(':')) {
      return null;
    }
    portStr = rest.substring(1);
  } else {
    final lastColonIndex = input.lastIndexOf(':');
    if (lastColonIndex == -1) {
      return null;
    }
    host = input.substring(0, lastColonIndex);
    portStr = input.substring(lastColonIndex + 1);
  }

  host = host.trim();
  portStr = portStr.trim();
  if (host.isEmpty || portStr.isEmpty) {
    return null;
  }

  final port = int.tryParse(portStr);
  if (port == null || port <= 0 || port > 65535) {
    return null;
  }

  return SyncPlayEndPoint(host: host, port: port);
}

bool isOfficialSyncPlayEndPoint(SyncPlayEndPoint endPoint) {
  final normalizedEndPoint = '${endPoint.host.toLowerCase()}:${endPoint.port}';
  return officialSyncPlayEndPoints.contains(normalizedEndPoint);
}
```

```dart
// lib/services/storage/settings_keys.dart
static const syncPlayEndPoint = SettingKey<String>(
  _SettingBoxKey.syncPlayEndPoint,
  defaultSyncPlayEndPoint,
  group: SettingGroup.player,
);
static const syncPlayUserName = SettingKey<String>(
  'syncPlayUserName',
  '',
  group: SettingGroup.player,
);
```

## 7. 相关单测

```dart
// test/syncplay_endpoint_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/syncplay_endpoint.dart';
import 'package:kazumi/services/storage/settings_keys.dart';

void main() {
  test('uses an official server as the default endpoint', () {
    expect(SettingsKeys.syncPlayEndPoint.defaultValue, defaultSyncPlayEndPoint);
    expect(officialSyncPlayEndPoints, contains(defaultSyncPlayEndPoint));
  });

  group('isOfficialSyncPlayEndPoint', () {
    test('recognizes every built-in official server', () {
      for (final endPoint in officialSyncPlayEndPoints) {
        expect(
          isOfficialSyncPlayEndPoint(parseSyncPlayEndPoint(endPoint)!),
          isTrue,
        );
      }
    });

    test('normalizes host casing and surrounding whitespace', () {
      expect(
        isOfficialSyncPlayEndPoint(
          parseSyncPlayEndPoint('  SYNCPLAY.PL:8996  ')!,
        ),
        isTrue,
      );
    });

    test('rejects custom hosts and ports', () {
      for (final endPoint in [
        'syncplay.example.com:8996',
        'syncplay.pl:9000',
        'localhost:8996',
      ]) {
        expect(
          isOfficialSyncPlayEndPoint(parseSyncPlayEndPoint(endPoint)!),
          isFalse,
        );
      }
    });
  });

  test('parseSyncPlayEndPoint rejects invalid endpoints', () {
    expect(parseSyncPlayEndPoint('syncplay.pl'), isNull);
    expect(parseSyncPlayEndPoint(''), isNull);
  });
}
```

## 8. 关键判断

- 连接创建后只能调用一次 `connect`；重新连接要重建 `SyncplayClient`。
- 官方 SyncPlay 服务器会走 STARTTLS；自定义服务器不使用 TLS。
- 房间号/用户名只在内存里，关闭连接不会自动恢复。
- 服务端消息通过多个 `StreamController` 分发，业务侧按事件类型监听。
- 发送前会先发 `SetMessage(setReady)`，协议版本固定为 `1.7.0`。
