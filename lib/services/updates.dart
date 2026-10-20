import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/ids.dart';
import '../data/local_prefs.dart';
import 'win_shell.dart';

class UpdateInfo {
  final String version;
  final String pageUrl;
  final String? downloadUrl;
  final String notes;
  final String? sumsUrl; // SHA256SUMS.txt della release
  const UpdateInfo(this.version, this.pageUrl, this.downloadUrl, this.notes, [this.sumsUrl]);

  Map<String, dynamic> toMap() => {'version': version, 'page': pageUrl, 'download': downloadUrl, 'notes': notes, 'sums': sumsUrl};
  static UpdateInfo? fromMap(Map<String, dynamic>? m) => m == null
      ? null
      : UpdateInfo(m['version'] as String, m['page'] as String, m['download'] as String?, (m['notes'] as String?) ?? '', m['sums'] as String?);
}

/// Aggiornamento trovato e non rimandato: lo mostrano il popup e la card in home.
final updateNotice = ValueNotifier<UpdateInfo?>(null);

/// "Più tardi": la stessa versione non viene riproposta per 20 ore.
bool updateSnoozed(LocalPrefs prefs, UpdateInfo u) =>
    prefs.dismissedUpdate == u.version && DateTime.now().millisecondsSinceEpoch - prefs.updateLaterAt < 20 * 3600 * 1000;

void snoozeUpdate(LocalPrefs prefs, UpdateInfo u) {
  prefs.dismissedUpdate = u.version;
  prefs.updateLaterAt = DateTime.now().millisecondsSinceEpoch;
  updateNotice.value = null;
}

/// Note della release in testo semplice (senza ## e **).
String plainNotes(String md) => md
    .replaceAll('**', '')
    .split('\n')
    .map((l) => l.replaceFirst(RegExp(r'^#+\s*'), '').trimRight())
    .join('\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// SHA-256 atteso per [file] in SHA256SUMS.txt (`hash *nome` o `hash  nome`).
String? expectedSha(String sums, String file) {
  for (final line in const LineSplitter().convert(sums)) {
    final m = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(line.trim());
    if (m != null && m.group(2)!.trim() == file) return m.group(1)!.toLowerCase();
  }
  return null;
}

class UpdateCancelled implements Exception {}

/// Cartella privata dei download (su Android la cache dell'app: niente file in Download).
Future<Directory> _updateDir() async => Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}dollarz-update');

/// All'avvio: via i file di aggiornamento già usati.
Future<void> cleanUpdates() async {
  try {
    final d = await _updateDir();
    if (await d.exists()) await d.delete(recursive: true);
  } catch (_) {}
}

/// Scarica il file della release e controlla lo SHA-256 con SHA256SUMS.txt.
Future<File> downloadUpdate(UpdateInfo u, {void Function(double)? onProgress, bool Function()? cancelled}) async {
  final url = Uri.parse(u.downloadUrl!);
  final dir = await _updateDir();
  await cleanUpdates();
  await dir.create(recursive: true);
  final name = url.pathSegments.last;
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  final client = http.Client();
  try {
    final r = await client.send(http.Request('GET', url)..headers['User-Agent'] = 'Dollarz/$appVersion').timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode}');
    final total = r.contentLength ?? 0;
    final sink = file.openWrite();
    var got = 0;
    try {
      await for (final chunk in r.stream.timeout(const Duration(seconds: 30))) {
        if (cancelled?.call() ?? false) throw UpdateCancelled();
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
    } finally {
      await sink.close();
    }
    if (total > 0 && got != total) throw const HttpException('Download incompleto');
    if (u.sumsUrl != null) {
      final s = await client.get(Uri.parse(u.sumsUrl!)).timeout(const Duration(seconds: 15));
      final want = s.statusCode == 200 ? expectedSha(s.body, name) : null;
      if (want != null && want != (await sha256.bind(file.openRead()).first).toString()) {
        await file.delete();
        throw const FormatException('File scaricato non valido');
      }
    }
    return file;
  } catch (_) {
    await cleanUpdates();
    rethrow;
  } finally {
    client.close();
  }
}

const _channel = MethodChannel('dollarz/update');

/// Installa sopra la versione attuale (stessa firma: i dati restano).
/// Android apre l'installer di sistema; Windows lancia il setup silenzioso con
/// la richiesta di Windows: chiude Dollarz e lo riapre aggiornato (/RELAUNCH=1).
/// Ritorna false se su Windows la richiesta è stata rifiutata.
Future<bool> installUpdate(File f) async {
  if (isAndroid) {
    await _channel.invokeMethod('installApk', f.path);
  } else if (isWindows) {
    return shellExecute('runas', f.path, '/SILENT /NORESTART /RELAUNCH=1');
  }
  return true;
}

/// true se [a] è più recente di [b] ("1.2.0" > "1.1.9").
bool isNewer(String a, String b) {
  List<int> parse(String v) => v.replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[.+-]')).map((e) => int.tryParse(e) ?? 0).toList();
  final x = parse(a), y = parse(b);
  for (var i = 0; i < 3; i++) {
    final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi > yi;
  }
  return false;
}

/// Controlla l'ultima release su GitHub (al massimo ogni 12 ore).
Future<UpdateInfo?> checkForUpdate(LocalPrefs prefs, {bool force = false}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  if (!force && now - prefs.lastUpdateCheck < 12 * 3600 * 1000) {
    final cached = UpdateInfo.fromMap(prefs.availableUpdate);
    return cached != null && isNewer(cached.version, appVersion) ? cached : null;
  }
  try {
    final r = await http.get(Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest'), headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'Dollarz/$appVersion',
    }).timeout(const Duration(seconds: 15));
    prefs.lastUpdateCheck = now;
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map;
    final tag = (j['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^[vV]'), '');
    if (tag.isEmpty || !isNewer(tag, appVersion)) {
      prefs.availableUpdate = null;
      return null;
    }
    String? dl, sums;
    for (final a in (j['assets'] as List? ?? const [])) {
      final name = ((a as Map)['name'] as String? ?? '').toLowerCase();
      if ((isAndroid && name.endsWith('.apk')) || (isWindows && name.endsWith('.exe'))) dl ??= a['browser_download_url'] as String?;
      if (name == 'sha256sums.txt') sums = a['browser_download_url'] as String?;
    }
    final info = UpdateInfo(tag, j['html_url'] as String? ?? 'https://github.com/$githubRepo/releases', dl, (j['body'] as String? ?? '').trim(), sums);
    prefs.availableUpdate = info.toMap();
    return info;
  } catch (_) {
    return null;
  }
}
