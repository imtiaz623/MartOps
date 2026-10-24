import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  String err = '', ssid = '', permMsg = '', cur = '';

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onData);
    _load();
  }

  @override
  void dispose() { FlutterForegroundTask.removeTaskDataCallback(_onData); super.dispose(); }

  void _onData(Object d) {
    if (d is Map && mounted) setState(() { cur = '${d['cur'] ?? ''}'; unknown = d['unknown'] == true; ssid = '${d['ssid'] ?? ''}'; });
  }

  Future<void> _load() async {
    final r = await Session.call('me');
    final v = await Session.call('myVisits');
    running = await FlutterForegroundTask.isRunningService;
    if (!mounted) return;
    setState(() {
      if (r['ok'] == true) { me = r; err = ''; } else { err = '${r['error']}'; }
      if (v['ok'] == true) visits = v['visits'];
    });
    await _ensureTracking();
  }

  Future<void> _ensureTracking() async {
    if (starting || me == null) return;
    final branches = (me?['branches'] ?? []) as List;
    final p = await SharedPreferences.getInstance();
    // Latest token + branch/Wi-Fi list is saved every time so the background service always has it.
    await p.setString('cfg', jsonEncode({'token': Session.token, 'branches': [for (final b in branches) {'id': b['id'], 'name': b['name'], 'wifi': b['wifi']}]}));
    if (branches.isEmpty) { setState(() => permMsg = 'Owner ne abhi koi branch / Wi-Fi add nahi kiya.'); return; }
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

  String get _where {
    final bs = (me?['branches'] ?? []) as List;
    for (final b in bs) { if ('${b['id']}' == cur) return '${b['name']}${'${b['city']}'.isEmpty ? '' : ', ${b['city']}'}'; }
    return '';
  }

  @override
  Widget build(BuildContext c) {
    final here = _where;
    return Scaffold(
      appBar: AppBar(title: Text(Session.companyName ?? 'MartOps')),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Salam, ${Session.name}', style: Theme.of(c).textTheme.headlineSmall),
        if (err.isNotEmpty) Text(err, style: const TextStyle(color: Colors.redAccent)),
        const SizedBox(height: 12),
        if (running) ...[
          ListTile(
            leading: Icon(Icons.circle, color: here.isNotEmpty ? Colors.green : Colors.orange),
            title: Text(here.isNotEmpty ? 'Abhi: $here' : 'Kisi branch ke Wi-Fi se connected nahi'),
            subtitle: ssid.isNotEmpty && !unknown ? Text('Wi-Fi: $ssid') : null),
          if (unknown) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Wi-Fi ka naam nahi mil raha. Phone ki Location (GPS) on karo aur Wi-Fi se connect raho.', style: TextStyle(color: Colors.orangeAccent))),
          const Padding(padding: EdgeInsets.all(16), child: Text('Branch visit tracking automatic on hai. Jis branch ke Wi-Fi se connect hoge, wo khud save hoga, app band ho tab bhi.', style: TextStyle(color: Colors.grey))),
        ] else ...[
          if (permMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(permMsg, style: const TextStyle(color: Colors.orangeAccent))),
          FilledButton(onPressed: starting ? null : _ensureTracking, child: Text(starting ? 'Please wait...' : 'Tracking shuru karo (permission do)')),
        ],
        const SizedBox(height: 20),
        const Text('Meri recent branch visits', style: TextStyle(fontWeight: FontWeight.w600)),
        for (final v in visits) ListTile(
          dense: true,
          title: Text('${v['branchName']}${'${v['city']}'.isEmpty ? '' : ', ${v['city']}'}'),
          subtitle: Text(v['left'] == '' ? '${fmtT(v['arrived'])}  (abhi yahan)' : '${fmtT(v['arrived'])} - ${fmtT(v['left'])}   ${v['minutes']} min')),
        if (visits.isEmpty) const Text('Abhi koi visit nahi.'),
      ])),
    );
  }
}
