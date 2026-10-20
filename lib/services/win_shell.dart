import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// ShellExecute di Windows: [verb] 'open' oppure 'runas' (come amministratore,
/// con la richiesta di conferma di Windows in primo piano).
/// Ritorna false se la richiesta è stata rifiutata; lancia se l'avvio fallisce.
///
/// Niente PowerShell: avviato "staccato" da un'app senza console, su alcune
/// versioni di Windows 11 non esegue il comando e l'installer non parte mai.
bool shellExecute(String verb, String file, String params, {bool hidden = false}) {
  final exec = DynamicLibrary.open('shell32.dll').lookupFunction<
      IntPtr Function(IntPtr hwnd, Pointer<Utf16> verb, Pointer<Utf16> file, Pointer<Utf16> params, Pointer<Utf16> dir, Int32 show),
      int Function(int hwnd, Pointer<Utf16> verb, Pointer<Utf16> file, Pointer<Utf16> params, Pointer<Utf16> dir, int show)>('ShellExecuteW');
  final v = verb.toNativeUtf16(), f = file.toNativeUtf16(), p = params.toNativeUtf16();
  try {
    // > 32 = avviato; 5 (SE_ERR_ACCESSDENIED) = "No" alla richiesta di Windows
    final r = exec(0, v, f, p, nullptr, hidden ? 0 : 1);
    if (r > 32) return true;
    if (r == 5) return false;
    throw ProcessException(file, [params], 'ShellExecute ha risposto $r');
  } finally {
    malloc.free(v);
    malloc.free(f);
    malloc.free(p);
  }
}
