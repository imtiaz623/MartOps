import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

const pingEvery = Duration(seconds: 15);  // local check (free, no server call)
const keepAlive = Duration(minutes: 5);   // server keep-alive while nothing changes
const gapAfter = Duration(minutes: 3);    // no tick for this long = phone off / app not running

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
      serviceId: 301, notificationTitle: 'Branch visit tracking on', notificationText: 'Check ho raha hai', callback: startCallback);
}

/// Every 15 s: works out the phone's state and queues a timestamped event when it changes.
/// States: BRANCH (branch Wi-Fi), OTHER (another Wi-Fi), MOBILE (mobile data, Wi-Fi off/disconnected),
/// NONET (no network), LOCOFF (Wi-Fi connected but name unreadable) and OFF (phone off / app stopped, found on restart).
/// Events are kept on the phone until the server confirms them, so nothing is lost while offline.
class PresenceHandler extends TaskHandler {
  DateTime lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastTry = DateTime.fromMillisecondsSinceEpoch(0);
  String? cand;
  int candCount = 0;
  int candSince = 0;
  String? lastNote;

  @override
  Future<void> onStart(DateTime ts, TaskStarter s) async { await onRepeatEvent(ts); }

  @override
  Future<void> onRepeatEvent(DateTime ts) async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final cfg = jsonDecode(p.getString('cfg') ?? '{}') as Map;
    final branches = (cfg['branches'] ?? []) as List;
    final now = DateTime.now().millisecondsSinceEpoch;
    final queue = (jsonDecode(p.getString('queue') ?? '[]') as List).toList();

    // 1) Was the service not running for a while? (phone switched off, battery dead, app force-stopped)
    final lastTick = p.getInt('tick');
    await p.setInt('tick', now);
    var reopen = false;
    if (lastTick != null && now - lastTick > gapAfter.inMilliseconds) {
      queue.add({'s': 'OFF', 'at': lastTick, 'until': now});
      reopen = true;
    }

    // 2) What is the phone connected to right now?
    final conn = await Connectivity().checkConnectivity();
    final hasWifi = conn.contains(ConnectivityResult.wifi);
    final hasMobile = conn.contains(ConnectivityResult.mobile);
    String s = 'NONET', b = '', d = '', ssidShown = '';
    if (hasWifi) {
      final info = NetworkInfo();
      final ssid = (await info.getWifiName())?.replaceAll('"', '').trim().toLowerCase();
      final bssid = (await info.getWifiBSSID())?.toLowerCase();
      final unknown = ssid == null || ssid.isEmpty || ssid.contains('unknown ssid');
      ssidShown = unknown ? '' : ssid;
      if (unknown) {
        s = 'LOCOFF';
      } else {
        for (final br in branches) {
          final wifi = ((br['wifi'] ?? []) as List).map((e) => e.toString().trim().toLowerCase()).toList();
          if (wifi.contains(ssid) || (bssid != null && wifi.contains(bssid))) { b = '${br['id']}'; break; }
        }
        if (b.isNotEmpty) { s = 'BRANCH'; } else { s = 'OTHER'; d = ssid; }
      }
    } else if (hasMobile) {
      s = 'MOBILE';
    }
    final key = s == 'BRANCH' ? 'BRANCH:$b' : (s == 'OTHER' ? 'OTHER:$d' : s);
    final cur = p.getString('cur');

    // 3) Queue a change only after 2 checks in a row (30 s) so a brief flicker is ignored; the event keeps its first-seen time.
    if (reopen) {
      queue.add({'s': s, 'b': b, 'd': d, 'at': now});
      await p.setString('cur', key);
      cand = null; candCount = 0;
    } else if (cur == key) {
      cand = null; candCount = 0;
    } else {
      if (cand == key) { candCount++; } else { cand = key; candCount = 1; candSince = now; }
      if (cur == null || candCount >= 2) {
        queue.add({'s': s, 'b': b, 'd': d, 'at': candSince});
        await p.setString('cur', key);
        cand = null; candCount = 0;
      }
    }
    await p.setString('queue', jsonEncode(queue));

    // 4) Send to the server (events first, otherwise a keep-alive). Failed sends stay queued.
    final due = queue.isNotEmpty || DateTime.now().difference(lastSent) >= keepAlive;
    if (due && DateTime.now().difference(lastTry).inSeconds >= 20) {
      lastTry = DateTime.now();
      final chunk = queue.take(150).toList();
      final r = await rawCall(cfg['token'], 'visits', {'events': chunk, 'ssid': ssidShown});
      if (r['ok'] == true) {
        lastSent = DateTime.now();
        await p.reload();
        final rest = (jsonDecode(p.getString('queue') ?? '[]') as List).toList();
        rest.removeRange(0, chunk.length > rest.length ? rest.length : chunk.length);
        await p.setString('queue', jsonEncode(rest));
      }
    }

    final note = s == 'LOCOFF' ? 'Wi-Fi ka naam nahi mil raha - Location (GPS) on karo' : 'Check ho raha hai';
    if (lastNote != note) {
      lastNote = note;
      FlutterForegroundTask.updateService(notificationText: note);
    }
    FlutterForegroundTask.sendDataToMain({'s': s, 'b': b, 'd': d, 'loc': s == 'LOCOFF', 'ssid': ssidShown});
  }

  @override
  Future<void> onDestroy(DateTime ts) async {}
}
