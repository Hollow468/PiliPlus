import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/services/player/syncplay_endpoint.dart';
import 'package:PiliPlus/services/player/watch_together_message.dart';

class WatchTogetherClient {
  WatchTogetherClient._({
    required this.endPoint,
    required this.room,
    required this.username,
    required this.socketFactory,
    required this.httpClientFactory,
  });

  factory WatchTogetherClient({
    required SyncPlayEndPoint endPoint,
    required String room,
    required String username,
    Future<_WatchTogetherSocket> Function(Uri uri, String protocols)?
          socketFactory,
    HttpClient Function()? httpClientFactory,
  }) {
    return WatchTogetherClient._(
      endPoint: endPoint,
      room: room,
      username: username,
      socketFactory: socketFactory ?? _socketFromWebSocket,
      httpClientFactory: httpClientFactory ?? HttpClient.new,
    );
  }

  final SyncPlayEndPoint endPoint;
  final String room;
  final String username;
  final Future<_WatchTogetherSocket> Function(Uri uri, String protocols)
      socketFactory;
  final HttpClient Function() httpClientFactory;

  final StreamController<ServerMessage> _controller =
      StreamController<ServerMessage>.broadcast();
  Stream<ServerMessage> get messages => _controller.stream;
  bool get isConnected => _socket != null;

  _WatchTogetherSocket? _socket;
  HttpClientRequest? _roomRequest;
  Timer? _staleTimer;

  Future<void> connect() async {
    final client = httpClientFactory();
    final request = await client.postUrl(
      Uri.parse('http://${endPoint.host}:${endPoint.port}/rooms'),
    );
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(json.encode(<String, dynamic>{
      'room_id': room,
      'max_peers': null,
    })));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.conflict) {
      throw const WatchTogetherException('room_already_exists');
    }
    if (response.statusCode == HttpStatus.badRequest) {
      throw const WatchTogetherException('invalid_room_id');
    }
    if (response.statusCode != HttpStatus.created) {
      throw const WatchTogetherException('room_create_failed');
    }
    final roomId = _parseRoomId(body) ?? room;

    final uri = Uri.parse('ws://${endPoint.host}:${endPoint.port}/ws/$roomId');
    final socket = await socketFactory(uri, 'watch-together');
    _socket = socket;
    _staleTimer?.cancel();
    _staleTimer = Timer(const Duration(minutes: 5), () {
      if (isConnected) {
        unawaited(disconnect());
      }
    });

    socket.messages.listen(
      _controller.add,
      onDone: () {
        if (!_controller.isClosed) {
          _controller.close();
        }
      },
      cancelOnError: false,
    );

    logger.i('一起看: create room=$room ws=$uri send join nick=$username');
    socket.send(json.encode(ClientMessage.join(nick: username)));
  }

  Future<void> join() async {
    final uri = Uri.parse('ws://${endPoint.host}:${endPoint.port}/ws/$room');
    final socket = await socketFactory(uri, 'watch-together');
    _socket = socket;
    _staleTimer?.cancel();
    _staleTimer = Timer(const Duration(minutes: 5), () {
      if (isConnected) {
        unawaited(disconnect());
      }
    });

    socket.messages.listen(
      _controller.add,
      onDone: () {
        if (!_controller.isClosed) {
          _controller.close();
        }
      },
      cancelOnError: false,
    );

    logger.i('一起看: join room=$room ws=$uri send join nick=$username');
    socket.send(json.encode(ClientMessage.join(nick: username)));
  }

  Future<void> disconnect() async {
    _staleTimer?.cancel();
    _staleTimer = null;

    final socket = _socket;
    _socket = null;
    if (socket != null) {
      await _safeSend(socket, ClientMessage.leave());
      await socket.close();
    }

    await _roomRequest?.close();
    _roomRequest = null;
  }

  String? get roomId {
    if (_socket == null) {
      return null;
    }
    return _socket!.uri.path.split('/').lastWhere((segment) => segment.isNotEmpty, orElse: () => '');
  }

  void sendPlay() => _send(ClientMessage.play());
  void sendPause() => _send(ClientMessage.pause());
  void sendSeek(int positionMs) => _send(ClientMessage.seek(positionMs: positionMs));
  void sendHostTransfer(String to) => _send(ClientMessage.hostTransfer(to: to));

  void _send(Object message) {
    final socket = _socket;
    if (socket == null) {
      throw const WatchTogetherException('session_not_connected');
    }
    socket.send(json.encode(message));
  }

  String? _parseRoomId(String body) {
    try {
      final jsonBody = json.decode(body) as Map<String, dynamic>;
      return jsonBody['room_id'] as String?;
    } on FormatException catch (_) {
      return null;
    }
  }
}

Future<void> _safeSend(_WatchTogetherSocket socket, Map<String, dynamic> message) {
  try {
    return socket.send(json.encode(message));
  } on Exception catch (_) {
    return Future<void>.value();
  }
}

class WatchTogetherException implements Exception {
  const WatchTogetherException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class _WatchTogetherSocket {
  Stream<ServerMessage> get messages;
  Uri get uri;
  Future<void> send(Object message);
  Future<void> close();
}

Future<_WatchTogetherSocket> _socketFromWebSocket(
  Uri uri,
  String protocols,
) async {
  final webSocket = await WebSocket.connect(uri.toString(), protocols: [protocols]);
  return _WebSocketSocket(webSocket);
}

class _WebSocketSocket implements _WatchTogetherSocket {
  _WebSocketSocket(this.socket);

  final WebSocket socket;

  @override
  Stream<ServerMessage> get messages {
    return socket
        .map((event) {
          if (event is String) {
            return event;
          }
          if (event is List<int>) {
            return utf8.decode(event);
          }
          throw const WatchTogetherException('invalid_ws_message');
        })
        .map(json.decode)
        .cast<Map<String, dynamic>>()
        .map(ServerMessage.parse);
  }

  @override
  Uri get uri => Uri.parse(socket.toString());

  @override
  Future<void> send(Object message) {
    if (message is String) {
      socket.add(message);
    } else {
      socket.add(message as List<int>);
    }
    return Future<void>.value();
  }

  @override
  Future<void> close() => socket.close();
}
