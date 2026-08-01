# SmallestPlayerItemPanel 相关 UI 实现

> 提取范围：`lib/pages/player/smallest_player_item_panel.dart`、`lib/pages/player/player_item_panel.dart`、`lib/pages/player/player_panel_hold.dart`、`lib/pages/player/controller/player_panel_controller.dart`
>
> 说明：`SmallestPlayerItemPanel` 是播放器在“窄界面 / 画中画兼容模式”下使用的最小化控制面板，完整面板则使用 `PlayerItemPanel`。

## 1. 选择最小面板的入口

```dart
// lib/pages/player/player_item.dart
bool needFullPanel(BuildContext context) {
  // windows too small, workaround for ohos floating window
  ...
}
...
child: (needFullPanel(context))
    ? PlayerItemPanel(...)
    : SmallestPlayerItemPanel(
        playerController: playerController,
        videoPageController: videoPageController,
        onBackPressed: widget.onBackPressed,
        setPlaybackSpeed: setPlaybackSpeed,
        showDanmakuSwitch: showDanmakuSwitch,
        handleFullscreen: handleFullscreen,
        handleProgressBarDragStart: handleProgressBarDragStart,
        handleProgressBarSeek: handleProgressBarSeek,
        handleSuperResolutionChange: handleSuperResolutionChange,
        panelVisibilityController: _panelVisibilityController,
        acquirePlayerPanelHold: acquirePlayerPanelHold,
        onMenuVisibilityChanged: _handlePlayerMenuVisibilityChanged,
        handleDanmaku: handleDanmaku,
        showVideoInfo: showVideoInfo,
        showSyncPlayPanel: showSyncPlayPanel,
        pauseForTimedShutdown: widget.pauseForTimedShutdown,
        disableAnimations: widget.disableAnimations,
        skipOP: skipOP,
      ),
```

## 2. 面板可传入的接口

```dart
// lib/pages/player/smallest_player_item_panel.dart
class SmallestPlayerItemPanel extends StatefulWidget {
  const SmallestPlayerItemPanel({
    super.key,
    required this.playerController,
    required this.videoPageController,
    required this.onBackPressed,
    required this.setPlaybackSpeed,
    required this.showDanmakuSwitch,
    required this.handleFullscreen,
    required this.handleProgressBarDragStart,
    required this.handleProgressBarSeek,
    required this.handleSuperResolutionChange,
    required this.panelVisibilityController,
    required this.acquirePlayerPanelHold,
    required this.onMenuVisibilityChanged,
    required this.handleDanmaku,
    required this.skipOP,
    required this.showVideoInfo,
    required this.showSyncPlayPanel,
    required this.pauseForTimedShutdown,
    this.disableAnimations = false,
  });

  final PlayerController playerController;
  final VideoPageController videoPageController;
  final void Function(BuildContext) onBackPressed;
  final Future<void> Function(double) setPlaybackSpeed;
  final void Function() showDanmakuSwitch;
  final void Function() handleDanmaku;
  final void Function() skipOP;
  final void Function() handleFullscreen;
  final VoidCallback handleProgressBarDragStart;
  final Future<void> Function(Duration duration) handleProgressBarSeek;
  final Future<void> Function(SuperResolutionMode mode)
      handleSuperResolutionChange;
  final AnimationController panelVisibilityController;
  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final ValueChanged<bool> onMenuVisibilityChanged;
  final void Function() showVideoInfo;
  final void Function() showSyncPlayPanel;
  final VoidCallback pauseForTimedShutdown;
  final bool disableAnimations;
}
```

## 3. 动画与显示控制

```dart
// lib/pages/player/smallest_player_item_panel.dart
class _SmallestPlayerItemPanelState extends State<SmallestPlayerItemPanel> {
  late Animation<Offset> topOffsetAnimation;
  late Animation<Offset> bottomOffsetAnimation;
  late final VideoPageController videoPageController =
      widget.videoPageController;
  late final PlayerController playerController;

  String? cachedSvgString;
  Widget? cachedDanmakuOnIcon;
  Widget? cachedDanmakuOffIcon;

  static const double _danmakuIconSize = 24.0;
  static const double _loadingIndicatorStrokeWidth = 2.0;

  @override
  void initState() {
    super.initState();
    playerController = widget.playerController;
    topOffsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: const Offset(0.0, 0.0),
    ).animate(CurvedAnimation(
      parent: widget.panelVisibilityController,
      curve: Curves.easeInOut,
    ));
    bottomOffsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, 1.0),
      end: const Offset(0.0, 0.0),
    ).animate(CurvedAnimation(
      parent: widget.panelVisibilityController,
      curve: Curves.easeInOut,
    ));
    cacheSvgIcons();
  }
```

面板显隐由 `playerController.panel` 和 `panelVisibilityController` 共同控制：

```dart
// lib/pages/player/smallest_player_item_panel.dart
Widget build(BuildContext context) {
  return Stack(
    alignment: Alignment.center,
    children: [
      AnimatedPositioned(
        duration: const Duration(seconds: 1),
        top: 0,
        left: 0,
        right: 0,
        child: Observer(builder: (context) {
          return Visibility(
            visible: !playerController.panel.lockPanel &&
                (widget.disableAnimations
                    ? playerController.panel.showVideoController
                    : true),
            child: widget.disableAnimations
                ? Container(
                    height: 50,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black45,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  )
                : SlideTransition(
                    position: topOffsetAnimation,
                    child: Container(
                      height: 50,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black45,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
          );
        }),
      ),
      ...
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Observer(builder: (context) {
          return Visibility(
            visible: !playerController.panel.lockPanel &&
                (widget.disableAnimations
                    ? playerController.panel.showVideoController
                    : true),
            child: widget.disableAnimations
                ? topControlWidget
                : SlideTransition(
                    position: topOffsetAnimation, child: topControlWidget),
          );
        }),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Observer(builder: (context) {
          return Visibility(
            visible: !playerController.panel.lockPanel &&
                (widget.disableAnimations
                    ? playerController.panel.showVideoController
                    : true),
            child: widget.disableAnimations
                ? bottomControlWidget
                : SlideTransition(
                    position: bottomOffsetAnimation,
                    child: bottomControlWidget),
          );
        }),
      ),
    ],
  );
}
```

## 4. 顶部控制区

```dart
// lib/pages/player/smallest_player_item_panel.dart
Widget get topControlWidget {
  return EmbeddedNativeControlArea(
    child: Row(
      children: [
        IconButton(
          color: Colors.white,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回',
          onPressed: () {
            widget.onBackPressed(context);
          },
        ),
        const Expanded(
          child: dtb.DragToMoveArea(child: SizedBox(height: 40)),
        ),
        forwardIcon(),
        if (isDesktop() || Platform.isAndroid)
          IconButton(
              onPressed: () async {
                if (isDesktop()) {
                  if (videoPageController.isPip) {
                    await PipUtils.exitDesktopPIPWindow();
                  } else {
                    await PipUtils.enterDesktopPIPWindow(
                      width: playerController.debug.playerWidth,
                      height: playerController.debug.playerHeight,
                    );
                  }
                  videoPageController.isPip = !videoPageController.isPip;
                  return;
                }
                final bool supported = await PipUtils.isAndroidPIPSupported();
                if (!supported) {
                  KazumiDialog.showToast(message: '当前设备不支持画中画');
                  return;
                }
                await PipUtils.updateAndroidPIPActions(
                  playing: playerController.playback.playing,
                  danmakuEnabled: playerController.danmaku.danmakuOn,
                  width: playerController.debug.playerWidth,
                  height: playerController.debug.playerHeight,
                );
                final bool entered = await PipUtils.enterAndroidPIPWindow(
                  width: playerController.debug.playerWidth,
                  height: playerController.debug.playerHeight,
                );
                if (!entered) {
                  KazumiDialog.showToast(message: '进入画中画失败');
                }
              },
              tooltip: '画中画',
              icon:
                  const Icon(Icons.picture_in_picture, color: Colors.white)),
        _buildDanmakuToggleButton(context),
        PlayerPanelHoldCollectButton(
          acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
          bangumiItem: videoPageController.bangumiItem,
        ),
        PlayerPanelHoldMenuAnchor(
          acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
          onVisibilityChanged: widget.onMenuVisibilityChanged,
          consumeOutsideTap: true,
          builder: (BuildContext context, MenuController controller,
              Widget? child) {
            return IconButton(
              onPressed: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              tooltip: '更多选项',
              icon: const Icon(
                Icons.more_vert,
                color: Colors.white,
              ),
            );
          },
          menuChildren: [
            SubmenuButton(
              menuChildren: [
                for (final aspectRatioMode in PlayerAspectRatio.values)
                  MenuItemButton(
                    onPressed: () => playerController.panel.aspectRatioMode =
                        aspectRatioMode,
                    child: Container(
                      height: 48,
                      constraints: BoxConstraints(minWidth: 112),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          aspectRatioMode.label,
                          style: TextStyle(
                              color: aspectRatioMode ==
                                      playerController.panel.aspectRatioMode
                                  ? Theme.of(context).colorScheme.primary
                                  : null),
                        ),
                      ),
                    ),
                  ),
              ],
              child: Container(
                height: 48,
                constraints: BoxConstraints(minWidth: 112),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("视频比例"),
                ),
              ),
            ),
            SubmenuButton(
              menuChildren: [
                for (final double i in defaultPlaySpeedList)
                  MenuItemButton(
                    onPressed: () async {
                      await widget.setPlaybackSpeed(i);
                    },
                    child: Container(
                      height: 48,
                      constraints: BoxConstraints(minWidth: 112),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${i}x',
                          style: TextStyle(
                              color: i == playerController.playback.playerSpeed
                                  ? Theme.of(context).colorScheme.primary
                                  : null),
                        ),
                      ),
                    ),
                  ),
              ],
              child: Container(
                height: 48,
                constraints: BoxConstraints(minWidth: 112),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("倍速"),
                ),
              ),
            ),
            SubmenuButton(
              menuChildren: [
                for (final mode in SuperResolutionMode.values)
                  MenuItemButton(
                    onPressed: () => widget.handleSuperResolutionChange(mode),
                    child: Container(
                      height: 48,
                      constraints: BoxConstraints(minWidth: 112),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          mode.label,
                          style: TextStyle(
                            color: playerController
                                        .playback.superResolutionMode ==
                                    mode
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
              child: Container(
                height: 48,
                constraints: BoxConstraints(minWidth: 112),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("超分辨率"),
                ),
              ),
            ),
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
            MenuItemButton(
              onPressed: () {
                widget.showDanmakuSwitch();
              },
              child: Container(
                height: 48,
                constraints: BoxConstraints(minWidth: 112),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("弹幕切换"),
                ),
              ),
            ),
            MenuItemButton(
              onPressed: () {
                showDanmakuSettingsSheet(
                  context: context,
                  danmakuController:
                      playerController.danmaku.canvasController,
                  onUpdateDanmakuSpeed: playerController.updateDanmakuSpeed,
                  onTimelineOffsetChanged: playerController
                      .danmaku.clearAndInvalidateScheduledDanmakus,
                );
              },
              child: Container(
                height: 48,
                constraints: BoxConstraints(minWidth: 112),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("弹幕设置"),
                ),
              ),
            ),
            MenuItemButton(
              onPressed: () {
                widget.showVideoInfo();
              },
              child: Container(
                height: 48,
                constraints: BoxConstraints(minWidth: 112),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("视频详情"),
                ),
              ),
            ),
            MenuItemButton(
              onPressed: () {
                bool needRestart = playerController.playback.playing;
                playerController.pause();
                RemotePlay()
                    .castVideo(playerController.videoUrl,
                        videoPageController.currentPlugin.referer)
                    .whenComplete(() {
                  if (mounted && needRestart) {
                    playerController.play();
                  }
                });
              },
              child: Container(
                height: 48,
                constraints: BoxConstraints(minWidth: 112),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("远程投屏"),
                ),
              ),
            ),
            MenuItemButton(
              onPressed: () {
                playerController.launchExternalPlayer();
              },
              child: Container(
                height: 48,
                constraints: BoxConstraints(minWidth: 112),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("外部播放"),
                ),
              ),
            ),
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                  onPressed: () {
                    TimedShutdownService().cancel();
                  },
                  child: Container(
                    height: 48,
                    constraints: BoxConstraints(minWidth: 112),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "不开启",
                        style: TextStyle(
                          color: !TimedShutdownService().isActive
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
                for (final int minutes in [15, 30, 60])
                  MenuItemButton(
                    onPressed: () {
                      TimedShutdownService().start(minutes,
                          onExpired: widget.pauseForTimedShutdown);
                      KazumiDialog.showToast(
                          message:
                              '已设置 ${TimedShutdownService().formatMinutesToDisplay(minutes)} 后定时关闭');
                    },
                    child: Container(
                      height: 48,
                      constraints: BoxConstraints(minWidth: 112),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "$minutes 分钟",
                          style: TextStyle(
                            color:
                                TimedShutdownService().setMinutes == minutes
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                MenuItemButton(
                  onPressed: () {
                    TimedShutdownService.showCustomTimerDialog(
                      onExpired: widget.pauseForTimedShutdown,
                    );
                  },
                  child: Container(
                    height: 48,
                    constraints: BoxConstraints(minWidth: 112),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text("自定义"),
                    ),
                  ),
                ),
              ],
              child: Container(
                height: 48,
                constraints: BoxConstraints(minWidth: 112),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ValueListenableBuilder<int>(
                    valueListenable:
                        TimedShutdownService().remainingSecondsNotifier,
                    builder: (context, remainingSeconds, child) {
                      return Text(
                        remainingSeconds > 0
                            ? "定时关闭 (${TimedShutdownService().formatRemainingTime()})"
                            : "定时关闭",
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
```

## 5. 底部控制区

```dart
// lib/pages/player/smallest_player_item_panel.dart
Widget get bottomControlWidget {
  return Row(
    children: [
      IconButton(
        icon: PlayPauseIcon(
          iconColor: Colors.white,
          playing: playerController.playback.playing,
        ),
        tooltip: playerController.playback.playing ? '暂停' : '播放',
        onPressed: () {
          playerController.playOrPause();
        },
      ),
      Expanded(
        child: Observer(builder: (context) {
          return ProgressBar(
            thumbRadius: 8,
            thumbGlowRadius: 18,
            timeLabelLocation: TimeLabelLocation.none,
            progress: playerController.playback.currentPosition,
            buffered: playerController.playback.buffer,
            total: playerController.playback.duration,
            onSeek: widget.handleProgressBarSeek,
            onDragStart: (_) => widget.handleProgressBarDragStart(),
            onDragUpdate: (details) => playerController.seeking
                .updateInteractiveSeek(details.timeStamp),
          );
        }),
      ),
      Observer(builder: (context) {
        return Text(
          "    ${durationToString(playerController.playback.currentPosition)} / ${durationToString(playerController.playback.duration)}",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.0,
            fontFeatures: [
              FontFeature.tabularFigures(),
            ],
          ),
        );
      }),
      (!videoPageController.isPip)
          ? IconButton(
              color: Colors.white,
              icon: Icon(videoPageController.isFullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded),
              tooltip: videoPageController.isFullscreen ? '退出全屏' : '全屏',
              onPressed: () {
                widget.handleFullscreen();
              },
            )
          : const Text('    '),
    ],
  );
}
```

## 6. 弹幕开关与快进按钮

```dart
// lib/pages/player/smallest_player_item_panel.dart
Widget _buildDanmakuToggleButton(BuildContext context) {
  return Observer(builder: (context) {
    final danmakuLoading = playerController.danmaku.danmakuLoading;
    final danmakuOn = playerController.danmaku.danmakuOn;
    return IconButton(
      color: Colors.white,
      icon: danmakuLoading
          ? SizedBox(
              width: _danmakuIconSize,
              height: _danmakuIconSize,
              child: CircularProgressIndicator(
                strokeWidth: _loadingIndicatorStrokeWidth,
              ),
            )
          : (danmakuOn ? danmakuOnIcon(context) : cachedDanmakuOffIcon!),
      onPressed: danmakuLoading
          ? null
          : () {
              widget.handleDanmaku();
            },
      tooltip: danmakuLoading ? '弹幕加载中...' : (danmakuOn ? '关闭弹幕' : '打开弹幕'),
    );
  });
}

Widget forwardIcon() {
  return Tooltip(
    message: '快进${playerController.playback.buttonSkipTime}秒，长按修改时间',
    child: GestureDetector(
      onLongPress: () => showForwardChange(),
      child: IconButton(
        icon: Image.asset(
          'assets/images/forward_80.png',
          color: Colors.white,
          height: 24,
        ),
        onPressed: () {
          widget.skipOP();
        },
      ),
    ),
  );
}
```

快进秒数可修改：

```dart
// lib/pages/player/smallest_player_item_panel.dart
void showForwardChange() {
  KazumiDialog.show(builder: (context) {
    String input = "";
    return AlertDialog(
      title: const Text('跳过秒数'),
      content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
        return TextField(
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            floatingLabelBehavior: FloatingLabelBehavior.never,
            labelText: playerController.playback.buttonSkipTime.toString(),
          ),
          onChanged: (value) {
            input = value;
          },
        );
      }),
      actions: <Widget>[
        TextButton(
          onPressed: () => KazumiDialog.dismiss(),
          child: Text(
            '取消',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        TextButton(
          onPressed: () async {
            if (input != "") {
              playerController.setButtonForwardTime(int.parse(input));
              KazumiDialog.dismiss();
            } else {
              KazumiDialog.dismiss();
            }
          },
          child: const Text('确定'),
        ),
      ],
    );
  });
}
```

## 7. 面板状态依赖

最小面板并不直接管理 show/hide 状态，而是消费 `PlayerPanelController`：

```dart
// lib/pages/player/controller/player_panel_controller.dart
abstract class _PlayerPanelController with Store {
  @observable
  PlayerAspectRatio aspectRatioMode = PlayerAspectRatio.automatic;
  @observable
  double brightness = 0;
  @observable
  bool lockPanel = false;
  @observable
  bool showVideoController = true;
  @observable
  bool showSeekTime = false;
  @observable
  bool showBrightness = false;
  @observable
  bool showVolume = false;
  @observable
  bool showPlaySpeed = false;
  @observable
  bool brightnessSeeking = false;
  @observable
  bool volumeSeeking = false;
  int seekDirection = 0;
  @observable
  bool canHidePlayerPanel = true;

  @action
  void reset() {
    lockPanel = false;
    showVideoController = true;
    showSeekTime = false;
    showBrightness = false;
    showVolume = false;
    showPlaySpeed = false;
    brightnessSeeking = false;
    volumeSeeking = false;
    seekDirection = 0;
    canHidePlayerPanel = true;
  }
}
```

## 8. 菜单展开时的面板保持

当用户打开更多选项菜单时，面板不会因自动隐藏逻辑而消失：

```dart
// lib/pages/player/player_panel_hold.dart
class PlayerPanelHoldMenuAnchor extends StatefulWidget {
  const PlayerPanelHoldMenuAnchor({
    super.key,
    required this.acquirePlayerPanelHold,
    required this.onVisibilityChanged,
    required this.builder,
    required this.menuChildren,
    this.consumeOutsideTap = false,
  });

  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final ValueChanged<bool> onVisibilityChanged;
  final Widget Function(
    BuildContext context,
    MenuController controller,
    Widget? child,
  ) builder;
  final List<Widget> menuChildren;
  final bool consumeOutsideTap;

  @override
  State<PlayerPanelHoldMenuAnchor> createState() =>
      _PlayerPanelHoldMenuAnchorState();
}

class _PlayerPanelHoldMenuAnchorState extends State<PlayerPanelHoldMenuAnchor> {
  PlayerPanelHold? _hold;
  bool _isOpen = false;

  @override
  void dispose() {
    _handleClose();
    super.dispose();
  }

  void _handleOpen() {
    if (_isOpen) {
      return;
    }
    _isOpen = true;
    widget.onVisibilityChanged(true);
    if (_hold?.isReleased == false) {
      return;
    }
    _hold = widget.acquirePlayerPanelHold();
  }

  void _handleClose() {
    if (_isOpen) {
      _isOpen = false;
      widget.onVisibilityChanged(false);
    }
    _hold?.release();
    _hold = null;
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      consumeOutsideTap: widget.consumeOutsideTap,
      onOpen: _handleOpen,
      onClose: _handleClose,
      builder: widget.builder,
      menuChildren: widget.menuChildren,
    );
  }
}
```

```dart
// lib/pages/player/player_panel_hold.dart
class PlayerPanelHold {
  PlayerPanelHold({required VoidCallback onRelease}) : _onRelease = onRelease;

  VoidCallback? _onRelease;

  bool get isReleased => _onRelease == null;

  void release() {
    final onRelease = _onRelease;
    if (onRelease == null) {
      return;
    }
    _onRelease = null;
    onRelease();
  }

  void releaseSilently() {
    _onRelease = null;
  }
}
```

## 9. 与完整播放器面板的联系

`SmallestPlayerItemPanel` 和 `PlayerItemPanel` 共享同一组外部能力：

- `showSyncPlayPanel`
- `showDanmakuSwitch`
- `showVideoInfo`
- `handleSuperResolutionChange`
- `acquirePlayerPanelHold`

最小面板只保留更紧凑的控制项，适合：

- 小窗口
- 画中画
- 桌面悬浮播放
- 手机横屏资源受限场景

其可见性控制仍然遵循同一套面板锁/自动隐藏机制，因此相关生命周期和状态切换会随着 `PlayerPanelController` 一起变化。
