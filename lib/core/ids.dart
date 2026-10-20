import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

final _rnd = Random.secure();
const _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

String randomString(int n, [String alphabet = _alphabet]) =>
    List.generate(n, (_) => alphabet[_rnd.nextInt(alphabet.length)]).join();

/// Id univoco ordinabile nel tempo.
String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36) + randomString(5);

bool get isAndroid => !kIsWeb && Platform.isAndroid;
bool get isWindows => !kIsWeb && Platform.isWindows;
bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

const appVersion = '1.0.1';
const appBuild = 2;
const githubRepo = 'psyko-cyber/dollarz';
