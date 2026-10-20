import '../data/app_state.dart';
import 'bank_bridge.dart';
import 'desktop.dart';
import 'lock.dart';
import 'notifications.dart';
import 'prices.dart';
import 'sync.dart';

/// Servizi globali creati all'avvio.
class Services {
  static late AppState app;
  static late SyncService sync;
  static late NotificationService notif;
  static late LockService lock;
  static late PriceService prices;
  static late BankBridge bank;
  static DesktopService? desktop;
}
