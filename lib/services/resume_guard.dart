import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Su Windows, dopo tray, blocco schermo o monitor spento, Flutter può restare
/// nello stato "hidden": i dati si salvano ma la schermata non si ridisegna
/// più (i tasti "sembrano" non funzionare). Appena la finestra torna visibile
/// o l'utente la tocca, riporto l'app allo stato "resumed".
void ensureResumed() {
  final b = WidgetsBinding.instance;
  if (b.lifecycleState != AppLifecycleState.resumed) {
    // stesso messaggio che invia il sistema quando l'app torna in primo piano
    ui.channelBuffers.push(
      SystemChannels.lifecycle.name,
      SystemChannels.lifecycle.codec.encodeMessage(AppLifecycleState.resumed.toString()),
      (_) {},
    );
  }
  b.scheduleFrame();
}

bool _installed = false;

/// Qualsiasi clic o tocco sulla finestra la rende di nuovo "attiva".
void installResumeGuard() {
  if (_installed) return;
  _installed = true;
  GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
    if (e is PointerDownEvent || e is PointerHoverEvent || e is PointerScrollEvent) {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) ensureResumed();
    }
  });
}
