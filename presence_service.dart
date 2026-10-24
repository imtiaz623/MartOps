import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

const pingEvery = Duration(minutes: 1);    // local Wi-Fi check (free, no server call)
const keepAlive = Duration(minutes: 10);   // server keep-alive while nothing changes (saves Apps Script quota)

@pragma('vm:entry-point')
void startCallback() => FlutterForegroundTask.setTaskHandler(PresenceHandler());

Future<void> startPresence() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(channelId: 'presence', channelName: 'Branch visits'),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(pingEvery.inMilliseconds), autoRunOnBoot: true, allowWifiLock: true),
  );
  await FlutterForegroundTask.startService(
      serviceId: 301, notificationTitle: 'Branch visit tracking on', notificationText: 'Wi-Fi check ho raha hai', callback: startCallback);
}

/// Matches the phone's current Wi-Fi against every branch's Wi-Fi list.
/// A change (arrived at branch / left) is confirmed after 2 checks in a row, queued, and sent to the server when online.
class PresenceHandler extends TaskHandler {
  DateTime lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  String? cand;
  int candCount = 0;
  int candSince = 0;

  @override
  Future<void> onStart(DateTime ts, TaskStarter s) async { await onRepeatEvent(ts); }

  @override
  Future<void> onRepeatEvent(DateTime ts) async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final cfg = jsonDecode(p.getString('cfg') ?? '{}') as Map;
    final branches = (cfg['branches'] ?? []) as List;

    final info = NetworkInfo();
    final ssid = (await info.getWifiName())?.replaceAll('"', '').trim().toLowerCase();
    final unknown = ssid == null || ssid.isEmpty || ssid.contains('unknown ssid');
    final bssid = (await info.getWifiBSSID())?.toLowerCase();

    String match = '';
    for (final b in branches) {
      final wifi = ((b['wifi'] ?? []) as List).map((e) => e.toString().trim().toLowerCase()).toList();
      if ((ssid != null && wifi.contains(ssid)) || (bssid != null && wifi.contains(bssid))) { match = '${b['id']}'; break; }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final cur = p.getString('cur'); // null = first run
    var queue = (jsonDecode(p.getString('queue') ?? '[]') as List).toList();

    if (cur != null && match == cur) {
      cand = null; candCount = 0;
    } else {
      if (cand == match) { candCount++; } else { cand = match; candCount = 1; candSince = now; }
      if (cur == null || candCount >= 2) {
        if (!(cur == null && match.isEmpty)) queue.add({'b': match, 'at': candSince});
        await p.setString('cur', match);
        await p.setString('queue', jsonEncode(queue));
        cand = null; candCount = 0;
      }
    }

    final curNow = p.getString('cur') ?? '';
    if (queue.isNotEmpty || DateTime.now().difference(lastSent) >= keepAlive) {
      final r = await rawCall(cfg['token'], 'visits', {'events': queue, 'ssid': ssid ?? ''});
      if (r['ok'] == true) {
        lastSent = DateTime.now();
        await p.setString('queue', '[]'); // only forget events once the server has them
      }
    }
    FlutterForegroundTask.sendDataToMain({'cur': curNow, 'unknown': unknown, 'ssid': ssid ?? ''});
  }

  @override
  Future<void> onDestroy(DateTime ts) async {}
}
