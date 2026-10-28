import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:location/location.dart' as lc;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'about.dart';
import 'guide.dart';
import 'main.dart' show logout;
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
    _boot();
  }

  @override
  void dispose() { FlutterForegroundTask.removeTaskDataCallback(_onData); super.dispose(); }

  /// First time on this phone: walk the manager through the setup, then start tracking.
  Future<void> _boot() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('guide_seen') != true) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) { await Navigator.push(context, MaterialPageRoute(builder: (_) => const GuideScreen())); }
      await p.setBool('guide_seen', true);
    }
    _load();
  }

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

  Color get _heroColor => st == 'BRANCH' ? Colors.green : (st == 'NONET' || gpsOff) ? Colors.redAccent : st == 'OFFDUTY' ? Colors.blueGrey : Colors.orange;
  IconData get _heroIcon => st == 'BRANCH' ? Icons.location_on : st == 'OFFDUTY' ? Icons.nightlight_round : st == 'MOBILE' ? Icons.signal_cellular_alt : st == 'NONET' ? Icons.wifi_off : st == 'OTHER' ? Icons.wifi : Icons.sync;

  Widget _card(Widget child, {Color? color}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color ?? const Color(0xFF211F2B), borderRadius: BorderRadius.circular(20)),
        child: child,
      );

  @override
  Widget build(BuildContext c) {
    final here = _where;
    final col = _heroColor;
    return Scaffold(
      appBar: AppBar(title: Text(Session.companyName ?? 'MartOps'), actions: [
        IconButton(icon: const Icon(Icons.menu_book_outlined), tooltip: 'Setup guide', onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const GuideScreen()))),
        IconButton(icon: const Icon(Icons.info_outline), tooltip: 'About / Help', onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const AboutScreen()))),
        IconButton(icon: const Icon(Icons.lock_outline), tooltip: 'Logout / Tracking band (PIN)', onPressed: () => _unlockAndLogout(c)),
      ]),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Salam, ${Session.name}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(err, style: const TextStyle(color: Colors.redAccent))),
        const SizedBox(height: 14),
        if (running) ...[
          Container(
            padding: const EdgeInsets.all(18),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: LinearGradient(colors: [col.withAlpha(110), col.withAlpha(30)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: Row(children: [
              CircleAvatar(radius: 28, backgroundColor: col, child: Icon(_heroIcon, color: Colors.white, size: 30)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st.isEmpty ? 'Check ho raha hai...' : st == 'BRANCH' ? 'Abhi: $here' : stLabel(st, detail: stD), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                if (ssid.isNotEmpty && !unknown) Padding(padding: const EdgeInsets.only(top: 2), child: Text('Wi-Fi: $ssid', style: const TextStyle(color: Colors.white70))),
              ])),
            ]),
          ),
          if (_workText.isNotEmpty) _card(Row(children: [const Icon(Icons.schedule, size: 20), const SizedBox(width: 10), Expanded(child: Text(_workText))])),
          if (_locText.isNotEmpty) _card(Row(children: [const Icon(Icons.my_location, size: 20), const SizedBox(width: 10), Expanded(child: Text(_locText, style: const TextStyle(color: Colors.white70)))])),
          if (unknown || gpsOff)
            _card(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(gpsOff ? 'Phone ki Location (GPS) band hai.' : 'Wi-Fi ka naam nahi mil raha.', style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w700)),
                if (hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: const TextStyle(color: Colors.orangeAccent))),
                Row(children: [
                  TextButton(onPressed: _ensureGps, child: const Text('Location on karo')),
                  TextButton(onPressed: () async { await Permission.locationWhenInUse.request(); await Permission.locationAlways.request(); await openAppSettings(); }, child: const Text('App settings')),
                ]),
              ]),
              color: const Color(0xFF3A2A12),
            ),
          _card(const Text('Tracking automatic on hai. Branch ke Wi-Fi se connect hone par visit save hoti hai. Wi-Fi off/disconnect, mobile data, internet band ya phone off hone ka record bhi owner ko dikhta hai, app band ho tab bhi.\n\nWi-Fi, Location ya Data off karoge to owner ko record mein dikhega.\n\nPhone restart ke baad khud chalne ke liye: Settings > Apps > MartOps mein Autostart ON karo aur Battery ko Unrestricted rakho.', style: TextStyle(color: Colors.white60))),
        ] else ...[
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Tracking abhi band hai', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (permMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(permMsg, style: const TextStyle(color: Colors.orangeAccent))),
            const SizedBox(height: 10),
            FilledButton(onPressed: starting ? null : _startService, child: Text(starting ? 'Please wait...' : 'Tracking shuru karo (permission do)')),
            TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const GuideScreen())), child: const Text('Setup guide kholo')),
          ])),
        ],
        const SizedBox(height: 8),
        const Padding(padding: EdgeInsets.only(left: 4, bottom: 6), child: Text('Meri recent activity', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        _card(visits.isEmpty
            ? const Text('Abhi koi activity nahi.')
            : Column(children: [
                for (final v in visits.take(30))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(v['state'] == 'BRANCH' ? Icons.location_on : Icons.circle, size: 18, color: v['state'] == 'BRANCH' ? Colors.green : Colors.orange),
                    title: Text(v['state'] == 'BRANCH' ? '${v['branchName']}${'${v['city']}'.isEmpty ? '' : ', ${v['city']}'}' : stLabel(v['state'], detail: '${v['detail'] ?? ''}')),
                    subtitle: Text(v['left'] == '' ? '${fmtT(v['arrived'])}  (abhi)' : '${fmtT(v['arrived'])} - ${fmtT(v['left'])}   ${v['minutes']} min'),
                  ),
              ])),
      ])),
    );
  }
}
