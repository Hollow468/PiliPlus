import 'dart:async';

import 'package:PiliPlus/services/player/watch_together_client.dart';
import 'package:PiliPlus/services/player/watch_together_message.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/services/player/syncplay_endpoint.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

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

  final RxString syncplayRoom = ''.obs;
  final RxInt syncplayClientRtt = 0.obs;
  final RxString syncplayHost = ''.obs;

  bool get hasSession => _client != null;

  final RxString _currentFileName = ''.obs;
  Timer? _staleSessionTimer;
  WatchTogetherClient? _client;
  StreamSubscription<ServerMessage>? _messageSubscription;

  @override
  Future<void> dispose() async {
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    await exitRoom();
    super.dispose();
  }

  Future<void> createRoom(String room, String username) async {
    await exitRoom();
    final endPointString = GStorage.setting.get(
          SettingBoxKey.syncPlayEndPoint,
          defaultValue: defaultSyncPlayEndPoint,
        ) ??
        defaultSyncPlayEndPoint;
    final parsed = parseSyncPlayEndPoint(endPointString);
    if (parsed == null) {
      SmartDialog.showToast('一起看: 服务器地址不合法 $endPointString');
      return;
    }
    final client = WatchTogetherClient(
      endPoint: parsed,
      room: room,
      username: username,
    );
    _client = client;
    _currentFileName.value = "${bangumiId()}[${currentEpisode()}]";
    _staleSessionTimer?.cancel();
    _staleSessionTimer = Timer(const Duration(minutes: 5), () {
      if (identical(_client, client)) {
        exitRoom();
        SmartDialog.showToast('一起看: 连接超时');
      }
    });
    _messageSubscription?.cancel();
    _messageSubscription = client.messages.listen(
      (message) => _onMessage(message),
      onError: (Object error, StackTrace stackTrace) {
        logger.e('一起看: $error', error: error, stackTrace: stackTrace);
        SmartDialog.showToast('一起看: 连接异常');
        exitRoom();
      },
      onDone: () {
        if (identical(_client, client)) {
          exitRoom();
        }
      },
      cancelOnError: false,
    );
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
      syncplayHost.value = '';
      SmartDialog.showToast('一起看: 连接失败');
      rethrow;
    }
  }

  void setCurrentPosition({
    bool? forceSyncPlaying,
    double? forceSyncPosition,
  }) {
    // reserved for manual resync
  }

  Future<void> setPlayingBangumi({
    bool? forceSyncPlaying,
    double? forceSyncPosition,
  }) async {
    await Future<void>.value();
  }

  Future<void> requestSync({bool? doSeek}) async {
    await Future<void>.value();
  }

  Future<void> sendChatMessage(String message) async {
    await Future<void>.value();
  }

  Future<void> exitRoom() async {
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    _staleSessionTimer?.cancel();
    _staleSessionTimer = null;
    final client = _client;
    _client = null;
    syncplayRoom.value = '';
    syncplayClientRtt.value = 0;
    syncplayHost.value = '';
    await client?.disconnect();
  }

  void _onMessage(ServerMessage message) {
    final client = _client;
    if (client == null) {
      return;
    }
    if (message.type == 'init') {
      syncplayHost.value = message.host ?? '';
    }
    if (message.type == 'host_changed') {
      syncplayHost.value = message.host ?? '';
    }
    if (message.type == 'state') {
      _applyPlayState(message);
    }
    if (message.type == 'error') {
      SmartDialog.showToast('一起看: ${message.errorMessage}');
    }
  }

  void _applyPlayState(ServerMessage message) {
    final playSnapshot = message.play;
    if (playSnapshot == null) {
      return;
    }
    final shouldPlay = playSnapshot.status == PlayStatus.playing;
    final target = Duration(milliseconds: playSnapshot.positionMs);
    final diff =
        (playerPosition().inMilliseconds - target.inMilliseconds).abs();
    if (diff > 1000 && duration().inMilliseconds > 0) {
      unawaited(seek(target, enableSync: false));
    } else if (shouldPlay != playing()) {
      if (shouldPlay) {
        play(enableSync: false);
      } else {
        unawaited(pause(enableSync: false));
      }
    }
    syncplayClientRtt.value = playSnapshot.updatedAtMs == null
        ? 0
        : (DateTime.now().millisecondsSinceEpoch - playSnapshot.updatedAtMs!).abs();
  }
}
