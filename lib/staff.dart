import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'presence_service.dart';

/// Staff ek baar login karta hai; tracking khud shuru hoti hai aur background mein chalti rehti hai
/// (app band ho ya phone restart ho). Staff ke paas band karne ya logout ka option nahi.
class StaffHome extends StatefulWidget {
  const StaffHome({super.key});
  @override
  State<StaffHome> createState() => _StaffHomeState();
}

class _StaffHomeState extends State<StaffHome> {
  Map? me;
  List duties = [];
  bool running = false, inStore = false, unknown = false, starting = false;
  String err = '', ssid = '', permMsg = '';

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onData);
    _load();
  }

  @override
  void dispose() { FlutterForegroundTask.removeTaskDataCallback(_onData); super.dispose(); }

  void _onData(Object d) {
    if (d is Map && mounted) setState(() { inStore = d['inStore'] == true; unknown = d['unknown'] == true; ssid = '${d['ssid'] ?? ''}'; });
  }

  Future<void> _load() async {
    final r = await Session.call('me');
    final du = await Session.call('myDuties');
    running = await FlutterForegroundTask.isRunningService;
    if (!mounted) return;
    setState(() {
      if (r['ok'] == true) { me = r; err = ''; } else { err = '${r['error']}'; }
      if (du['ok'] == true) duties = du['duties'];
    });
    await _ensureTracking();
  }

  Future<void> _ensureTracking() async {
    if (starting || me == null) return;
    final wifi = (me?['branch']?['wifi'] ?? []) as List;
    if (wifi.isEmpty) { setState(() => permMsg = 'Owner ne is branch ka Wi-Fi set nahi kiya.'); return; }
    // Latest token + Wi-Fi list hamesha save karo (owner Wi-Fi badle to background service ko naya mile).
    final p = await SharedPreferences.getInstance();
    await p.setString('cfg', jsonEncode({'token': Session.token, 'wifi': wifi}));
    if (running) { setState(() => permMsg = ''); return; }
    starting = true;
    try {
      if (!await Permission.locationWhenInUse.request().isGranted) {
        setState(() => permMsg = 'Location permission zaroori hai (Wi-Fi ka naam padhne ke liye). Neeche button dabao.');
        return;
      }
      await Permission.notification.request();
      await Permission.locationAlways.request(); // app band hone par bhi Wi-Fi naam padhne ke liye
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      await startPresence();
      if (mounted) setState(() { running = true; permMsg = ''; });
    } finally {
      starting = false;
    }
  }

  @override
  Widget build(BuildContext c) {
    final b = me?['branch'];
    return Scaffold(
      appBar: AppBar(title: Text(Session.companyName ?? 'MartOps')),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Salam, ${Session.name}', style: Theme.of(c).textTheme.headlineSmall),
        if (err.isNotEmpty) Text(err, style: const TextStyle(color: Colors.redAccent)),
        if (b != null) Text('${b['name']}, ${b['city']}  |  Shift ${b['shift']}'),
        const SizedBox(height: 16),
        if (running) ...[
          ListTile(
            leading: Icon(Icons.circle, color: inStore ? Colors.green : Colors.orange),
            title: Text(inStore ? 'Store Wi-Fi connected' : 'Store se bahar / Wi-Fi nahi'),
            subtitle: ssid.isNotEmpty && !unknown ? Text('Wi-Fi: $ssid') : null),
          if (unknown) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Wi-Fi ka naam nahi mil raha. Phone ki Location (GPS) on karo aur Wi-Fi se connect raho.', style: TextStyle(color: Colors.orangeAccent))),
          const Padding(padding: EdgeInsets.all(16), child: Text('Duty tracking automatic on hai. Store Wi-Fi se connect hote hi khud kaam karti hai, app band ho tab bhi.', style: TextStyle(color: Colors.grey))),
        ] else ...[
          if (permMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(permMsg, style: const TextStyle(color: Colors.orangeAccent))),
          FilledButton(onPressed: starting ? null : _ensureTracking, child: Text(starting ? 'Please wait...' : 'Tracking shuru karo (permission do)')),
        ],
        const SizedBox(height: 20),
        const Text('Aaj ki duties', style: TextStyle(fontWeight: FontWeight.w600)),
        for (final d in duties) CheckboxListTile(
          value: d['done'] == 1, title: Text('${d['aisle']}  ${d['task'] ?? ''}'),
          onChanged: (v) async { await Session.call('doneDuty', {'id': d['id'], 'done': v == true ? 1 : 0}); _load(); }),
        if (duties.isEmpty) const Text('Koi duty assign nahi.'),
      ])),
    );
  }
}
