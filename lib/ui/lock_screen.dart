import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ids.dart';
import '../core/theme.dart';
import '../services/services.dart';
import 'widgets.dart';

/// Tastierino del PIN (sblocco, creazione, conferma).
class PinPad extends StatelessWidget {
  final int length;
  final int filled;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback? onBio;
  final bool error;
  const PinPad({super.key, this.length = 6, required this.filled, required this.onDigit, required this.onDelete, this.onBio, this.error = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => SizedBox(
          width: 76,
          height: 64,
          child: Tap(
            radius: 32,
            onTap: onTap,
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 26, color: t.soft)
                  : Text(label, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: t.ink, fontFeatures: tabular)),
            ),
          ),
        );
    void digit(String d) {
      HapticFeedback.selectionClick();
      onDigit(d);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 7),
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: error ? TC.neg : (i < filled ? TC.accent : Colors.transparent),
              border: Border.all(color: error ? TC.neg : (i < filled ? TC.accent : t.dim), width: 1.6),
            ),
          ),
      ]),
      const SizedBox(height: 30),
      for (final row in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ])
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) key(d, onTap: () => digit(d))]),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        onBio != null ? key('', icon: isWindows ? Icons.face_rounded : Icons.fingerprint_rounded, onTap: onBio) : const SizedBox(width: 76, height: 64),
        key('0', onTap: () => digit('0')),
        key('', icon: Icons.backspace_outlined, onTap: onDelete),
      ]),
    ]);
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  bool _error = false;
  bool _checking = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // impronta subito, se attiva
    WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (Services.lock.waitSeconds > 0 && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _bio() async {
    if (!Services.lock.canUseBio) return;
    await Services.lock.unlockBio();
  }

  Future<void> _digit(String d) async {
    if (_checking || Services.lock.waitSeconds > 0) return;
    setState(() {
      _error = false;
      _pin += d;
    });
    if (_pin.length < 6) return;
    _checking = true;
    final ok = await Services.lock.unlockPin(_pin);
    _checking = false;
    if (!mounted) return;
    if (!ok) {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = true;
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final wait = Services.lock.waitSeconds;
    return Material(
      color: t.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const DollarzMark(size: 56),
              const SizedBox(height: 18),
              Text('Dollarz è bloccato', style: TS.h2(t)),
              const SizedBox(height: 6),
              Text(
                wait > 0 ? 'Troppi tentativi: riprova tra $wait s' : (_error ? 'PIN sbagliato' : 'Inserisci il PIN'),
                style: TextStyle(fontSize: 14, color: _error || wait > 0 ? TC.neg : t.dim),
              ),
              const SizedBox(height: 30),
              PinPad(
                filled: _pin.length,
                error: _error,
                onDigit: _digit,
                onDelete: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
                onBio: Services.lock.canUseBio ? _bio : null,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Crea un PIN nuovo (due volte). Ritorna true se impostato.
Future<bool> setupPin(BuildContext context) async {
  final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const _PinSetup()));
  return r ?? false;
}

class _PinSetup extends StatefulWidget {
  const _PinSetup();
  @override
  State<_PinSetup> createState() => _PinSetupState();
}

class _PinSetupState extends State<_PinSetup> {
  String _first = '';
  String _pin = '';
  bool _error = false;
  bool _saving = false;

  Future<void> _digit(String d) async {
    if (_saving) return;
    setState(() {
      _error = false;
      _pin += d;
    });
    if (_pin.length < 6) return;
    if (_first.isEmpty) {
      setState(() {
        _first = _pin;
        _pin = '';
      });
      return;
    }
    if (_pin != _first) {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = true;
        _first = '';
        _pin = '';
      });
      return;
    }
    setState(() => _saving = true);
    await Services.lock.setPin(_pin);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return SubPage(
      title: 'PIN di Dollarz',
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_first.isEmpty ? 'Scegli un PIN di 6 cifre' : 'Ripetilo per conferma', style: TS.h2(t)),
            const SizedBox(height: 6),
            Text(_error ? 'I due PIN non coincidono: ricomincia' : 'Serve per aprire l\'app se l\'impronta non va.',
                style: TextStyle(fontSize: 13.5, color: _error ? TC.neg : t.dim)),
            const SizedBox(height: 30),
            if (_saving)
              const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())
            else
              PinPad(
                filled: _pin.length,
                error: _error,
                onDigit: _digit,
                onDelete: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
              ),
          ]),
        ),
      ),
    );
  }
}
