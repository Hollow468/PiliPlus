import 'dart:async';
import 'package:PiliPlus/services/player/syncplay_endpoint.dart';
import 'dart:math' show min, Random;

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/pages/player/controller/player_syncplay_controller.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

enum _SyncPlayDestination { create, join, server }

Future<T?> _showStep<T>(
    BuildContext context, WidgetBuilder pageBuilder) async {
  final result = await Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      pageBuilder: (context, animation, secondaryAnimation) {
        return FadeTransition(opacity: animation, child: pageBuilder(context));
      },
      transitionDuration: const Duration(milliseconds: 200),
    ),
  );
  return result;
}

Future<void> showSyncPlaySheet(
  BuildContext context, {
  required PlayerSyncPlayController playerController,
  required Future<void> Function(int episode, {int? currentRoad, int? offset})
      changeEpisode,
}) async {
  final destination = await _showStep<_SyncPlayDestination>(
    context,
    (context) => _SyncPlayHomeSheet(playerController: playerController),
  );
  if (destination == null || !context.mounted) {
    return;
  }
  await _showStep<void>(
    context,
    (context) {
      return switch (destination) {
        _SyncPlayDestination.create || _SyncPlayDestination.join =>
          _SyncPlayRoomSheet(
            isCreate: destination == _SyncPlayDestination.create,
            playerController: playerController,
            changeEpisode: changeEpisode,
          ),
        _SyncPlayDestination.server => const _SyncPlayServerSheet(),
      };
    },
  );
}

class _SyncPlaySheetScaffold extends StatelessWidget {
  const _SyncPlaySheetScaffold({
    required this.title,
    required this.description,
    required this.primaryAction,
    required this.bodyBuilder,
    this.compact = false,
  });

  final String title;
  final String description;
  final Widget? primaryAction;
  final Widget Function(BuildContext, bool) bodyBuilder;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedPadding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: min(420, MediaQuery.of(context).size.width),
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 18)),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (primaryAction != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: primaryAction!,
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              Flexible(
                child: bodyBuilder(context, compact),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncPlayHomeSheet extends StatelessWidget {
  const _SyncPlayHomeSheet({required this.playerController});

  final PlayerSyncPlayController playerController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SyncPlaySheetScaffold(
      title: '一起看',
      description: '与好友同步播放、暂停与选集',
      primaryAction: playerController.hasSession
          ? FilledButton.tonalIcon(
              onPressed: () async {
                await playerController.exitRoom();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.link_off_rounded, size: 18),
              label: Text(
                playerController.syncplayRoom.isEmpty
                    ? '取消连接'
                    : '断开连接',
              ),
            )
          : null,
      bodyBuilder: (context, compact) {
        final connected = playerController.syncplayRoom.isNotEmpty;
        final connecting = playerController.hasSession && !connected;
        if (connected) {
          return _buildConnected(context, theme);
        }
        if (connecting) {
          return _buildConnecting(context, theme);
        }
        return _buildLobby(context, theme);
      },
    );
  }

  Widget _buildConnected(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.meeting_room_rounded,
              size: 42, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Obx(() {
            final room = playerController.syncplayRoom.value;
            final rtt = playerController.syncplayClientRtt.value;
            return Text('房间号：$room',
                style: const TextStyle(fontSize: 16));
          }),
          const SizedBox(height: 8),
          Text('延迟：${playerController.syncplayClientRtt.value} ms',
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13)),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () async {
              await playerController.exitRoom();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.link_off_rounded, size: 18),
            label: const Text('断开连接'),
          ),
        ],
      ),
    );
  }

  Widget _buildConnecting(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('正在加入一起看...',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () async {
              await playerController.exitRoom();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('取消连接'),
          ),
        ],
      ),
    );
  }

  Widget _buildLobby(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionCard(
            icon: Icons.add_rounded,
            title: '创建房间',
            description: '生成房间号并邀请好友加入',
            onTap: () =>
                Navigator.of(context).pushReplacement(PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) {
                return FadeTransition(
                  opacity: animation,
                  child: _SyncPlayRoomSheet(
                    isCreate: true,
                    playerController: playerController,
                    changeEpisode: (_, {int? currentRoad, int? offset}) async {},
                  ),
                );
              },
              transitionDuration: const Duration(milliseconds: 220),
            )),
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.login_rounded,
            title: '加入房间',
            description: '输入房间号与好友同步播放',
            onTap: () =>
                Navigator.of(context).pushReplacement(PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) {
                return FadeTransition(
                  opacity: animation,
                  child: _SyncPlayRoomSheet(
                    isCreate: false,
                    playerController: playerController,
                    changeEpisode: (_, {int? currentRoad, int? offset}) async {},
                  ),
                );
              },
              transitionDuration: const Duration(milliseconds: 220),
            )),
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.dns_rounded,
            title: '同步服务器',
            description: '切换自定义 SyncPlay 服务器',
            onTap: () =>
                Navigator.of(context).pushReplacement(PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) {
                return const FadeTransition(
                  opacity: AlwaysStoppedAnimation(1),
                  child: _SyncPlayServerSheet(),
                );
              },
              transitionDuration: const Duration(milliseconds: 220),
            )),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SyncPlayRoomSheet extends StatefulWidget {
  const _SyncPlayRoomSheet({
    required this.isCreate,
    required this.playerController,
    required this.changeEpisode,
  });

  final bool isCreate;
  final PlayerSyncPlayController playerController;
  final Future<void> Function(int episode, {int? currentRoad, int? offset})
      changeEpisode;

  @override
  State<_SyncPlayRoomSheet> createState() => _SyncPlayRoomSheetState();
}

class _SyncPlayRoomSheetState extends State<_SyncPlayRoomSheet> {
  static final Random _random = Random();
  static String _generateRoomNumber() =>
      List.generate(8, (_) => _random.nextInt(10)).join();

  static String _generateUserName() {
    const consonants = 'bcdfghjklmnpqrstvwxyz';
    const vowels = 'aeiou';
    final syllables = 3 + _random.nextInt(2);
    final buffer = StringBuffer();
    for (int i = 0; i < syllables; i++) {
      buffer.write(consonants[_random.nextInt(consonants.length)]);
      buffer.write(vowels[_random.nextInt(vowels.length)]);
    }
    final name = buffer.toString();
    return name[0].toUpperCase() + name.substring(1);
  }

  final _formKey = GlobalKey<FormState>();
  final _roomController = TextEditingController();
  final _usernameController = TextEditingController();

  late String _createdRoom = _generateRoomNumber();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _usernameController.text =
        GStorage.setting.get(SettingBoxKey.syncPlayUserName) ?? '';
    if (_usernameController.text.isEmpty) {
      _usernameController.text = _generateUserName();
    }
  }

  @override
  void dispose() {
    _roomController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_submitting) {
      return;
    }
    final username = _usernameController.text.trim();
    final room = widget.isCreate ? _createdRoom : _roomController.text.trim();
    setState(() => _submitting = true);
    await widget.playerController.createRoom(room, username);
    GStorage.setting.put(SettingBoxKey.syncPlayUserName, username);
    if (!mounted) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SyncPlaySheetScaffold(
      title: widget.isCreate ? '创建房间' : '加入房间',
      description: '与好友同步播放、暂停与选集',
      primaryAction: null,
              bodyBuilder: (context, compact) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.isCreate) ...[
                  TextFormField(
                    controller: _roomController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: const InputDecoration(
                      labelText: '房间号',
                      hintText: '6-10 位数字',
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty) {
                        return '请输入房间号';
                      }
                      if (!RegExp(r'^[0-9]{6,10}$').hasMatch(text)) {
                        return '房间号为 6-10 位数字';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                if (widget.isCreate)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.vpn_key_rounded, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('房间号：$_createdRoom',
                              style: const TextStyle(fontSize: 15)),
                        ),
                      ],
                    ),
                  ),
                if (widget.isCreate) const SizedBox(height: 14),
                TextFormField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.done,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(
                    labelText: '昵称',
                    hintText: '4-12 位英文字母，房间内可见',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return '请输入昵称';
                    }
                    if (!RegExp(r'^[a-zA-Z]{4,12}$').hasMatch(text)) {
                      return '昵称为 4-12 位英文字母';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(widget.isCreate ? '创建并加入' : '加入房间'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SyncPlayServerSheet extends StatelessWidget {
  const _SyncPlayServerSheet();

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();
    final current = GStorage.setting.get(SettingBoxKey.syncPlayEndPoint,
            defaultValue: defaultSyncPlayEndPoint) ??
        defaultSyncPlayEndPoint;
    controller.text = current;

    return _SyncPlaySheetScaffold(
      title: '同步服务器',
      description: '自定义 SyncPlay 服务器地址',
      primaryAction: null,
              bodyBuilder: (context, compact) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'host:port',
                  prefixIcon: Icon(Icons.dns_rounded),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    GStorage.setting.put(
                        SettingBoxKey.syncPlayEndPoint, controller.text);
                    SmartDialog.showToast('已保存 SyncPlay 服务器地址');
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('保存'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
