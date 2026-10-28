import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:location/location.dart' as lc;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'guide.dart';
import 'main.dart' show logout;
import 'api.dart';
import 'presence_service.dart';

/// Manager screen. Login once; tracking starts by itself and keeps running in the background
/// (also after the app is closed or the phone restarts). The screen shows nothing but the tracking status:
/// no history, no details, no settings. (Admin exit: long-press the status and enter the owner's unlock PIN.)
class StaffHome extends StatefulWidget {
  const StaffHome({super.key});
  @override
  State<StaffHome> createState() => _StaffHomeState();
}

class _StaffHomeState extends State<StaffHome> {
  Map? me;
  bool running = false, locProblem = false, starting = false;
  String permMsg = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onData);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final r = await FlutterForegroundTask.isRunningService;
      if (mounted && r != running) setState(() => running = r);
      if (!r && mounted && !starting) { _tryRestart(); } // the service stopped: quietly bring it back
    });
    _boot();
  }

  @override
  void dispose() {
    _timer?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onData);
    super.dispose();
  }

  void _onData(Object d) {
    if (d is Map && mounted) {
      final bad = d['loc'] == true || d['gpsoff'] == true;
      if (bad != locProblem) setState(() => locProblem = bad);
    }
  }

  /// First time on this phone: walk the manager through the permissions once, then start tracking.
  Future<void> _boot() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('guide_seen') != true) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) { await Navigator.push(context, MaterialPageRoute(builder: (_) => const GuideScreen())); }
      await p.setBool('guide_seen', true);
    }
    _load();
  }

  /// Restarts the background service without any dialog (only if the manager already agreed and gave location permission).
  Future<void> _tryRestart() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool('disclosed2') != true || !(p.getString('cfg') ?? '').contains('"id"')) return;
      if (!await Permission.locationWhenInUse.isGranted) return;
      await startPresence();
      if (mounted) setState(() => running = true);
    } catch (_) {}
  }

  Future<void> _ensureGps() async {
    try {
      final l = lc.Location();
      if (!await l.serviceEnabled()) await l.requestService();
    } catch (_) {}
  }

  Future<void> _load() async {
    running = await FlutterForegroundTask.isRunningService;
    final p = await SharedPreferences.getInstance();
    // Fast start: use the saved branch/Wi-Fi list so tracking begins before the server replies.
    if (!running && (p.getString('cfg') ?? '').contains('"id"')) { await _startService(); }
    final r = await Session.call('me');
    running = await FlutterForegroundTask.isRunningService;
    if (!mounted) return;
    if (r['ok'] == true) { me = r; }
    setState(() {});
    await _ensureTracking();
    if (running) _ensureGps();
  }

  Future<void> _ensureTracking() async {
    if (me == null) return;
    final branches = (me?['branches'] ?? []) as List;
    final p = await SharedPreferences.getInstance();
    // Latest token + branch / Wi-Fi list + company time are saved every time so the background service always has them.
    await p.setString('cfg', jsonEncode({'token': Session.token, 'work': me?['work'], 'branches': [for (final b in branches) {'id': b['id'], 'name': b['name'], 'wifi': b['wifi']}]}));
    if (branches.isEmpty) { if (mounted) setState(() => permMsg = 'Owner ne abhi branch add nahi ki.'); return; }
    if (running) { if (mounted) setState(() => permMsg = ''); return; }
    await _startService();
  }

  /// Play Store "prominent disclosure": shown before the system location prompt, once.
  Future<bool> _disclosure() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('disclosed2') == true) return true;
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Location aur background use'),
        content: const SingleChildScrollView(child: Text(
            'MartOps uses your phone\'s precise location (GPS) and Wi-Fi name during the company working time set by your owner. About every 5 minutes, and whenever your status changes, the app saves your position (latitude, longitude, accuracy) with the time, so your company owner can see where you are and which branch you visited. Nothing is recorded outside company time.\n\n'
            'This also works in the background (with a notification), even when the app is closed. The owner of your company can see this record. It is not sold or used for ads.\n\n'
            'Urdu: Company time mein har 5 minute mein aur status badalne par app aap ki location (GPS) aur Wi-Fi ka naam save karti hai taake owner dekh sake aap kahan hain aur kis branch gaye. App band ho tab bhi chalta hai. Company time ke baad kuch record nahi hota.\n\n'
            'Agree dabane ke baad Android permission poochega. "Allow all the time" aur "Precise" chuno.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Agree')),
        ],
      ),
    );
    if (ok == true) { await p.setBool('disclosed2', true); return true; }
    return false;
  }

  Future<void> _startService() async {
    if (starting) return;
    starting = true;
    try {
      if (!await _disclosure()) {
        if (mounted) setState(() => permMsg = '"Agree" dabana zaroori hai.');
        return;
      }
      if (!await Permission.locationWhenInUse.request().isGranted) {
        if (mounted) setState(() => permMsg = 'Location permission zaroori hai.');
        return;
      }
      await _ensureGps();
      await Permission.notification.request();
      await Permission.locationAlways.request(); // app band hone par bhi chalne ke liye
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      await startPresence();
      if (mounted) setState(() { running = true; permMsg = ''; });
    } finally {
      starting = false;
    }
  }

  /// Logout / stopping tracking needs the unlock PIN (the owner's PIN, or the manager's own password if none is set).
  Future<void> _unlockAndLogout(BuildContext c) async {
    final ctl = TextEditingController();
    final pin = await showDialog<String>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('PIN darj karo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Logout ya tracking band karne ke liye owner ki Unlock PIN (ya PIN na ho to apna password) chahiye.'),
          TextField(controller: ctl, obscureText: true, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'PIN / password')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: const Text('OK'))],
      ),
    );
    if (pin == null || pin.isEmpty) return;
    final r = await Session.call('checkLockPin', {'pin': pin});
    if (!c.mounted) return;
    if (r['ok'] == true) {
      await logout(c);
    } else {
      final msg = {'wrong_pin': 'Galat PIN.', 'too_many_tries': 'Bohat galat koshish. 10 minute baad try karo.', 'network': 'Internet check karo.'}[r['error']] ?? '${r['error']}';
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext c) {
    final ok = running;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onLongPress: () => _unlockAndLogout(c),
                behavior: HitTestBehavior.opaque,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(ok ? Icons.check_circle : Icons.pause_circle_outline, size: 104, color: ok ? Colors.green : Colors.orange),
                  const SizedBox(height: 18),
                  Text(ok ? 'Tracking active' : 'Tracking band hai', textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  if (ok) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Shukriya', style: TextStyle(fontSize: 20, color: Colors.grey))),
                ]),
              ),
              if (!ok) ...[
                if (permMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(permMsg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.orangeAccent))),
                const SizedBox(height: 18),
                FilledButton(onPressed: starting ? null : _startService, child: Text(starting ? 'Please wait...' : 'Tracking shuru karo')),
              ],
              if (ok && locProblem) ...[
                const SizedBox(height: 22),
                const Text('Phone ki Location (GPS) on karo.', textAlign: TextAlign.center, style: TextStyle(color: Colors.orangeAccent)),
                TextButton(onPressed: _ensureGps, child: const Text('Location on karo')),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
