import 'dart:async';

import 'package:PiliPlus/services/player/syncplay_client.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/services/player/syncplay_endpoint.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class SyncPlayChatMessage {
  const SyncPlayChatMessage({
    required this.username,
    required this.message,
    required this.fromRemote,
  });

  final String username;
  final String message;
  final bool fromRemote;
}

class AsyncSession {
  AsyncSession(this._owner);

  final AsyncSessionOwner _owner;
  bool _cancelled = false;

  bool get isActive => !_cancelled && _owner._activeSession == this;

  void cancel() {
    _cancelled = true;
  }
}

class AsyncSessionOwner {
  AsyncSession? _activeSession;
  bool _closed = false;

  bool get isClosed => _closed;

  AsyncSession begin() {
    if (_closed) {
      return AsyncSession(this)..cancel();
    }
    _activeSession?.cancel();
    final session = AsyncSession(this);
    _activeSession = session;
    return session;
  }

  void cancel() {
    _activeSession?.cancel();
  }

  void close() {
    _closed = true;
    _activeSession?.cancel();
  }
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
  final Future<void> Function(int episode, {int? currentRoad, int? offset})
      changeEpisode;

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

  final Rx<SyncplayClient?> syncplayController = Rxn<SyncplayClient>();
  final AsyncSessionOwner _connectionSessions = AsyncSessionOwner();
  final RxString syncplayRoom = ''.obs;
  final RxInt syncplayClientRtt = 0.obs;

  bool get hasSession => syncplayController.value != null;

  final RxString _currentFileName = ''.obs;
  final RxBool _syncplayPlaying = false.obs;
  Timer? _staleSessionTimer;

  final StreamController<SyncPlayChatMessage> _chatStreamController =
      StreamController<SyncPlayChatMessage>.broadcast();

  Stream<SyncPlayChatMessage> get chatStream => _chatStreamController.stream;

  void emitChatMessage({
    required String username,
    required String message,
    required bool fromRemote,
  }) {
    if (_chatStreamController.isClosed) {
      return;
    }
    _chatStreamController.add(SyncPlayChatMessage(
      username: username,
      message: message,
      fromRemote: fromRemote,
    ));
  }

  Future<void> createRoom(
    String room,
    String username,
  ) async {
    if (_connectionSessions.isClosed) {
      return;
    }
    final session = _connectionSessions.begin();
    final previousClient = syncplayController.value;
    syncplayController.value = null;
    syncplayRoom.value = '';
    syncplayClientRtt.value = 0;
    await previousClient?.disconnect();
    if (session._cancelled) {
      return;
    }
    final String endPoint =
        GStorage.setting.get(SettingBoxKey.syncPlayEndPoint,
                defaultValue: defaultSyncPlayEndPoint) ??
            defaultSyncPlayEndPoint;
    logger.i('SyncPlay: connecting to $endPoint');
    final parsed = parseSyncPlayEndPoint(endPoint);
    if (parsed == null) {
      SmartDialog.showToast('SyncPlay: 服务器地址不合法 $endPoint');
      logger.e('SyncPlay: invalid server address $endPoint');
      return;
    }
    final enableTLS = isOfficialSyncPlayEndPoint(parsed);
    final client = SyncplayClient(host: parsed.host, port: parsed.port);
    syncplayController.value = client;
    _currentFileName.value = "${bangumiId()}[${currentEpisode()}]";
    try {
      await client.connect(enableTLS: enableTLS);
      if (!_isCurrentConnection(session, client)) {
        await client.disconnect();
        return;
      }
      _staleSessionTimer?.cancel();
      _staleSessionTimer = Timer(const Duration(minutes: 5), () {
        if (identical(syncplayController.value, client)) {
          exitRoom();
          SmartDialog.showToast('SyncPlay: 连接超时，请重新加入');
        }
      });
      client.onGeneralMessage.listen(
        null,
        onError: (error) {
          if (!_isCurrentConnection(session, client)) {
            return;
          }
          final message = error is SyncplayException
              ? error.message
              : error.toString();
          logger.e('SyncPlay: error $message', error: error);
          if (error is SyncplayConnectionException) {
            _staleSessionTimer?.cancel();
            _staleSessionTimer = null;
            exitRoom();
            SmartDialog.showToast('SyncPlay: 同步中断 $message');
          }
        },
      );
      client.onRoomMessage.listen((message) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        if (message['type'] == 'init') {
          if ((message['username'] ?? '') == '') {
            SmartDialog.showToast('SyncPlay: 您是当前房间中的唯一用户');
            unawaited(setPlayingBangumi(forceSyncPlaying: true));
          } else {
            SmartDialog.showToast(
                'SyncPlay: 您不是当前房间中的唯一用户, 当前以用户 ${message['username']} 进度为准');
          }
        }
        if (message['type'] == 'left') {
          SmartDialog.showToast('SyncPlay: ${message['username']} 离开了房间');
        }
        if (message['type'] == 'joined') {
          SmartDialog.showToast('SyncPlay: ${message['username']} 加入了房间');
        }
      });
      client.onFileChangedMessage.listen((message) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        logger.i(
            'SyncPlay: file changed by ${message['setBy']}: ${message['name']}');
        final match =
            RegExp(r'(\d+)\[(\d+)\]').firstMatch(message['name'] ?? '');
        if (match == null) {
          return;
        }
        final bangumiID = int.tryParse(match.group(1) ?? '0') ?? 0;
        final episode = int.tryParse(match.group(2) ?? '0') ?? 0;
        if (bangumiID == 0 || episode == 0 || episode == currentEpisode()) {
          return;
        }
        SmartDialog.showToast(
            'SyncPlay: ${message['setBy'] ?? 'unknown'} 切换到第 $episode 话');
        _currentFileName.value = "${bangumiID}[$episode]";
        unawaited(changeEpisode(episode, currentRoad: currentRoad()));
      });
      client.onChatMessage.listen((message) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        final sender = (message['username'] ?? '').toString();
        final text = (message['message'] ?? '').toString();
        emitChatMessage(
          username: sender,
          message: text,
          fromRemote: sender != client.username,
        );
      }, onError: (error) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        final message = error is SyncplayException
            ? error.message
            : error.toString();
        logger.e('SyncPlay: error $message', error: error);
      });
      client.onPositionChangedMessage.listen((message) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        syncplayClientRtt.value =
            (message['clientRtt'].toDouble() * 1000).toInt();
        final paused = message['paused'] as bool;
        final position =
            Duration(milliseconds: (message['calculatedPositon'].toDouble() * 1000).toInt());
        if (paused != !playing()) {
          if (paused) {
            if (position != Duration.zero) {
              SmartDialog.showToast('SyncPlay: ${message['setBy'] ?? 'unknown'} 暂停了播放');
              unawaited(pause(enableSync: false));
            }
          } else {
            if (position != Duration.zero) {
              SmartDialog.showToast('SyncPlay: ${message['setBy'] ?? 'unknown'} 开始了播放');
              unawaited(play(enableSync: false));
            }
          }
        }
        final doSeek = message['doSeek'] as bool;
        if ((doSeek ||
                (playerPosition().inMilliseconds -
                            position.inMilliseconds)
                        .abs() >
                    1000) &&
            duration().inMilliseconds > 0) {
          unawaited(seek(position, enableSync: false));
        }
      });
      await client.joinRoom(room, username);
      if (!_isCurrentConnection(session, client)) {
        await client.disconnect();
        return;
      }
      syncplayRoom.value = room;
      GStorage.setting.put(SettingBoxKey.syncPlayUserName, username);
    } catch (e) {
      logger.e('SyncPlay: error $e', error: e);
      if (!_isCurrentConnection(session, client)) {
        await client.disconnect();
        return;
      }
      _staleSessionTimer?.cancel();
      _staleSessionTimer = null;
      syncplayController.value = null;
      syncplayRoom.value = '';
      syncplayClientRtt.value = 0;
      await client.disconnect();
      final message = e is SyncplayException ? e.message : e.toString();
      SmartDialog.showToast('SyncPlay: 连接失败 $message');
    }
  }

  void setCurrentPosition({
    bool? forceSyncPlaying,
    double? forceSyncPosition,
  }) {
    final client = syncplayController.value;
    if (client == null) {
      return;
    }
    forceSyncPlaying ??= playing();
    client.setPaused(!forceSyncPlaying);
    client.setPosition(forceSyncPosition ??
        (((currentPosition().inMilliseconds - playerPosition().inMilliseconds)
                    .abs() >
                2000)
            ? currentPosition().inMilliseconds.toDouble() / 1000
            : playerPosition().inMilliseconds.toDouble() / 1000));
  }

  Future<void> setPlayingBangumi({
    bool? forceSyncPlaying,
    double? forceSyncPosition,
  }) async {
    final client = syncplayController.value;
    if (client == null) {
      return;
    }
    await _runBestEffortSync(() async {
      await client.setSyncPlayPlaying(
          _currentFileName.value, 10800, 220514438);
      if (!identical(syncplayController.value, client)) {
        return;
      }
      setCurrentPosition(
          forceSyncPlaying: forceSyncPlaying,
          forceSyncPosition: forceSyncPosition);
      await client.sendSyncPlaySyncRequest(doSeek: null);
    });
  }

  Future<void> requestSync({bool? doSeek}) async {
    final client = syncplayController.value;
    if (client == null) {
      return;
    }
    await _runBestEffortSync(
        () => client.sendSyncPlaySyncRequest(doSeek: doSeek));
  }

  Future<void> sendChatMessage(String message) async {
    final client = syncplayController.value;
    if (client == null) {
      return;
    }
    await _runBestEffortSync(() => client.sendChatMessage(message));
  }

  Future<void> _runBestEffortSync(Future<void> Function() operation) async {
    try {
      await operation();
    } on SyncplayConnectionException {
      // Socket handlers report active connection failures.
    }
  }

  Future<void> exitRoom() async {
    _connectionSessions.cancel();
    _staleSessionTimer?.cancel();
    _staleSessionTimer = null;
    final controller = syncplayController.value;
    syncplayController.value = null;
    syncplayRoom.value = '';
    syncplayClientRtt.value = 0;
    if (controller == null) {
      return;
    }
    await controller.disconnect();
  }

  @override
  Future<void> dispose() async {
    _staleSessionTimer?.cancel();
    _staleSessionTimer = null;
    _connectionSessions.close();
    await exitRoom();
    await _chatStreamController.close();
    super.dispose();
  }

  bool _isCurrentConnection(AsyncSession session, SyncplayClient client) {
    return !session._cancelled &&
        _connectionSessions._activeSession == session &&
        identical(syncplayController.value, client);
  }
}
