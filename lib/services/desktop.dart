import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme.dart';
import '../data/app_state.dart';
import 'resume_guard.dart';

/// Integrazione Windows: finestra, icona nel tray, avvio con Windows e
/// istanza unica (se riapri Dollarz mentre è nel tray, si mostra quella).
class DesktopService with WindowListener, TrayListener {
  static const _instancePort = 47829;
  static ServerSocket? _instanceServer;
  static VoidCallback? _onShowRequest;
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _runName = 'Dollarz';

  final AppState app;
  final Future<void> Function() onSyncNow;
  final Future<void> Function() onQuit;
  final VoidCallback onQuickAdd;
  DesktopService(this.app, {required this.onSyncNow, required this.onQuit, required this.onQuickAdd});

  /// false = c'è già un'altra istanza (a cui ho chiesto di mostrarsi).
  static Future<bool> ensureSingleInstance() async {
    try {
      _instanceServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, _instancePort);
      _instanceServer!.listen((c) {
        c.listen((data) {
          if (utf8.decode(data, allowMalformed: true).contains('show')) _onShowRequest?.call();
        }, onDone: () => c.destroy(), onError: (_) => c.destroy());
      });
      return true;
    } catch (_) {
      try {
        final c = await Socket.connect(InternetAddress.loopbackIPv4, _instancePort, timeout: const Duration(seconds: 2));
        c.write('show');
        await c.flush();
        await c.close();
      } catch (_) {}
      return false;
    }
  }

  static Future<void> initWindow({required bool hidden}) async {
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      size: Size(1240, 860),
      minimumSize: Size(420, 640),
      center: true,
      title: 'Dollarz',
      backgroundColor: TC.bg,
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      if (!hidden) {
        await windowManager.show();
        await windowManager.focus();
      }
    });
    await windowManager.setPreventClose(true);
  }

  Future<void> init() async {
    _onShowRequest = showWindow;
    windowManager.addListener(this);
    await _initTray();
  }

  Future<void> _initTray() async {
    try {
      await trayManager.setIcon('assets/brand/tray.ico');
      await trayManager.setToolTip('Dollarz');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'Apri Dollarz'),
        MenuItem(key: 'add', label: 'Nuovo movimento'),
        MenuItem(key: 'sync', label: 'Sincronizza ora'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Esci da Dollarz'),
      ]));
      trayManager.addListener(this);
    } catch (e) {
      debugPrint('tray non disponibile: $e');
    }
  }

  Future<void> showWindow() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
    ensureResumed();
  }

  Future<void> quit() async {
    await onQuit();
    try {
      await trayManager.destroy();
    } catch (_) {}
    await _instanceServer?.close();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // ---------------------------------------------------------------- listener

  // la finestra torna visibile: riprendo a disegnare (vedi resume_guard.dart)
  @override
  void onWindowFocus() => ensureResumed();

  @override
  void onWindowRestore() => ensureResumed();

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'show') ensureResumed();
  }

  @override
  void onWindowClose() async {
    if (app.prefs.trayEnabled) {
      await windowManager.hide();
    } else {
      await quit();
    }
  }

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
      case 'add':
        showWindow().then((_) => onQuickAdd());
      case 'sync':
        onSyncNow();
      case 'quit':
        quit();
    }
  }

  // ---------------------------------------------------------------- avvio automatico

  static Future<bool> isAutostart() async {
    try {
      final r = await Process.run('reg', ['query', _runKey, '/v', _runName]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setAutostart(bool on) async {
    try {
      final r = on
          ? await Process.run('reg', ['add', _runKey, '/v', _runName, '/t', 'REG_SZ', '/d', '"${Platform.resolvedExecutable}" --tray', '/f'])
          : await Process.run('reg', ['delete', _runKey, '/v', _runName, '/f']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
