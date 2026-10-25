import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:location/location.dart' as lc;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'about.dart';
import 'api.dart';
import 'presence_service.dart';

/// Manager screen. Login once; tracking starts by itself and keeps running in the background.
/// It records which branch (by Wi-Fi) the manager is at. No stop or logout button.
class StaffHome extends StatefulWidget {
  const StaffHome({super.key});
  @override
  State<StaffHome> createState() => _StaffHomeState();
}

class _StaffHomeState extends State<StaffHome> {
  Map? me;
  List visits = [];
  bool running = false, unknown = false, starting = false;
  String err = '', ssid = '', permMsg = '', st = '', stB = '', stD = '', hint = '';
  bool diagBusy = false;

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onData);
    _load();
  }

  @override
  void dispose() { FlutterForegroundTask.removeTaskDataCallback(_onData); super.dispose(); }

  void _onData(Object d) {
    if (d is Map && mounted) {
      setState(() { st = '${d['s'] ?? ''}'; stB = '${d['b'] ?? ''}'; stD = '${d['d'] ?? ''}'; unknown = d['loc'] == true; ssid = '${d['ssid'] ?? ''}'; });
      if (unknown) { _diagnose(); } else if (hint.isNotEmpty) { setState(() => hint = ''); }
    }
  }

  /// Tells the manager exactly why the Wi-Fi name can't be read.
  Future<void> _diagnose() async {
    if (diagBusy) return;
    diagBusy = true;
    final perm = await Permission.locationWhenInUse.status.isGranted;
    final gps = await Permission.locationWhenInUse.serviceStatus.isEnabled;
    final always = await Permission.locationAlways.status.isGranted;
    diagBusy = false;
    if (!mounted) return;
    setState(() => hint = !perm
        ? 'Location permission band hai. Neeche button se App settings kholo > Permissions > Location > "Allow all the time" aur "Use precise location" on karo.'
        : !gps
            ? 'Phone ki Location (GPS) band hai. Screen ke upar se neeche kheench kar Location on karo. Bina Location ke Android Wi-Fi ka naam nahi dikhata.'
            : !always
                ? 'Location "Allow all the time" aur "Use precise location" karo (App settings > Permissions > Location).'
                : 'Phone Wi-Fi se connected hona chahiye. Connected ho to Location precise on hai ya nahi check karo.');
  }

  /// Android can't switch GPS on silently; this shows the one-tap system dialog "Turn on location".
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
    final v = await Session.call('myVisits');
    running = await FlutterForegroundTask.isRunningService;
    if (!mounted) return;
    setState(() {
      if (r['ok'] == true) { me = r; err = ''; } else { err = '${r['error']}'; }
      if (v['ok'] == true) visits = v['visits'];
    });
    await _ensureTracking();
    if (running) _ensureGps();
  }

  Future<void> _ensureTracking() async {
    if (me == null) return;
    final branches = (me?['branches'] ?? []) as List;
    final p = await SharedPreferences.getInstance();
    // Latest token + branch/Wi-Fi list is saved every time so the background service always has it.
    await p.setString('cfg', jsonEncode({'token': Session.token, 'branches': [for (final b in branches) {'id': b['id'], 'name': b['name'], 'wifi': b['wifi']}]}));
    if (branches.isEmpty) { setState(() => permMsg = 'Owner ne abhi koi branch / Wi-Fi add nahi kiya.'); return; }
    if (running) { setState(() => permMsg = ''); return; }
    await _startService();
  }

  /// Play Store "prominent disclosure": shown before the system location prompt, once.
  Future<bool> _disclosure() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('disclosed') == true) return true;
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Location aur background use'),
        content: const SingleChildScrollView(child: Text(
            'MartOps needs the Location permission only because Android requires it to read the name of the Wi-Fi network you are connected to. The app does not read or save your GPS position.\n\n'
            'The app also checks the Wi-Fi name in the background (with a notification), even when the app is closed, so your visits to company branches are recorded automatically: which branch, arrival time and departure time. Your company owner can see this record.\n\n'
            'Urdu: App sirf Wi-Fi ka naam padhne ke liye Location maangti hai, aap ki GPS position save nahi karti. App band hone par bhi branch ke Wi-Fi se connect hone ka record (kab aaye, kab gaye) aap ke owner ko dikhta hai.\n\n'
            'Agree dabane ke baad Android permission poochega. "Allow all the time" aur "Precise" chuno.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Agree')),
        ],
      ),
    );
    if (ok == true) { await p.setBool('disclosed', true); return true; }
    return false;
  }

  Future<void> _startService() async {
    if (starting) return;
    starting = true;
    try {
      if (!await _disclosure()) {
        if (mounted) setState(() => permMsg = 'Tracking ke liye "Agree" zaroori hai. Neeche button dabao.');
        return;
      }
      if (!await Permission.locationWhenInUse.request().isGranted) {
        if (mounted) setState(() => permMsg = 'Location permission zaroori hai (Wi-Fi ka naam padhne ke liye). Neeche button dabao.');
        return;
      }
      await _ensureGps();
      await Permission.notification.request();
      await Permission.locationAlways.request(); // app band hone par bhi Wi-Fi naam padhne ke liye
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      await startPresence();
      if (mounted) setState(() { running = true; permMsg = ''; });
    } finally {
      starting = false;
    }
  }

  String get _where {
    final bs = (me?['branches'] ?? []) as List;
    final id = st == 'BRANCH' ? stB : '';
    for (final b in bs) { if ('${b['id']}' == id) return '${b['name']}${'${b['city']}'.isEmpty ? '' : ', ${b['city']}'}'; }
    return '';
  }

  @override
  Widget build(BuildContext c) {
    final here = _where;
    return Scaffold(
      appBar: AppBar(title: Text(Session.companyName ?? 'MartOps'), actions: [IconButton(icon: const Icon(Icons.info_outline), tooltip: 'About / Help', onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const AboutScreen())))]),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Salam, ${Session.name}', style: Theme.of(c).textTheme.headlineSmall),
        if (err.isNotEmpty) Text(err, style: const TextStyle(color: Colors.redAccent)),
        const SizedBox(height: 12),
        if (running) ...[
          ListTile(
            leading: Icon(Icons.circle, color: st == 'BRANCH' ? Colors.green : (st == 'NONET' ? Colors.redAccent : Colors.orange)),
            title: Text(st.isEmpty ? 'Check ho raha hai...' : st == 'BRANCH' ? 'Abhi: $here' : stLabel(st, detail: stD)),
            subtitle: ssid.isNotEmpty && !unknown ? Text('Wi-Fi: $ssid') : null),
          if (unknown) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Wi-Fi ka naam nahi mil raha.', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w600)),
            if (hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: const TextStyle(color: Colors.orangeAccent))),
            Row(children: [
              TextButton(onPressed: _ensureGps, child: const Text('Location on karo')),
              TextButton(onPressed: () async { await Permission.locationWhenInUse.request(); await Permission.locationAlways.request(); await openAppSettings(); }, child: const Text('App settings')),
            ]),
          ])),
          const Padding(padding: EdgeInsets.all(16), child: Text('Tracking automatic on hai. Branch ke Wi-Fi se connect hone par visit save hoti hai. Wi-Fi off/disconnect, mobile data, internet band ya phone off hone ka record bhi owner ko dikhta hai, app band ho tab bhi.', style: TextStyle(color: Colors.grey))),
        ] else ...[
          if (permMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(permMsg, style: const TextStyle(color: Colors.orangeAccent))),
          FilledButton(onPressed: starting ? null : _startService, child: Text(starting ? 'Please wait...' : 'Tracking shuru karo (permission do)')),
        ],
        const SizedBox(height: 20),
        const Text('Meri recent activity', style: TextStyle(fontWeight: FontWeight.w600)),
        for (final v in visits) ListTile(
          dense: true,
          title: Text(v['state'] == 'BRANCH' ? '${v['branchName']}${'${v['city']}'.isEmpty ? '' : ', ${v['city']}'}' : stLabel(v['state'], detail: '${v['detail'] ?? ''}')),
          subtitle: Text(v['left'] == '' ? '${fmtT(v['arrived'])}  (abhi)' : '${fmtT(v['arrived'])} - ${fmtT(v['left'])}   ${v['minutes']} min')),
        if (visits.isEmpty) const Text('Abhi koi visit nahi.'),
      ])),
    );
  }
}
