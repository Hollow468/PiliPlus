# 一起看功能：生命周期、状态切换与持久化

> 主要提取：`lib/pages/player/controller/player_syncplay_controller.dart`、`lib/pages/player/syncplay_sheet.dart`、`lib/pages/player/player_controller.dart`、`lib/pages/video/video_page.dart`、`lib/services/storage/settings_keys.dart`

## 1. 整体生命周期

一起看功能的生命周期主要分成这几个阶段：

1. 用户在播放器菜单中打开一起看入口
2. 进入 SyncPlay sheet，选择“创建房间/加入房间/同步服务器”
3. `PlayerSyncPlayController.createRoom()` 建立连接并加入房间
4. 连接成功后，播放器与房间内其他成员同步播放状态、文件切换、聊天消息
5. 用户主动断开连接，或页面销毁时清理 session 和 socket

## 2. 入口 UI 与进入路径

```dart
// lib/pages/player/player_item.dart
void showSyncPlayPanel() {
  showSyncPlaySheet(
    context,
    playerController: playerController,
    changeEpisode: widget.changeEpisode,
  );
}
```

小播放器面板和完整播放器面板都提供了“一起看”菜单入口：

```dart
// lib/pages/player/smallest_player_item_panel.dart
MenuItemButton(
  onPressed: () {
    widget.showSyncPlayPanel();
  },
  child: Container(
    height: 48,
    constraints: BoxConstraints(minWidth: 112),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text("一起看"),
    ),
  ),
),
```

```dart
// lib/pages/player/player_item_panel.dart
MenuItemButton(
  onPressed: () {
    widget.showSyncPlayPanel();
  },
  child: Container(
    height: 48,
    constraints: BoxConstraints(minWidth: 112),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text("一起看"),
    ),
  ),
),
```

## 3. SyncPlay sheet 状态流转

```dart
// lib/pages/player/syncplay_sheet.dart
enum _SyncPlayDestination { create, join, server }

Future<void> showSyncPlaySheet(
  BuildContext context, {
  required PlayerController playerController,
  required Future<void> Function(int episode, {int currentRoad, int offset})
      changeEpisode,
}) async {
  final _SyncPlayDestination? destination =
      await _showStep<_SyncPlayDestination>(
    context,
    (context) => _SyncPlayHomeSheet(playerController: playerController),
  );
  if (destination == null || !context.mounted) {
    return;
  }
  await _showStep<void>(
    context,
    (context) => switch (destination) {
      _SyncPlayDestination.create ||
      _SyncPlayDestination.join =>
        _SyncPlayRoomSheet(
          isCreate: destination == _SyncPlayDestination.create,
          playerController: playerController,
          changeEpisode: changeEpisode,
        ),
      _SyncPlayDestination.server => const _SyncPlayServerSheet(),
    },
  );
}
```

主状态只有三种：

- `hasSession == false && room.isEmpty`：大厅页，可以创建/加入房间或修改服务器
- `hasSession == true && room.isEmpty`：正在连接中
- `hasSession == true && room.isNotEmpty`：已连接，显示房间号和延迟

```dart
// lib/pages/player/syncplay_sheet.dart
Observer(builder: (context) {
  final bool hasSession = playerController.syncplay.hasSession;
  final String room = playerController.syncplay.syncplayRoom;
  final int rtt = playerController.syncplay.syncplayClientRtt;
  final bool connected = room.isNotEmpty;
  final bool connecting = hasSession && !connected;

  return _SyncPlaySheetScaffold(
    title: '一起看',
    description: '与好友同步播放、暂停与选集',
    primaryAction: hasSession
        ? FilledButton.tonalIcon(
            onPressed: () async {
              await playerController.exitSyncPlayRoom();
            },
            ...
            label: Text(connecting ? '取消连接' : '断开连接'),
          )
        : null,
    bodyBuilder: (context, compact) {
      if (connected) {
        return _buildConnected(context, room: room, rtt: rtt);
      }
      if (connecting) {
        return _buildConnecting(context);
      }
      return _buildLobby(context, compact: compact);
    },
  );
});
```

## 4. 创建/加入房间实现

```dart
// lib/pages/player/syncplay_sheet.dart
class _SyncPlayRoomSheetState extends State<_SyncPlayRoomSheet> {
  static final Random _random = Random();
  static String _generateRoomNumber() =>
      List.generate(8, (_) => _random.nextInt(10)).join();
  static String _generateUserName() {
    const String consonants = 'bcdfghjklmnpqrstvwxyz';
    const String vowels = 'aeiou';
    final int syllables = 3 + _random.nextInt(2);
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < syllables; i++) {
      buffer.write(consonants[_random.nextInt(consonants.length)]);
      buffer.write(vowels[_random.nextInt(vowels.length)]);
    }
    final String name = buffer.toString();
    return name[0].toUpperCase() + name.substring(1);
  }

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  late String _createdRoom = _generateRoomNumber();

  @override
  void initState() {
    super.initState();
    _usernameController.text =
        GStorage.getSetting<String>(SettingsKeys.syncPlayUserName);
    if (_usernameController.text.isEmpty) {
      _usernameController.text = _generateUserName();
    }
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final String username = _usernameController.text.trim();
    final String room =
        widget.isCreate ? _createdRoom : _roomController.text.trim();
    GStorage.putSetting<String>(SettingsKeys.syncPlayUserName, username);
    Navigator.of(context).pop();
    widget.playerController
        .createSyncPlayRoom(room, username, widget.changeEpisode);
  }
}
```

房间号与用户名校验：

```dart
// lib/pages/player/syncplay_sheet.dart
Widget _buildRoomField() {
  return TextFormField(
    controller: _roomController,
    autofocus: true,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.next,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    autovalidateMode: AutovalidateMode.onUserInteraction,
    decoration: _sheetInputDecoration(
      context,
      labelText: '房间号',
      hintText: '6-10 位数字',
      icon: Icons.meeting_room_outlined,
    ),
    validator: (value) {
      final String text = (value ?? '').trim();
      if (text.isEmpty) {
        return '请输入房间号';
      }
      if (!RegExp(r'^[0-9]{6,10}$').hasMatch(text)) {
        return '房间号为 6-10 位数字';
      }
      return null;
    },
  );
}

Widget _buildUsernameField({bool compact = false}) {
  return TextFormField(
    controller: _usernameController,
    textInputAction: TextInputAction.done,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    decoration: _sheetInputDecoration(
      context,
      labelText: '昵称',
      icon: Icons.person_outline_rounded,
      helperText: compact ? null : '4-12 位英文字母，房间内可见',
    ),
    validator: (value) {
      final String text = (value ?? '').trim();
      if (text.isEmpty) {
        return '请输入昵称';
      }
      if (!RegExp(r'^[a-zA-Z]{4,12}$').hasMatch(text)) {
        return '昵称为 4-12 位英文字母';
      }
      return null;
    },
    onFieldSubmitted: (_) => _submit(),
  );
}
```

## 5. 控制器里的状态与连接管理

```dart
// lib/pages/player/controller/player_syncplay_controller.dart
abstract class _PlayerSyncPlayController with Store {
  _PlayerSyncPlayController({
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

  @observable
  SyncplayClient? syncplayController;
  final AsyncSessionOwner _connectionSessions = AsyncSessionOwner();
  @observable
  String syncplayRoom = '';
  @observable
  int syncplayClientRtt = 0;

  bool get hasSession => syncplayController != null;

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
}
```

连接与监听：

```dart
// lib/pages/player/controller/player_syncplay_controller.dart
Future<void> createRoom(
    String room,
    String username,
    Future<void> Function(int episode, {int currentRoad, int offset})
        changeEpisode) async {
  if (_connectionSessions.isClosed) {
    return;
  }
  final session = _connectionSessions.begin();
  final previousClient = syncplayController;
  syncplayController = null;
  syncplayRoom = '';
  syncplayClientRtt = 0;
  await previousClient?.disconnect();
  if (session.isStale) {
    return;
  }
  final String syncPlayEndPoint =
      GStorage.getSetting(SettingsKeys.syncPlayEndPoint);
  KazumiLogger().i('SyncPlay: connecting to $syncPlayEndPoint');
  final parsed = parseSyncPlayEndPoint(syncPlayEndPoint);
  if (parsed == null) {
    KazumiDialog.showToast(
      message: 'SyncPlay: 服务器地址不合法 $syncPlayEndPoint',
    );
    KazumiLogger().e('SyncPlay: invalid server address $syncPlayEndPoint');
    return;
  }
  final enableTLS = isOfficialSyncPlayEndPoint(parsed);
  final client = SyncplayClient(host: parsed.host, port: parsed.port);
  syncplayController = client;
  try {
    await client.connect(enableTLS: enableTLS);
    if (!_isCurrentConnection(session, client)) {
      await client.disconnect();
      return;
    }
    client.onGeneralMessage.listen(
      null,
      onError: (error) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        final message =
            error is SyncplayException ? error.message : error.toString();
        KazumiLogger().e('SyncPlay: error $message', error: error);
        if (error is SyncplayConnectionException) {
          exitRoom();
          KazumiDialog.showToast(
            message: 'SyncPlay: 同步中断 $message',
            duration: const Duration(seconds: 5),
            showActionButton: true,
            actionLabel: '重新连接',
            onActionPressed: () => createRoom(room, username, changeEpisode),
          );
        }
      },
    );
    client.onRoomMessage.listen(
      (message) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        if (message['type'] == 'init') {
          if (message['username'] == '') {
            KazumiDialog.showToast(
                message: 'SyncPlay: 您是当前房间中的唯一用户',
                duration: const Duration(seconds: 5));
            setPlayingBangumi();
          } else {
            KazumiDialog.showToast(
                message:
                    'SyncPlay: 您不是当前房间中的唯一用户, 当前以用户 ${message['username']} 进度为准');
          }
        }
        if (message['type'] == 'left') {
          KazumiDialog.showToast(
              message: 'SyncPlay: ${message['username']} 离开了房间',
              duration: const Duration(seconds: 5));
        }
        if (message['type'] == 'joined') {
          KazumiDialog.showToast(
              message: 'SyncPlay: ${message['username']} 加入了房间',
              duration: const Duration(seconds: 5));
        }
      },
    );
    client.onFileChangedMessage.listen(
      (message) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        KazumiLogger().i(
            'SyncPlay: file changed by ${message['setBy']}: ${message['name']}');
        RegExp regExp = RegExp(r'(\d+)\[(\d+)\]');
        Match? match = regExp.firstMatch(message['name']);
        if (match != null) {
          int bangumiID = int.tryParse(match.group(1) ?? '0') ?? 0;
          int episode = int.tryParse(match.group(2) ?? '0') ?? 0;
          if (bangumiID != 0 && episode != 0 && episode != currentEpisode()) {
            KazumiDialog.showToast(
                message:
                    'SyncPlay: ${message['setBy'] ?? 'unknown'} 切换到第 $episode 话',
                duration: const Duration(seconds: 3));
            changeEpisode(episode, currentRoad: currentRoad());
          }
        }
      },
    );
    client.onChatMessage.listen(
      (message) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        final String sender = (message['username'] ?? '').toString();
        final String text = (message['message'] ?? '').toString();
        final bool fromRemote = message['username'] != username;

        emitChatMessage(
          username: sender,
          message: text,
          fromRemote: fromRemote,
        );
      },
      onError: (error) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        final message =
            error is SyncplayException ? error.message : error.toString();
        KazumiLogger().e('SyncPlay: error $message', error: error);
      },
    );
    client.onPositionChangedMessage.listen(
      (message) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        syncplayClientRtt = (message['clientRtt'].toDouble() * 1000).toInt();
        if (message['paused'] != !playing()) {
          if (message['paused']) {
            if (message['position'] != 0) {
              KazumiDialog.showToast(
                  message: 'SyncPlay: ${message['setBy'] ?? 'unknown'} 暂停了播放',
                  duration: const Duration(seconds: 3));
              pause(enableSync: false);
            }
          } else {
            if (message['position'] != 0) {
              KazumiDialog.showToast(
                  message: 'SyncPlay: ${message['setBy'] ?? 'unknown'} 开始了播放',
                  duration: const Duration(seconds: 3));
              play(enableSync: false);
            }
          }
        }
        if ((((playerPosition().inMilliseconds -
                            (message['calculatedPositon'].toDouble() * 1000)
                                .toInt())
                        .abs() >
                    1000) ||
                message['doSeek']) &&
            duration().inMilliseconds > 0) {
          seek(
              Duration(
                  milliseconds:
                      (message['calculatedPositon'].toDouble() * 1000)
                          .toInt()),
              enableSync: false);
        }
      },
    );
    await client.joinRoom(room, username);
    if (!_isCurrentConnection(session, client)) {
      await client.disconnect();
      return;
    }
    syncplayRoom = room;
  } catch (e) {
    KazumiLogger().e('SyncPlay: error', error: e);
    if (!_isCurrentConnection(session, client)) {
      await client.disconnect();
      return;
    }
    syncplayController = null;
    syncplayRoom = '';
    syncplayClientRtt = 0;
    await client.disconnect();
    final message = e is SyncplayException ? e.message : e.toString();
    KazumiDialog.showToast(
      message: 'SyncPlay: 连接失败 $message',
      duration: const Duration(seconds: 5),
    );
  }
}

bool _isCurrentConnection(AsyncSession session, SyncplayClient client) {
  return session.isActive && identical(syncplayController, client);
}
```

位置同步与发送播放信息：

```dart
// lib/pages/player/controller/player_syncplay_controller.dart
void setCurrentPosition({bool? forceSyncPlaying, double? forceSyncPosition}) {
  if (syncplayController == null) {
    return;
  }
  forceSyncPlaying ??= playing();
  syncplayController!.setPaused(!forceSyncPlaying);
  syncplayController!.setPosition((forceSyncPosition ??
      (((currentPosition().inMilliseconds - playerPosition().inMilliseconds)
                  .abs() >
              2000)
          ? currentPosition().inMilliseconds.toDouble() / 1000
          : playerPosition().inMilliseconds.toDouble() / 1000)));
}

Future<void> setPlayingBangumi(
    {bool? forceSyncPlaying, double? forceSyncPosition}) async {
  final client = syncplayController;
  if (client == null) {
    return;
  }
  await _runBestEffortSync(() async {
    await client.setSyncPlayPlaying(
        "${bangumiId()}[${currentEpisode()}]", 10800, 220514438);
    if (!identical(syncplayController, client)) {
      return;
    }
    setCurrentPosition(
        forceSyncPlaying: forceSyncPlaying,
        forceSyncPosition: forceSyncPosition);
    await client.sendSyncPlaySyncRequest(doSeek: null);
  });
}

Future<void> requestSync({bool? doSeek}) async {
  final client = syncplayController;
  if (client == null) {
    return;
  }
  await _runBestEffortSync(
      () => client.sendSyncPlaySyncRequest(doSeek: doSeek));
}

Future<void> sendChatMessage(String message) async {
  final client = syncplayController;
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

@action
Future<void> exitRoom() async {
  _connectionSessions.cancel();
  final controller = syncplayController;
  syncplayController = null;
  syncplayRoom = '';
  syncplayClientRtt = 0;
  if (controller == null) {
    return;
  }
  await controller.disconnect();
}

Future<void> dispose() async {
  _connectionSessions.close();
  await exitRoom();
  await _chatStreamController.close();
}
```

## 6. 播放器与 SyncPlay 的联动

```dart
// lib/pages/player/player_controller.dart
late final PlayerSyncPlayController syncplay = PlayerSyncPlayController(
  ...
);

Future<void> _initializePlayback() async {
  ...
  if (syncplay.syncplayController?.isConnected ?? false) {
    if (syncplay.syncplayController!.currentFileName !=
        "$bangumiId[$currentEpisode]") {
      setSyncPlayPlayingBangumi(
          forceSyncPlaying: true, forceSyncPosition: 0.0);
    }
  }
  return true;
}
```

播放控制会主动同步到一起看：

```dart
// lib/pages/player/player_controller.dart
Future<void> _onSeekCompleted(bool enableSync) async {
  if (syncplay.hasSession) {
    setSyncPlayCurrentPosition();
    if (enableSync) {
      await requestSyncPlaySync(doSeek: true);
    }
  }
}

Future<void> pause({bool enableSync = true}) async {
  final player = playback.mediaPlayer;
  if (player == null) return;
  danmaku.canvasController.pause();
  try {
    await player.pause();
  } catch (_) {
    return;
  }
  playback.playing = false;
  if (syncplay.hasSession) {
    setSyncPlayCurrentPosition();
    if (enableSync) {
      await requestSyncPlaySync();
    }
  }
}

Future<void> play({bool enableSync = true}) async {
  final player = playback.mediaPlayer;
  if (player == null) return;
  danmaku.canvasController.resume();
  try {
    await player.play();
  } catch (_) {
    return;
  }
  playback.playing = true;
  if (syncplay.hasSession) {
    setSyncPlayCurrentPosition();
    if (enableSync) {
      await requestSyncPlaySync();
    }
  }
}
```

页面销毁时一起看也会同步退出：

```dart
// lib/pages/player/player_controller.dart
Future<void> _shutdownResources() async {
  await Future.wait([
    _releasePlaybackResources(),
    syncplay.dispose(),
  ]);
}
```

## 7. 聊天与弹幕联动

```dart
// lib/pages/video/video_page.dart
_syncChatSubscription =
    playerController.syncplay.chatStream.listen((event) {
  final localUsername =
      playerController.syncplay.syncplayController?.username ?? '';
  final String displayText = '${event.username}：${event.message}';

  if (playerController.danmaku.danmakuOn &&
      event.username != localUsername &&
      event.fromRemote) {
    playerController.danmaku.canvasController.addDanmaku(
      DanmakuContentItem(
        displayText,
        color: Colors.orange,
        isColorful: true,
        type: DanmakuItemType.bottom,
        extra: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
});
```

发送弹幕时，若目标为聊天室，会先校验是否已加入一起看：

```dart
// lib/pages/video/video_page.dart
if (destination == DanmakuDestination.chatRoom) {
  if (playerController.syncplay.syncplayRoom.isEmpty) {
    KazumiDialog.showToast(message: '你还没有加入一起看，无法发送聊天室弹幕');
    return false;
  }

  final sender =
      playerController.syncplay.syncplayController?.username ?? '我';
  final String displayText = '$sender：$msg';

  playerController.danmaku.canvasController.addDanmaku(
    DanmakuContentItem(
      displayText,
      color: Colors.orange,
      isColorful: true,
      type: DanmakuItemType.bottom,
      extra: DateTime.now().millisecondsSinceEpoch,
    ),
  );

  unawaited(playerController.sendSyncPlayChatMessage(msg));
}
```

## 8. 持久化情况

一起看的持久化非常有限，当前只有配置类字段会落盘：

- `SettingsKeys.syncPlayEndPoint`：SyncPlay 服务器地址
- `SettingsKeys.syncPlayUserName`：SyncPlay 昵称

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

状态切换与生命周期相关的重要点：

- `syncplayController`、`syncplayRoom`、`syncplayClientRtt` 都是内存状态，不会自动恢复。
- `createRoom` 会先断开旧连接，再新建 `SyncplayClient`。
- `AsyncSession` 用于避免旧连接回调污染新连接状态。
- 连接异常会弹出“重新连接”；用户关闭 sheet 也会断开连接。
- 房间号、RTT、用户名均不会保存在当前页面路由之外；关闭播放页后再进入需要重新加入房间。
