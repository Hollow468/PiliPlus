enum PlayStatus { playing, paused }

class PlaySnapshot {
  const PlaySnapshot({
    required this.status,
    required this.positionMs,
    this.updatedBy,
    this.updatedAtMs,
  });

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
  const ServerMessage._({
    required this.type,
    this.room,
    this.you,
    this.host,
    this.peers,
    this.play,
    this.peer,
    this.nick,
    this.reason,
    this.errorCode,
    this.errorMessage,
  });

  factory ServerMessage.init({
    required String room,
    required String you,
    required String host,
    required Map<String, String> peers,
    required PlaySnapshot play,
  }) {
    return ServerMessage._(
      type: 'init',
      room: room,
      you: you,
      host: host,
      peers: peers,
      play: play,
    );
  }

  factory ServerMessage.state({
    required PlaySnapshot play,
    Map<String, String>? peers,
    String? host,
  }) {
    return ServerMessage._(
      type: 'state',
      play: play,
      peers: peers,
      host: host,
    );
  }

  factory ServerMessage.peerJoined({
    required String peer,
    required String nick,
  }) {
    return ServerMessage._(
      type: 'peer_joined',
      peer: peer,
      nick: nick,
    );
  }

  factory ServerMessage.peerLeft({
    required String peer,
  }) {
    return ServerMessage._(
      type: 'peer_left',
      peer: peer,
    );
  }

  factory ServerMessage.hostChanged({
    required String host,
    String? reason,
  }) {
    return ServerMessage._(
      type: 'host_changed',
      host: host,
      reason: reason,
    );
  }

  factory ServerMessage.error({
    required String errorCode,
    required String errorMessage,
  }) {
    return ServerMessage._(
      type: 'error',
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  factory ServerMessage.parse(Map<String, dynamic> json) {
    final type = json['t'] as String;
    return switch (type) {
      'init' => ServerMessage.init(
          room: json['room'] as String,
          you: json['you'] as String,
          host: json['host'] as String,
          peers: Map<String, String>.from(json['peers'] as Map),
          play: PlaySnapshot.fromJson(Map<String, dynamic>.from(json['play'] as Map)),
        ),
      'state' => ServerMessage.state(
          play: PlaySnapshot.fromJson(Map<String, dynamic>.from(json['play'] as Map)),
          peers: json['peers'] != null
              ? Map<String, String>.from(json['peers'] as Map)
              : null,
          host: json['host'] as String?,
        ),
      'peer_joined' => ServerMessage.peerJoined(
          peer: json['peer'] as String,
          nick: json['nick'] as String,
        ),
      'peer_left' => ServerMessage.peerLeft(
          peer: json['peer'] as String,
        ),
      'host_changed' => ServerMessage.hostChanged(
          host: json['host'] as String,
          reason: json['reason'] as String?,
        ),
      'error' => ServerMessage.error(
          errorCode: json['code'] as String,
          errorMessage: json['msg'] as String,
        ),
      _ => throw FormatException('unknown message type $type'),
    };
  }

  final String type;
  final String? room;
  final String? you;
  final String? host;
  final Map<String, String>? peers;
  final PlaySnapshot? play;
  final String? peer;
  final String? nick;
  final String? reason;
  final String? errorCode;
  final String? errorMessage;
}

class ClientMessage {
  const ClientMessage._();

  static Map<String, dynamic> join({required String nick}) =>
      <String, dynamic>{'t': 'join', 'nick': nick};

  static Map<String, dynamic> leave() => const <String, dynamic>{'t': 'leave'};

  static Map<String, dynamic> play() => const <String, dynamic>{'t': 'play'};

  static Map<String, dynamic> pause() => const <String, dynamic>{'t': 'pause'};

  static Map<String, dynamic> seek({required int positionMs}) =>
      <String, dynamic>{'t': 'seek', 'pos': positionMs};
}
