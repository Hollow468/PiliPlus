import 'dart:async';

import 'package:get/get.dart';

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

  bool get hasSession => false;

  final RxString _currentFileName = ''.obs;
  Timer? _staleSessionTimer;

  @override
  Future<void> dispose() async {
    _staleSessionTimer?.cancel();
    _staleSessionTimer = null;
    syncplayRoom.value = '';
    syncplayClientRtt.value = 0;
    await Future<void>.value();
    super.dispose();
  }

  Future<void> createRoom(
    String room,
    String username,
  ) async {
    _currentFileName.value = "${bangumiId()}[${currentEpisode()}]";
    await Future<void>.value();
  }

  void setCurrentPosition({
    bool? forceSyncPlaying,
    double? forceSyncPosition,
  }) {
    // syncplay client removed
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
    _staleSessionTimer?.cancel();
    _staleSessionTimer = null;
    syncplayRoom.value = '';
    syncplayClientRtt.value = 0;
    await Future<void>.value();
  }
}
