import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:location/location.dart' as lc;
import 'package:permission_handler/permission_handler.dart';
import 'api.dart';

/// Step-by-step setup. Managers get a live checklist (each step shows done / not done and has a button).
/// Owners get the setup steps for the web panel.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});
  @override
  State<GuideScreen> createState() => _GuideState();
}

class _Step {
  final String key, title, desc, button;
  final Future<void> Function() action;
  const _Step(this.key, this.title, this.desc, this.button, this.action);
}

class _GuideState extends State<GuideScreen> with WidgetsBindingObserver {
  Map<String, bool> ok = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh(); // back from phone settings
  }

  Future<void> _refresh() async {
    final m = <String, bool>{};
    try { m['loc'] = await Permission.locationWhenInUse.status.isGranted; } catch (_) { m['loc'] = false; }
    try { m['always'] = await Permission.locationAlways.status.isGranted; } catch (_) { m['always'] = false; }
    try { m['gps'] = await Permission.locationWhenInUse.serviceStatus.isEnabled; } catch (_) { m['gps'] = false; }
    try { m['notif'] = await Permission.notification.status.isGranted; } catch (_) { m['notif'] = false; }
    try { m['battery'] = await FlutterForegroundTask.isIgnoringBatteryOptimizations; } catch (_) { m['battery'] = false; }
    if (mounted) setState(() => ok = m);
  }

  Future<void> _ask(Permission p) async {
    final s = await p.request();
    if (s.isPermanentlyDenied) await openAppSettings();
    await _refresh();
  }

  List<_Step> get _steps => [
        _Step('loc', '1. Location permission', 'Allow karo aur "Use precise location" chuno. Android Wi-Fi ka naam padhne ke liye ye maangta hai.', 'Allow karo', () => _ask(Permission.locationWhenInUse)),
        _Step('always', '2. "Allow all the time"', 'Location ko "Allow all the time" par rakho taake app band hone par bhi chale. Settings khulein to Location > Allow all the time chuno.', 'Allow karo', () => _ask(Permission.locationAlways)),
        _Step('gps', '3. Phone ki Location (GPS) on', 'Location band ho to Wi-Fi ka naam nahi milta aur position record nahi hoti.', 'GPS on karo', () async { try { await lc.Location().requestService(); } catch (_) {} await _refresh(); }),
        _Step('notif', '4. Notifications', 'Tracking chalne ka notification dikhta rahega. Isay allow karo.', 'Allow karo', () => _ask(Permission.notification)),
        _Step('battery', '5. Battery: Unrestricted', 'Taake phone ki battery bachat app ko band na kar de.', 'Allow karo', () async { try { await FlutterForegroundTask.requestIgnoreBatteryOptimization(); } catch (_) {} await _refresh(); }),
      ];

  Widget _managerBody(BuildContext c) {
    final steps = _steps;
    final done = steps.where((s) => ok[s.key] == true).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Manager setup guide', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('Ye steps ek baar karne hain. Is ke baad app khud chalti hai, app band ho ya phone restart ho.', style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 14),
      ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: done / steps.length, minHeight: 10)),
      const SizedBox(height: 4),
      Text('$done / ${steps.length} complete', style: const TextStyle(color: Colors.grey)),
      const SizedBox(height: 8),
      for (final s in steps)
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 14, backgroundColor: ok[s.key] == true ? Colors.green : Colors.orange, child: Icon(ok[s.key] == true ? Icons.check : Icons.priority_high, size: 16, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                Text(s.desc, style: const TextStyle(color: Colors.grey)),
                if (ok[s.key] != true) Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton.tonal(onPressed: s.action, child: Text(s.button))),
              ])),
            ]),
          ),
        ),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('6. Autostart (phone restart ke baad)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Kuch phones (Infinix, Tecno, Oppo, Vivo, Xiaomi) app ko khud start hone se rokte hain. Settings > Apps > MartOps mein "Autostart" ya "Auto-launch" ON karo.', style: TextStyle(color: Colors.grey)),
            Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton.tonal(onPressed: openAppSettings, child: const Text('App settings kholo'))),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Ho gaya')),
    ]);
  }

  Widget _ownerBody(BuildContext c) {
    const steps = [
      ['1. Branch aur Wi-Fi add karo', 'Web panel > "Branches and Wi-Fi" tab. Branch ka naam, location ka naam aur us branch ke Wi-Fi ke naam likho (bilkul waise jaise phone mein dikhte hain). Ek branch ke kai Wi-Fi ho sakte hain.'],
      ['2. Company time set karo', 'Web panel > Settings > Company time. Sirf isi time mein record hoga. Set na karo to poora din.'],
      ['3. Manager add karo', 'Web panel > "Managers" tab. Manager ID aur PIN sirf ek baar dikhti hai, manager ko de do.'],
      ['4. Manager ke phone mein app chalao', 'App install karke Login dabao. Company code, Manager ID aur PIN likho. App khud permissions ka guide dikhayegi.'],
      ['5. Unlock PIN (zaroori nahi)', 'Web panel > Settings > Unlock PIN. Manager PIN ke baghair logout nahi kar sakega.'],
      ['6. Report', 'Web panel > "Reports". Date chuno aur Excel, PDF, Text ya Image download karo.'],
    ];
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Owner setup guide', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('Poora setup web panel se hota hai. Neeche steps ek ek karke karo.', style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 8),
      for (final s in steps)
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s[0], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 4),
              Text(s[1], style: const TextStyle(color: Colors.grey)),
            ]),
          ),
        ),
      const SizedBox(height: 12),
      FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Samajh gaya')),
    ]);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Setup guide')),
        body: SafeArea(child: Session.role == 'owner' ? _ownerBody(c) : _managerBody(c)),
      );
}
