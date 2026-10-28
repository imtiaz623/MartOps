import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

const pingEvery = Duration(seconds: 10);  // local check (free, no server call)
const keepAlive = Duration(minutes: 5);   // server keep-alive while nothing changes
const gapAfter = Duration(minutes: 3);    // no tick for this long = phone off / app not running
const locEvery = Duration(minutes: 5);    // GPS position is saved this often during company time (and on every status change)
const _day = 86400000;

@pragma('vm:entry-point')
void startCallback() => FlutterForegroundTask.setTaskHandler(PresenceHandler());

Future<void> startPresence() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(channelId: 'presence', channelName: 'Branch visits'),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(pingEvery.inMilliseconds), autoRunOnBoot: true, autoRunOnMyPackageReplaced: true, allowWifiLock: true),
  );
  await FlutterForegroundTask.startService(
      serviceId: 301, notificationTitle: 'MartOps', notificationText: 'Tracking active', callback: startCallback);
}

// ---- company working time: {'s': start minute, 'e': end minute, 'd': day bit mask (Sun=1 ... Sat=64)}; null = always ----
bool _dayOn(Map w, DateTime d) {
  final mask = (w['d'] as num?)?.toInt() ?? 127;
  return ((mask >> (d.weekday % 7)) & 1) == 1;
}

/// Windows (start, end in ms) that begin on the day of [ref] or up to [back] days before it.
List<List<int>> _windows(DateTime ref, Map w, {int back = 1, int fwd = 0}) {
  final s = (w['s'] as num).toInt(), e = (w['e'] as num).toInt(), out = <List<int>>[];
  for (var k = -back; k <= fwd; k++) {
    final day = DateTime(ref.year, ref.month, ref.day).add(Duration(days: k, hours: 12)); // noon avoids DST edges
    final mid = DateTime(day.year, day.month, day.day);
    if (!_dayOn(w, mid)) continue;
    final st = mid.add(Duration(minutes: s)).millisecondsSinceEpoch;
    final en = mid.add(Duration(minutes: e)).millisecondsSinceEpoch + (e > s ? 0 : _day);
    out.add([st, en]);
  }
  return out;
}

bool inWindow(int ms, Map? w) {
  if (w == null || w['s'] == null || w['e'] == null) return true;
  for (final x in _windows(DateTime.fromMillisecondsSinceEpoch(ms), w)) { if (ms >= x[0] && ms < x[1]) return true; }
  return false;
}

/// End (ms) of the latest working window that finished at or before [ms].
int? lastWindowEnd(int ms, Map w) {
  int? best;
  for (final x in _windows(DateTime.fromMillisecondsSinceEpoch(ms), w, back: 9)) { if (x[1] <= ms && (best == null || x[1] > best)) best = x[1]; }
  return best;
}

/// Parts of [a, b] that fall inside working windows (used so "phone off" is only counted during company time).
List<List<int>> clipToWindows(int a, int b, Map? w) {
  if (w == null || w['s'] == null || w['e'] == null) return [[a, b]];
  final out = <List<int>>[];
  final days = ((b - a) ~/ _day).clamp(0, 14).toInt();
  for (final x in _windows(DateTime.fromMillisecondsSinceEpoch(b), w, back: days + 1)) {
    final lo = x[0] > a ? x[0] : a, hi = x[1] < b ? x[1] : b;
    if (hi > lo) out.add([lo, hi]);
  }
  out.sort((p, q) => p[0].compareTo(q[0]));
  return out;
}

/// Every 10 s: works out the phone's state and queues a timestamped event when it changes.
/// States: BRANCH (branch Wi-Fi), OTHER (another Wi-Fi), MOBILE (mobile data), NONET (no network),
/// LOCOFF (Wi-Fi connected but name unreadable), OFF (phone off / app stopped, found on restart),
/// OFFDUTY (outside company time: nothing is checked or recorded).
/// Events stay on the phone until the server confirms them, so nothing is lost while offline.
class PresenceHandler extends TaskHandler {
  DateTime lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastTry = DateTime.fromMillisecondsSinceEpoch(0);
  String? cand;
  int candCount = 0;
  int candSince = 0;
  String? lastNote;
  bool busy = false, locBusy = false, gpsOff = false;
  int lastLocAt = 0, lastFixAt = 0;
  double lastFixAcc = 0;

  @override
  Future<void> onStart(DateTime ts, TaskStarter s) async { await onRepeatEvent(ts); }

  @override
  Future<void> onRepeatEvent(DateTime ts) async {
    if (busy) return;
    busy = true;
    try { await _tick(); } finally { busy = false; }
  }

  Future<void> _tick() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final cfg = jsonDecode(p.getString('cfg') ?? '{}') as Map;
    final branches = (cfg['branches'] ?? []) as List;
    final Map? work = cfg['work'] is Map ? cfg['work'] as Map : null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final queue = (jsonDecode(p.getString('queue') ?? '[]') as List).toList();
    final inW = inWindow(now, work);

    // 1) Was the service not running for a while? (phone switched off, battery dead, app force-stopped)
    final lastTick = p.getInt('tick');
    await p.setInt('tick', now);
    var changed = false;
    var fresh = false; // phone just came back: take the current state immediately
    if (lastTick != null && now - lastTick > gapAfter.inMilliseconds) {
      for (final seg in clipToWindows(lastTick, now, work)) { queue.add({'s': 'OFF', 'at': seg[0], 'until': seg[1]}); }
      fresh = true;
    }

    String s = 'NONET', b = '', d = '', ssidShown = '';
    final cur = p.getString('cur');
    if (!inW) {
      // 2a) Outside company time: stop recording. Close the open record at the end of working time.
      s = 'OFFDUTY';
      if (cur != 'OFFDUTY') {
        final end = lastWindowEnd(now, work!) ?? now;
        queue.add({'s': 'OFFDUTY', 'at': end > now ? now : end});
        await p.setString('cur', 'OFFDUTY');
      }
      cand = null; candCount = 0;
    } else {
      // 2b) Inside company time: what is the phone connected to?
      final conn = await Connectivity().checkConnectivity();
      final hasWifi = conn.contains(ConnectivityResult.wifi);
      final hasMobile = conn.contains(ConnectivityResult.mobile);
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
      // 3) Queue a change after 2 checks in a row (20 s) so a brief flicker is ignored; it keeps its first-seen time.
      //    Right after start-up / company time begins / phone comes back, the state is taken at once.
      if (fresh || cur == 'OFFDUTY' || cur == null) {
        queue.add({'s': s, 'b': b, 'd': d, 'at': now});
        changed = true;
        await p.setString('cur', key);
        cand = null; candCount = 0;
      } else if (cur == key) {
        cand = null; candCount = 0;
      } else {
        if (cand == key) { candCount++; } else { cand = key; candCount = 1; candSince = now; }
        if (candCount >= 2) {
          queue.add({'s': s, 'b': b, 'd': d, 'at': candSince});
          changed = true;
          await p.setString('cur', key);
          cand = null; candCount = 0;
        }
      }
    }
    await p.setString('queue', jsonEncode(queue));
    if (inW && (changed || now - lastLocAt >= locEvery.inMilliseconds) && !locBusy) { unawaited(_locate(p, s)); }

    // 4) Send to the server (events first, otherwise a keep-alive during company time). Failed sends stay queued.
    final lq = (jsonDecode(p.getString('lq') ?? '[]') as List).toList();
    final due = queue.isNotEmpty || lq.isNotEmpty || (inW && DateTime.now().difference(lastSent) >= keepAlive);
    if (due && DateTime.now().difference(lastTry).inSeconds >= 15) {
      lastTry = DateTime.now();
      final chunk = queue.take(150).toList();
      final lchunk = lq.take(150).toList();
      final r = await rawCall(cfg['token'], 'visits', {'events': chunk, 'locs': lchunk, 'ssid': ssidShown});
      if (r['ok'] == true) {
        lastSent = DateTime.now();
        await p.reload();
        final rest = (jsonDecode(p.getString('queue') ?? '[]') as List).toList();
        rest.removeRange(0, chunk.length > rest.length ? rest.length : chunk.length);
        await p.setString('queue', jsonEncode(rest));
        final lrest = (jsonDecode(p.getString('lq') ?? '[]') as List).toList();
        lrest.removeRange(0, lchunk.length > lrest.length ? lrest.length : lchunk.length);
        await p.setString('lq', jsonEncode(lrest));
        // The server sends the latest company time and branch / Wi-Fi list, so owner changes reach the phone by themselves.
        if (r['branches'] is List) { cfg['branches'] = r['branches']; }
        cfg['work'] = r['work'];
        await p.setString('cfg', jsonEncode(cfg));
      }
    }

    final note = (s == 'LOCOFF' || gpsOff) ? 'Location (GPS) on karo' : 'Tracking active';
    if (lastNote != note) {
      lastNote = note;
      FlutterForegroundTask.updateService(notificationText: note);
    }
    FlutterForegroundTask.sendDataToMain({'s': s, 'b': b, 'd': d, 'loc': s == 'LOCOFF', 'ssid': ssidShown, 'gpsoff': gpsOff, 'acc': lastFixAcc.round(), 'fixat': lastFixAt});
  }

  /// Saves one GPS position (best of a few readings, up to 25 s) so the owner can see where the manager is.
  Future<void> _locate(SharedPreferences p, String s) async {
    if (locBusy) return;
    locBusy = true;
    lastLocAt = DateTime.now().millisecondsSinceEpoch;
    try {
      Map<String, dynamic> rec;
      if (!await Geolocator.isLocationServiceEnabled()) {
        gpsOff = true;
        rec = {'at': lastLocAt, 'off': 1, 's': s};
      } else {
        gpsOff = false;
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
          rec = {'at': lastLocAt, 'err': 'no permission', 's': s};
        } else {
          final fix = await _bestFix();
          if (fix == null) {
            rec = {'at': lastLocAt, 'err': 'no fix', 's': s};
          } else {
            lastFixAt = fix.timestamp.millisecondsSinceEpoch;
            lastFixAcc = fix.accuracy;
            rec = {'at': lastFixAt, 'lat': fix.latitude, 'lng': fix.longitude, 'acc': fix.accuracy, 'mock': fix.isMocked, 's': s};
          }
        }
      }
      await p.reload();
      final lq = (jsonDecode(p.getString('lq') ?? '[]') as List).toList();
      lq.add(rec);
      if (lq.length > 2000) lq.removeRange(0, lq.length - 2000);
      await p.setString('lq', jsonEncode(lq));
    } catch (_) {
    } finally {
      locBusy = false;
    }
  }

  Future<Position?> _bestFix() async {
    Position? best;
    StreamSubscription<Position>? sub;
    try {
      sub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0))
          .listen((x) { if (best == null || x.accuracy < best!.accuracy) best = x; }, onError: (_) {});
      var waited = 0;
      while (waited < 25000 && (best == null || best!.accuracy > 20)) {
        await Future.delayed(const Duration(milliseconds: 500));
        waited += 500;
      }
    } catch (_) {
    } finally {
      await sub?.cancel();
    }
    if (best == null) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && DateTime.now().difference(last.timestamp).inMinutes < 3) best = last;
      } catch (_) {}
    }
    return best;
  }

  @override
  Future<void> onDestroy(DateTime ts) async {}
}
