import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

const pingEvery = Duration(minutes: 3);      // local Wi-Fi check
const keepAlive = Duration(minutes: 10);     // server heartbeat while state is unchanged (saves Apps Script quota)

@pragma('vm:entry-point')
void startCallback() => FlutterForegroundTask.setTaskHandler(PresenceHandler());

Future<void> startPresence() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(channelId: 'presence', channelName: 'Store presence'),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(pingEvery.inMilliseconds), autoRunOnBoot: true, allowWifiLock: true),
  );
  await FlutterForegroundTask.startService(
      serviceId: 301, notificationTitle: 'Duty tracking on', notificationText: 'Store Wi-Fi check ho raha hai', callback: startCallback);
}

class PresenceHandler extends TaskHandler {
  bool? last;
  DateTime lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<void> onStart(DateTime ts, TaskStarter s) async {}

  @override
  Future<void> onRepeatEvent(DateTime ts) async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final cfg = jsonDecode(p.getString('cfg') ?? '{}') as Map;
    final allowed = ((cfg['wifi'] ?? []) as List).map((e) => e.toString().toLowerCase()).toList();

    final info = NetworkInfo();
    final ssid = (await info.getWifiName())?.replaceAll('"', '').toLowerCase();
    final bssid = (await info.getWifiBSSID())?.toLowerCase();
    // Connected to ANY of the (up to 4) authorized branch networks => in store.
    final inStore = (ssid != null && allowed.contains(ssid)) || (bssid != null && allowed.contains(bssid));

    int? leftAt = p.getInt('leftAt');
    if (!inStore) { leftAt ??= DateTime.now().millisecondsSinceEpoch; await p.setInt('leftAt', leftAt); }

    final changed = last != inStore;
    if (changed || DateTime.now().difference(lastSent) >= keepAlive || leftAt != null && inStore) {
      final r = await rawCall(cfg['token'], 'heartbeat', {'connected': inStore, 'leftAt': leftAt, 'ssid': ssid ?? ''});
      if (r['ok'] == true) {
        lastSent = DateTime.now();
        last = inStore;
        if (inStore) await p.remove('leftAt');  // only forget the out-time once the server has logged it
      }
    }
    FlutterForegroundTask.sendDataToMain({'inStore': inStore});
  }

  @override
  Future<void> onDestroy(DateTime ts) async {}
}
