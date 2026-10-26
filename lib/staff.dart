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
  bool diagBusy = false, gpsOff = false;
  int locAcc = 0, fixAt = 0;

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
      setState(() { st = '${d['s'] ?? ''}'; stB = '${d['b'] ?? ''}'; stD = '${d['d'] ?? ''}'; unknown = d['loc'] == true; ssid = '${d['ssid'] ?? ''}'; gpsOff = d['gpsoff'] == true; locAcc = (d['acc'] as num?)?.toInt() ?? 0; fixAt = (d['fixat'] as num?)?.toInt() ?? 0; });
      if (unknown || gpsOff) { _diagnose(); } else if (hint.isNotEmpty) { setState(() => hint = ''); }
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
    if (me == null) {  // show the last known screen at once; fresh data replaces it a moment later
      try {
        final c1 = p.getString('me_cache'), c2 = p.getString('visits_cache');
        if (c1 != null && mounted) setState(() { me = jsonDecode(c1) as Map; if (c2 != null) visits = jsonDecode(c2) as List; });
      } catch (_) {}
    }
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
    if (r['ok'] == true) { await p.setString('me_cache', jsonEncode(r)); }
    if (v['ok'] == true) { await p.setString('visits_cache', jsonEncode(v['visits'])); }
    await _ensureTracking();
    if (running) _ensureGps();
  }

  Future<void> _ensureTracking() async {
    if (me == null) return;
    final branches = (me?['branches'] ?? []) as List;
    final p = await SharedPreferences.getInstance();
    // Latest token + branch/Wi-Fi list is saved every time so the background service always has it.
    await p.setString('cfg', jsonEncode({'token': Session.token, 'work': me?['work'], 'branches': [for (final b in branches) {'id': b['id'], 'name': b['name'], 'wifi': b['wifi']}]}));
    if (branches.isEmpty) { setState(() => permMsg = 'Owner ne abhi koi branch / Wi-Fi add nahi kiya.'); return; }
    if (running) { setState(() => permMsg = ''); return; }
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

  String get _locText {
    if (fixAt == 0) return 'Location: company time mein har 5 minute mein record hoti hai.';
    final mins = ((DateTime.now().millisecondsSinceEpoch - fixAt) / 60000).round();
    return 'Aakhri location: ±$locAcc m, $mins min pehle. (Company time mein har 5 minute mein record hoti hai.)';
  }

  String get _workText {
    final w = me?['work'];
    if (w is! Map || w['s'] == null || w['e'] == null) return '';
    String hm(num m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final mask = (w['d'] as num?)?.toInt() ?? 127;
    final days = mask == 127 ? 'roz' : [for (var i = 0; i < 7; i++) if (((mask >> i) & 1) == 1) names[i]].join(', ');
    return 'Company time: ${hm(w['s'])} - ${hm(w['e'])} ($days). Is ke ilawa koi record nahi hota.';
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
          if (_locText.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text(_locText, style: const TextStyle(color: Colors.grey))),
          if (unknown || gpsOff) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(gpsOff ? 'Phone ki Location (GPS) band hai.' : 'Wi-Fi ka naam nahi mil raha.', style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w600)),
            if (hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: const TextStyle(color: Colors.orangeAccent))),
            Row(children: [
              TextButton(onPressed: _ensureGps, child: const Text('Location on karo')),
              TextButton(onPressed: () async { await Permission.locationWhenInUse.request(); await Permission.locationAlways.request(); await openAppSettings(); }, child: const Text('App settings')),
            ]),
          ])),
          if (_workText.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_workText, style: const TextStyle(fontWeight: FontWeight.w600))),
          const Padding(padding: EdgeInsets.all(16), child: Text('Tracking automatic on hai. Branch ke Wi-Fi se connect hone par visit save hoti hai. Wi-Fi off/disconnect, mobile data, internet band ya phone off hone ka record bhi owner ko dikhta hai, app band ho tab bhi.\n\nPhone restart ke baad khud chalne ke liye: Settings > Apps > MartOps mein Autostart ON karo aur Battery ko Unrestricted rakho.', style: TextStyle(color: Colors.grey))),
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
