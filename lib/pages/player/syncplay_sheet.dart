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

Future<void> showSyncPlaySheet(
  BuildContext context, {
  required PlayerSyncPlayController playerController,
  required Future<void> Function(int episode, {int? currentRoad, int? offset})
      changeEpisode,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      return _SyncPlayDialog(playerController: playerController);
    },
  );
}

class _SyncPlayDialog extends StatefulWidget {
  const _SyncPlayDialog({required this.playerController});

  final PlayerSyncPlayController playerController;

  @override
  State<_SyncPlayDialog> createState() => _SyncPlayDialogState();
}

class _SyncPlayDialogState extends State<_SyncPlayDialog> {
  _SyncPlayStep _step = _SyncPlayStep.home;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedPadding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
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
                        Text(_title, style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 4),
                        Text(
                          _description,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_step != _SyncPlayStep.home)
                    IconButton(
                      onPressed: () => setState(() => _step = _SyncPlayStep.home),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: '关闭',
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            _buildBody(context, theme),
          ],
        ),
      ),
    );
  }

  String get _title {
    return switch (_step) {
      _SyncPlayStep.home => '一起看',
      _SyncPlayStep.create => '创建房间',
      _SyncPlayStep.join => '加入房间',
      _SyncPlayStep.server => '同步服务器',
    };
  }

  String get _description {
    return switch (_step) {
      _SyncPlayStep.home => '与好友同步播放、暂停与进度',
      _SyncPlayStep.create => '生成房间号并邀请好友加入',
      _SyncPlayStep.join => '输入房间号与好友同步播放',
      _SyncPlayStep.server => '自定义同步服务器地址',
    };
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    final connected = widget.playerController.syncplayRoom.isNotEmpty;
    final connecting = widget.playerController.hasSession && !connected;
    switch (_step) {
      case _SyncPlayStep.home:
        return _buildHome(context, theme, connected: connected, connecting: connecting);
      case _SyncPlayStep.create:
        return _buildRoomForm(context, isCreate: true);
      case _SyncPlayStep.join:
        return _buildRoomForm(context, isCreate: false);
      case _SyncPlayStep.server:
        return const _SyncPlayServerSheet();
    }
  }

  Widget _buildHome(
    BuildContext context,
    ThemeData theme, {
    required bool connected,
    required bool connecting,
  }) {
    if (connected) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.meeting_room_rounded,
                size: 42, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Obx(() {
              return Text('房间号：${widget.playerController.syncplayRoom.value}',
                  style: const TextStyle(fontSize: 16));
            }),
            const SizedBox(height: 8),
            Text('延迟：${widget.playerController.syncplayClientRtt.value} ms',
                style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await widget.playerController.exitRoom();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: const Text('断开连接'),
              ),
            ),
          ],
        ),
      );
    }
    if (connecting) {
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
                await widget.playerController.exitRoom();
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionCard(
            icon: Icons.add_rounded,
            title: '创建房间',
            description: '生成房间号并邀请好友加入',
            onTap: () => setState(() => _step = _SyncPlayStep.create),
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.login_rounded,
            title: '加入房间',
            description: '输入房间号与好友同步播放',
            onTap: () => setState(() => _step = _SyncPlayStep.join),
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.dns_rounded,
            title: '同步服务器',
            description: '切换自定义同步服务器',
            onTap: () => setState(() => _step = _SyncPlayStep.server),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomForm(BuildContext context, {required bool isCreate}) {
    return _SyncPlayRoomSheet(
      isCreate: isCreate,
      playerController: widget.playerController,
      changeEpisode: (_, {int? currentRoad, int? offset}) async {},
      onFinished: () {
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
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
    required this.onFinished,
  });

  final bool isCreate;
  final PlayerSyncPlayController playerController;
  final Future<void> Function(int episode, {int? currentRoad, int? offset})
      changeEpisode;
  final VoidCallback onFinished;

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
    if (widget.isCreate) {
      _roomController.text = _createdRoom;
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
    final room = _roomController.text.trim();
    setState(() => _submitting = true);
    await widget.playerController.createRoom(room, username);
    GStorage.setting.put(SettingBoxKey.syncPlayUserName, username);
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _roomController,
              autofocus: !widget.isCreate,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
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
                SmartDialog.showToast('已保存同步服务器地址');
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
  }
}

enum _SyncPlayStep { home, create, join, server }
