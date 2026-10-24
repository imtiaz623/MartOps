import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'main.dart';
import 'presence_service.dart';

class StaffHome extends StatefulWidget {
  const StaffHome({super.key});
  @override
  State<StaffHome> createState() => _StaffHomeState();
}

class _StaffHomeState extends State<StaffHome> {
  Map? me;
  List duties = [];
  bool running = false, inStore = false;
  String err = '';

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onData);
    _load();
  }

  @override
  void dispose() { FlutterForegroundTask.removeTaskDataCallback(_onData); super.dispose(); }

  void _onData(Object d) { if (d is Map && mounted) setState(() => inStore = d['inStore'] == true); }

  Future<void> _load() async {
    final r = await Session.call('me');
    final du = await Session.call('myDuties');
    running = await FlutterForegroundTask.isRunningService;
    if (!mounted) return;
    setState(() {
      if (r['ok'] == true) { me = r; err = ''; } else { err = '${r['error']}'; }
      if (du['ok'] == true) duties = du['duties'];
    });
  }

  Future<void> _start() async {
    final wifi = (me?['branch']?['wifi'] ?? []) as List;
    if (wifi.isEmpty) return _snack('Owner ne is branch ka Wi-Fi set nahi kiya.');
    if (!await Permission.locationWhenInUse.request().isGranted) return _snack('Location permission zaroori hai (Wi-Fi name padhne ke liye).');
    await Permission.notification.request();
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    final p = await SharedPreferences.getInstance();
    await p.setString('cfg', jsonEncode({'token': Session.token, 'wifi': wifi}));
    await startPresence();
    setState(() => running = true);
  }

  Future<void> _stop() async { await FlutterForegroundTask.stopService(); setState(() => running = false); }
  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext c) {
    final b = me?['branch'];
    return Scaffold(
      appBar: AppBar(title: Text(Session.companyName ?? 'MartOps'), actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => logout(c))]),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Salam, ${Session.name}', style: Theme.of(c).textTheme.headlineSmall),
        if (err.isNotEmpty) Text(err, style: const TextStyle(color: Colors.redAccent)),
        if (b != null) Text('${b['name']}, ${b['city']}  |  Shift ${b['shift']}'),
        const SizedBox(height: 16),
        if (running) ListTile(
          leading: Icon(Icons.circle, color: inStore ? Colors.green : Colors.orange),
          title: Text(inStore ? 'Store Wi-Fi connected' : 'Store se bahar / Wi-Fi nahi')),
        FilledButton(onPressed: running ? _stop : _start, child: Text(running ? 'Duty tracking band karo' : 'Duty tracking shuru karo')),
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
