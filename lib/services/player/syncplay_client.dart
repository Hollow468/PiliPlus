import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max, min;
import 'dart:typed_data';


class SyncplayException implements Exception {
  const SyncplayException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SyncplayConnectionException extends SyncplayException {
  const SyncplayConnectionException(super.message);
}

class SyncplayProtocolException extends SyncplayException {
  const SyncplayProtocolException(super.message);
}

abstract class SyncplayMessage {
  const SyncplayMessage();

  Map<String, dynamic> toJson();
}

class HelloMessage extends SyncplayMessage {
  const HelloMessage({
    required this.username,
    required this.version,
    required this.room,
  });

  final String username;
  final String version;
  final String room;

  @override
  Map<String, dynamic> toJson() => {
        'Hello': {
          'username': username,
          'room': {'name': room},
          'version': version,
          'features': {
            'sharedPlaylists': true,
            'chat': true,
            'featureList': true,
            'readiness': true,
            'managedRooms': false,
          },
        },
      };
}

class StateMessage extends SyncplayMessage {
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

  final double position;
  final bool paused;
  final String? setBy;
  final bool? doSeek;
  final int? clientAck;
  final int? serverAck;
  double clientLatencyCalculation;
  double? latencyCalculation;
  final double clientRtt;

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
            if (latencyCalculation != null) 'latencyCalculation': latencyCalculation,
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
  const SetMessage({
    this.duration,
    this.fileName,
    this.username,
    this.size,
    this.setBy,
    this.room,
    this.setJoined,
    this.setReady,
  });

  final double? duration;
  final String? fileName;
  final String? username;
  final int? size;
  final String? setBy;
  final String? room;
  final bool? setJoined;
  final bool? setReady;

  @override
  Map<String, dynamic> toJson() {
    if (setJoined == true && room != null && username != null) {
      return {
        'Set': {
          room: {
            'room': {'name': room},
            'event': {'joined': true},
          },
        },
      };
    }
    if (setReady == true) {
      return {
        'Set': {
          'ready': {'isReady': true, 'manuallyInitiated': false},
        },
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
          'user': {
            setBy ?? username ?? '': {
              'room': {'name': room},
            },
          },
      },
    };
  }
}

class ChatMessage extends SyncplayMessage {
  const ChatMessage({required this.message});

  final String message;

  @override
  Map<String, dynamic> toJson() => {'Chat': message};
}

class _TLSMessage extends SyncplayMessage {
  const _TLSMessage({required this.message});

  final String message;

  @override
  Map<String, dynamic> toJson() => {
        'TLS': {'startTLS': message},
      };
}

class SyncplayClient {
  SyncplayClient({required String host, required int port})
      : _host = host,
        _port = port;

  final String _host;
  final int _port;
  String get host => _host;
  int get port => _port;

  static const _protocolVersion = '1.7.0';
  static const _tlsHandshakeTimeout = Duration(seconds: 10);
  static const _lineBreak = '\r\n';
  static const _maxLineLength = 8192;
  static const _pingMovingAverageWeight = 0.85;

  bool _connectCalled = false;
  bool _closed = false;
  bool _isTLS = false;
  RawSocket? _socket;
  RawSocket? _transportSocket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  Completer<void>? _tlsHandshakeCompleter;
  final List<int> _pendingWrites = [];
  Completer<void>? _pendingWriteCompleter;
  Timer? _pendingWriteTimer;
  String? _username;
  String? _currentRoom;
  String? _currentFileName;
  double _currentPosition = 0.0;
  bool _isPaused = true;
  StreamController<Map<String, dynamic>>? _generalMessageController;
  StreamController<Map<String, dynamic>>? _roomMessageController;
  StreamController<Map<String, dynamic>>? _chatMessageController;
  StreamController<Map<String, dynamic>>? _fileChangedMessageController;
  StreamController<Map<String, dynamic>>? _positionChangedMessageController;
  double? _lastLatencyCalculation;
  double _clientRtt = 0.0;
  double _serverRtt = 0.0;
  double _averageRtt = 0.0;
  double _forwardDelay = 0.0;
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
    _fileChangedMessageController ??= StreamController.broadcast();
    return _fileChangedMessageController!.stream;
  }

  Stream<Map<String, dynamic>> get onPositionChangedMessage {
    _positionChangedMessageController ??= StreamController.broadcast();
    return _positionChangedMessageController!.stream;
  }

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
        throw const SyncplayConnectionException(
            'SyncPlay: connection closed during connect');
      }
      _socket = socket;
      _transportSocket = socket;
      _setupSocketHandlers(socket);

      if (enableTLS) {
        final handshakeCompleter = Completer<void>();
        _tlsHandshakeCompleter = handshakeCompleter;
        try {
          await Future.wait<void>(
            [_requestTLS(), handshakeCompleter.future],
            eagerError: true,
          ).timeout(_tlsHandshakeTimeout);
          if (_socket == null || !_isTLS) {
            throw const SyncplayConnectionException(
                'SyncPlay: TLS connection closed during upgrade');
          }
        } on TimeoutException {
          throw const SyncplayConnectionException(
              'SyncPlay: TLS connection upgrade timed out');
        } finally {
          _tlsHandshakeCompleter = null;
        }
      }
    } catch (error, stackTrace) {
      await _maybeCloseAfterConnectError(error, stackTrace);
      if (error is SyncplayException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (error is SocketException) {
        Error.throwWithStackTrace(
          SyncplayConnectionException('SyncPlay: connection failed: ${error.message}'),
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
      throw const SyncplayConnectionException(
          'SyncPlay: cannot request TLS before connecting');
    }
    await _sendMessage(const _TLSMessage(message: 'send'));
  }

  Future<void> joinRoom(String room, String username) async {
    await _sendMessage(HelloMessage(
      username: username,
      version: _protocolVersion,
      room: room,
    ));
  }

  Future<void> sendChatMessage(String message) async {
    if (_currentRoom == null || _username == null) {
      _addGeneralError(
        const SyncplayProtocolException(
            'SyncPlay: send chat message failed, not in a room'),
      );
      return Future<void>.value();
    }
    return _sendMessage(ChatMessage(message: message));
  }

  Future<void> setSyncPlayPlaying(
      String bangumiName, double duration, int size) async {
    if (_currentRoom == null || _username == null) {
      _addGeneralError(
        const SyncplayProtocolException(
            'SyncPlay: set playing bangumi failed, not in a room'),
      );
      return Future<void>.value();
    }
    return _sendMessage(SetMessage(
      duration: duration,
      fileName: bangumiName,
      size: size,
      setBy: _username,
      room: _currentRoom,
    ));
  }

  Future<void> sendSyncPlaySyncRequest({bool? doSeek}) {
    return _sendState(
      position: _currentPosition,
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
        const SyncplayConnectionException('SyncPlay: connection closed');
    _completeTlsHandshakeError(exception);
    await _closeSockets(pendingWriteError: exception);
    await _generalMessageController?.close();
    _generalMessageController = null;
    await _roomMessageController?.close();
    _roomMessageController = null;
    await _chatMessageController?.close();
    _chatMessageController = null;
    await _fileChangedMessageController?.close();
    _fileChangedMessageController = null;
    await _positionChangedMessageController?.close();
    _positionChangedMessageController = null;
    _currentRoom = null;
    _username = null;
    _currentFileName = null;
    _currentPosition = 0.0;
    _isPaused = true;
    _lastLatencyCalculation = null;
    _clientIgnoringOnTheFly = 0;
    _serverIgnoringOnTheFly = 0;
    _clientRtt = 0.0;
    _serverRtt = 0.0;
    _averageRtt = 0.0;
    _forwardDelay = 0.0;
  }

  void setPosition(double position) {
    _currentPosition = position;
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
          const SyncplayConnectionException('SyncPlay: connection closed'),
      stackTrace,
    );
    try {
      await subscription?.cancel();
    } catch (_) {}

    if (transportSocket != null) {
      await _forceCloseSocket(transportSocket);
    }
    if (socket != null &&
        !identical(socket, transportSocket) &&
        socket is! RawSecureSocket) {
      await _forceCloseSocket(socket);
    }
  }

  Future<void> _maybeCloseAfterConnectError(
      Object error, StackTrace stackTrace) async {
    if (!_closed) {
      await _closeSockets(pendingWriteError: error, stackTrace: stackTrace);
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

  void _setupSocketHandlers(RawSocket socket) {
    final buffer = Uint8List(_maxLineLength);
    var bufferOffset = 0;
    var partialLine = '';

    _socketSubscription =
        socket.listen((RawSocketEvent event) async {
      if (event != RawSocketEvent.read) {
        return;
      }
      final data = socket.read();
      if (data == null || data.isEmpty) {
        return;
      }

      int remaining = data.length;
      int dataOffset = 0;

      while (remaining > 0) {
        final space = _maxLineLength - bufferOffset;
        final copy = min(remaining, space);
        buffer.setRange(bufferOffset, bufferOffset + copy, data, dataOffset);
        bufferOffset += copy;
        remaining -= copy;
        dataOffset += copy;

        while (true) {
          if (partialLine.length >= _maxLineLength) {
            _addGeneralError(const SyncplayProtocolException(
                'SyncPlay: message exceeded max line length'));
            partialLine = '';
            bufferOffset = 0;
            break;
          }
          final newlineIndex = _indexOfLineBreak(buffer, bufferOffset);
          if (newlineIndex == -1) {
            partialLine = partialLine +
                const Utf8Decoder(allowMalformed: false).convert(
                    buffer.sublist(0, bufferOffset));
            bufferOffset = 0;
            break;
          }
          final lineUtf8 = Uint8List.view(buffer.buffer, 0, newlineIndex);
          final line = partialLine +
              const Utf8Decoder(allowMalformed: false).convert(lineUtf8);
          partialLine = '';
          bufferOffset -= newlineIndex + _lineBreak.length;
          if (bufferOffset > 0) {
            buffer.setRange(0, bufferOffset, buffer, newlineIndex + _lineBreak.length);
          }
          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            continue;
          }
          try {
            final decoded = jsonDecode(trimmed);
            _handleMessage(decoded as Map<String, dynamic>, socket);
          } on FormatException {
            _addGeneralError(const SyncplayProtocolException(
                'SyncPlay: failed to decode message'));
          } on TypeError {
            _addGeneralError(const SyncplayProtocolException(
                'SyncPlay: unexpected message format'));
          }
        }
      }
    }, onError: (Object error, StackTrace stackTrace) {
      if (!_closed) {
        _addGeneralError(SyncplayConnectionException(
            'SyncPlay: socket error: $error'));
      }
    }, onDone: () {
      if (!_closed) {
        _closed = true;
        _addGeneralError(
            const SyncplayConnectionException('SyncPlay: connection closed'));
        unawaited(_closeSockets());
      }
    });
  }

  int _indexOfLineBreak(Uint8List buffer, int length) {
    for (int i = 0; i < length - 1; i++) {
      if (buffer[i] == _lineBreak.codeUnitAt(0) &&
          buffer[i + 1] == _lineBreak.codeUnitAt(1)) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _sendMessage(SyncplayMessage message) async {
    final encoded = Uint8List.fromList(
        utf8.encode('${jsonEncode(message.toJson())}$_lineBreak'));
    await _writeAll(encoded);
  }

  Future<void> _writeAll(Uint8List data) async {
    if (_closed || _socket == null) {
      throw const SyncplayConnectionException('SyncPlay: connection closed');
    }
    final completer = Completer<void>();
    _pendingWriteCompleter = completer;
    _pendingWrites.addAll(data);
    _pendingWriteTimer?.cancel();
    _pendingWriteTimer =
        Timer(const Duration(milliseconds: 1500), () {
      if (!completer.isCompleted) {
        _flushPendingWrites();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
    _flushPendingWrites();
    return completer.future;
  }

  void _flushPendingWrites() {
    final socket = _socket;
    if (socket == null || _pendingWrites.isEmpty) {
      return;
    }
    final written = socket.write(_pendingWrites);
    if (written > 0) {
      _pendingWrites.removeRange(0, written);
    }
    if (_pendingWrites.isEmpty) {
      _pendingWriteTimer?.cancel();
      _pendingWriteTimer = null;
      final completer = _pendingWriteCompleter;
      if (completer != null && !completer.isCompleted) {
        _pendingWriteCompleter = null;
        completer.complete();
      }
    }
  }

  void _handleMessage(dynamic data, RawSocket sourceSocket) {
    final json = data as Map<String, dynamic>;
    if (json.containsKey('TLS')) {
      final tlsData = json['TLS'];
      if (tlsData is! Map || !tlsData.containsKey('startTLS')) {
        _completeTlsHandshakeError(const SyncplayProtocolException(
            'SyncPlay: invalid TLS response'));
      } else if (tlsData['startTLS'] == 'true') {
        unawaited(_upgradeToTls(sourceSocket));
      } else {
        _completeTlsHandshakeError(const SyncplayConnectionException(
            'SyncPlay: server rejected TLS connection upgrade'));
      }
      return;
    }
    if (json.containsKey('Hello')) {
      if (json['Hello'].containsKey('room') &&
          json['Hello']['room'].containsKey('name')) {
        _username = json['Hello']['username'];
        _currentRoom = json['Hello']['room']['name'];
        unawaited(_setReady());
      }
      _addGeneralEvent({
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
        _updateClientRttAndForwardDelay(
            json['State']['ping']['clientLatencyCalculation'], _serverRtt);
      }
      if (json['State'].containsKey('ignoringOnTheFly')) {
        final ignoringOnTheFly = json['State']['ignoringOnTheFly'];
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
        _currentPosition = (json['State']['playstate']['paused'] ?? true)
            ? (json['State']['playstate']['position']?.toDouble() ?? 0.0)
            : ((json['State']['playstate']['position']?.toDouble() ?? 0.0) +
                _forwardDelay);
        _isPaused = json['State']['playstate']['paused'] ?? true;
        _positionChangedMessageController?.add({
          'calculatedPositon': (json['State']['playstate']['paused'] ?? true)
              ? (json['State']['playstate']['position']?.toDouble() ?? 0.0)
              : ((json['State']['playstate']['position']?.toDouble() ?? 0.0) +
                  _forwardDelay),
          'position': json['State']['playstate']['position']?.toDouble() ?? 0.0,
          'paused': json['State']['playstate']['paused'] ?? true,
          'doSeek': json['State']['playstate']['doSeek'] ?? false,
          'setBy': json['State']['playstate']['setBy'] ?? '',
          'clientRtt': _clientRtt,
          'serverRtt': _serverRtt,
          'avrRtt': _averageRtt,
          'fd': _forwardDelay,
        });
      }
      unawaited(_sendState(
        position: _currentPosition,
        paused: _isPaused,
      ));
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
        final userMap = json['Set']['user'] as Map<String, dynamic>;
        for (final entry in userMap.entries) {
          final details = entry.value;
          if (details is! Map || !details.containsKey('event')) {
            continue;
          }
          final event = (details['event'].keys.first ?? 'unknown').toString();
          _roomMessageController?.add({
            'type': event,
            'username': entry.key,
          });
        }
        for (final entry in userMap.entries) {
          final userData = entry.value;
          if (userData is Map && userData.containsKey('file')) {
            final fileData = userData['file'] as Map<String, dynamic>;
            final fileName = fileData['name'];
            _currentFileName = fileName;
            _fileChangedMessageController?.add({
              'name': fileName,
              'setBy': entry.key,
            });
          }
        }
      }
      return;
    }
    if (json.containsKey('Chat')) {
      final chat = json['Chat'] as Map<String, dynamic>;
      if (chat.containsKey('message') && chat.containsKey('username')) {
        _chatMessageController?.add({
          'message': chat['message'],
          'username': chat['username'],
        });
      }
      return;
    }
    _addGeneralError(const SyncplayProtocolException(
        'SyncPlay: unknown message type'));
  }

  Future<void> _upgradeToTls(RawSocket sourceSocket) async {
    try {
      final secureSocket = await RawSecureSocket.secure(
        sourceSocket,
        onBadCertificate: (_) => true,
      );
      if (_closed) {
        await secureSocket.close();
        return;
      }
      _transportSocket = secureSocket;
      _socket = secureSocket;
      _isTLS = true;
      _setupSocketHandlers(secureSocket);
      _completeTlsHandshake(null);
    } on Object catch (error, stackTrace) {
      _completeTlsHandshakeError(SyncplayConnectionException(
          'SyncPlay: TLS upgrade failed: $error'));
    }
  }

  Future<void> _setReady() => _sendMessage(
      const SetMessage(setReady: true, username: '', room: ''));

  Future<void> _sendState({
    required double position,
    required bool paused,
    bool? doSeek,
    bool stateChange = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final latencyCalculation = stateChange ? now : null;
    return _sendMessage(StateMessage(
      position: position,
      paused: paused,
      doSeek: doSeek,
      clientAck: stateChange ? _clientIgnoringOnTheFly + 1 : null,
      serverAck: stateChange ? _serverIgnoringOnTheFly : null,
      clientLatencyCalculation: now,
      latencyCalculation: latencyCalculation,
      clientRtt: latencyCalculation ?? 0.0,
    ));
  }

  void _updateClientRttAndForwardDelay(
      double? timestamp, double senderRtt) {
    if (timestamp == null || senderRtt < 0) {
      return;
    }
    final newClientRtt =
        DateTime.now().millisecondsSinceEpoch / 1000.0 - timestamp;
    if (newClientRtt < 0) {
      return;
    }
    _clientRtt = newClientRtt;
    _averageRtt = _averageRtt == 0.0
        ? _clientRtt
        : _pingMovingAverageWeight * _averageRtt +
            (1 - _pingMovingAverageWeight) * _clientRtt;
    _forwardDelay = senderRtt < _clientRtt
        ? _averageRtt / 2 + (_clientRtt - senderRtt)
        : _averageRtt / 2;
  }

  void _addGeneralEvent(Map<String, dynamic> event) {
    _generalMessageController?.add(event);
  }

  void _addGeneralError(Object error) {
    _generalMessageController?.addError(error);
  }

  void _completeTlsHandshake(Object? result) {
    final completer = _tlsHandshakeCompleter;
    if (completer != null && !completer.isCompleted) {
      _tlsHandshakeCompleter = null;
      completer.complete(result);
    }
  }

  void _completeTlsHandshakeError(Object error) {
    final completer = _tlsHandshakeCompleter;
    if (completer != null && !completer.isCompleted) {
      _tlsHandshakeCompleter = null;
      completer.completeError(error);
    }
  }

  void _failPendingWrites(Object error, StackTrace? stackTrace) {
    final pending = Uint8List.fromList(_pendingWrites);
    _pendingWrites.clear();
    _pendingWriteTimer?.cancel();
    _pendingWriteTimer = null;
    final completer = _pendingWriteCompleter;
    if (completer != null && !completer.isCompleted) {
      _pendingWriteCompleter = null;
      completer.completeError(error, stackTrace ?? StackTrace.current);
    }
  }
}
