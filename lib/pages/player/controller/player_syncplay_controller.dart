import 'dart:async';
import 'package:flutter/foundation.dart';

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
    required this.setCurrentPosition,
    required this.changeEpisode,
    this.onSessionReady,
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
  final void Function({double? forceSyncPosition}) setCurrentPosition;
  final Future<void> Function(int episode, {int? currentRoad, int? offset})
      changeEpisode;

  final VoidCallback? onSessionReady;


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
  final RxString syncplayClientId = ''.obs;

  bool get hasSession => _client != null;

  bool get sessionReady =>
      syncplayRoom.value.isNotEmpty && syncplayClientId.value.isNotEmpty;

  void _trySyncCurrentState() {
    if (!(isHost && sessionReady)) {
      return;
    }
    if (duration().inMilliseconds <= 0) {
      return;
    }
    if (playing()) {
      sendPlay();
    } else {
      sendPause();
    }
    sendSeek(playerPosition().inMilliseconds);
  }

  bool get isHost =>
      syncplayHost.value.isNotEmpty &&
      syncplayHost.value == syncplayClientId.value;

  final RxString _currentFileName = ''.obs;
  Timer? _staleSessionTimer;
  WatchTogetherClient? _client;
  StreamSubscription<ServerMessage>? _messageSubscription;
  int _lastApplyPlayStateAt = 0;

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
    } on WatchTogetherException catch (e) {
      logger.e('一起看: $e', error: e);
      await client.disconnect();
      _client = null;
      syncplayRoom.value = '';
      syncplayClientRtt.value = 0;
      syncplayHost.value = '';
      SmartDialog.showToast('一起看: ${e.message}');
      rethrow;
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

  Future<void> joinRoom(String room, String username) async {
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
      await client.join();
      syncplayRoom.value = room;
      GStorage.setting.put(SettingBoxKey.syncPlayUserName, username);
    } on WatchTogetherException catch (e) {
      logger.e('一起看: $e', error: e);
      await client.disconnect();
      _client = null;
      syncplayRoom.value = '';
      syncplayClientRtt.value = 0;
      syncplayHost.value = '';
      SmartDialog.showToast('一起看: ${e.message}');
      rethrow;
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

  void sendPlay() {
    final client = _client;
    if (client == null) {
      throw const WatchTogetherException('session_not_connected');
    }
    logger.i('一起看: send play room=${syncplayRoom.value}');
    client.sendPlay();
  }

  void sendPause() {
    final client = _client;
    if (client == null) {
      throw const WatchTogetherException('session_not_connected');
    }
    logger.i('一起看: send pause room=${syncplayRoom.value}');
    client.sendPause();
  }

  void sendSeek(int positionMs) {
    final client = _client;
    if (client == null) {
      throw const WatchTogetherException('session_not_connected');
    }
    logger.i('一起看: send seek room=${syncplayRoom.value} positionMs=$positionMs');
    client.sendSeek(positionMs);
  }

  void sendHostTransfer(String to) {
    final client = _client;
    if (client == null) {
      throw const WatchTogetherException('session_not_connected');
    }
    logger.i('一起看: send host_transfer room=${syncplayRoom.value} to=$to');
    client.sendHostTransfer(to);
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
      syncplayClientId.value = message.you ?? '';
      _staleSessionTimer?.cancel();
      _staleSessionTimer = Timer(const Duration(minutes: 5), () {
        if (hasSession) {
          exitRoom();
          SmartDialog.showToast('一起看: 连接超时');
        }
      });
      _trySyncCurrentState();
      if (sessionReady) {
        onSessionReady?.call();
      }
    }
    if (message.type == 'host_changed') {
      syncplayHost.value = message.host ?? '';
      final isHostNow = syncplayHost.value.isNotEmpty
          && syncplayHost.value == syncplayClientId.value;
      if (isHostNow) {
        SmartDialog.showToast('一起看: 你已成为房主');
        _trySyncCurrentState();
      }
    }
    if (message.type == 'state') {
      final play = message.play;
      if (play != null) {
        logger.i(
          '一起看: recv state room=${syncplayRoom.value} status=${play.status.name} positionMs=${play.positionMs} updatedBy=${play.updatedBy ?? ''} updatedAtMs=${play.updatedAtMs ?? 0}',
        );
      }
      _applyPlayState(message);
    }
    if (message.type == 'error') {
      SmartDialog.showToast('一起看: ${message.errorMessage}');
    }
    if (!sessionReady && syncplayRoom.value.isNotEmpty) {
      logger.i('一起看: session not ready room=${syncplayRoom.value} clientId=${syncplayClientId.value}');
    }
  }

  void _applyPlayState(ServerMessage message) {
    final playSnapshot = message.play;
    if (playSnapshot == null) {
      return;
    }
    if (!sessionReady) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (isHost && now - _lastApplyPlayStateAt < 1500) {
      logger.i('一起看: ignore self state room=${syncplayRoom.value} pos=${playSnapshot.positionMs}');
      return;
    }
    logger.i(
      '一起看: apply state room=${syncplayRoom.value} host=${syncplayHost.value} me=${syncplayClientId.value} isHost=$isHost pos=${playSnapshot.positionMs} status=${playSnapshot.status.name}',
    );
    final remoteUpdatedAtMs = playSnapshot.updatedAtMs;
    final predictedMs = remoteUpdatedAtMs == null
        ? null
        : remoteUpdatedAtMs + syncplayClientRtt.value;
    final shouldPlay = playSnapshot.status == PlayStatus.playing;
    final remotePosition = playSnapshot.positionMs;
    final localPosition = playerPosition().inMilliseconds;
    Duration? target;
    if (predictedMs != null && playSnapshot.updatedBy == syncplayHost.value) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - predictedMs;
      final predictedPosition = remotePosition + elapsed;
      if ((predictedPosition - localPosition).abs() <= 1500) {
        return;
      }
      target = Duration(milliseconds: predictedPosition.clamp(0, predictedPosition));
    }
    target ??= Duration(milliseconds: remotePosition);
    final diff =
        (playerPosition().inMilliseconds - target.inMilliseconds).abs();
    final maxDrift = duration().inMilliseconds > 0
        ? (duration().inMilliseconds * 0.15).clamp(1000, 5000)
        : 1000;
    if (diff > maxDrift && duration().inMilliseconds > 0) {
      unawaited(seek(target, enableSync: false));
    } else if (shouldPlay != playing()) {
      if (shouldPlay) {
        play(enableSync: false);
      } else {
        unawaited(pause(enableSync: false));
      }
    }
    _lastApplyPlayStateAt = now;
    syncplayClientRtt.value = remoteUpdatedAtMs == null
        ? 0
        : (DateTime.now().millisecondsSinceEpoch - remoteUpdatedAtMs).abs();
  }
}
