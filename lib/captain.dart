import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'main.dart';

class CaptainHome extends StatefulWidget {
  const CaptainHome({super.key});
  @override
  State<CaptainHome> createState() => _CaptainHomeState();
}

class _CaptainHomeState extends State<CaptainHome> {
  int tab = 0;
  List staff = [], duties = [];
  String err = '';
  Timer? t;

  @override
  void initState() {
    super.initState();
    load();
    t = Timer.periodic(const Duration(seconds: 30), (_) => load());
  }

  @override
  void dispose() { t?.cancel(); super.dispose(); }

  Future<void> load() async {
    final r = await Session.call('team');
    if (!mounted) return;
    setState(() {
      if (r['ok'] == true) { staff = r['staff']; duties = r['duties']; err = ''; } else { err = '${r['error']}'; }
    });
  }

  Future<void> addStaff() async {
    final n = TextEditingController(), p = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Naya staff'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: n, decoration: const InputDecoration(labelText: 'Naam (Imtiaz Ali)')),
        TextField(controller: p, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create'))],
    ));
    if (ok != true || n.text.trim().isEmpty) return;
    final r = await Session.call('addUser', {'name': n.text.trim(), 'phone': p.text});
    if (!mounted) return;
    if (r['ok'] == true) {
      await showDialog(context: context, builder: (_) => AlertDialog(
        title: const Text('Staff ban gaya'),
        content: Text('Company code: ${Session.companyCode}\nID: ${r['userId']}\nPIN: ${r['pin']}\n\nYe sirf ek dafa dikhta hai, staff ko de do.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
      load();
    } else { _snack('${r['error']}'); }
  }

  Future<void> assign() async {
    if (staff.isEmpty) return _snack('Pehle staff banao.');
    String? who = staff.first['userId'];
    final a = TextEditingController(), k = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: const Text('Duty assign karo'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButton<String>(isExpanded: true, value: who, items: [for (final s in staff) DropdownMenuItem(value: s['userId'] as String, child: Text('${s['name']}'))], onChanged: (v) => set(() => who = v)),
        TextField(controller: a, decoration: const InputDecoration(labelText: 'Aisle / shelf (Aisle 3)')),
        TextField(controller: k, decoration: const InputDecoration(labelText: 'Kaam (restock, cleaning...)')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Assign'))],
    )));
    if (ok != true || a.text.trim().isEmpty) return;
    final r = await Session.call('assignDuty', {'staff': who, 'aisle': a.text.trim(), 'task': k.text.trim()});
    if (r['ok'] == true) { load(); } else { _snack('${r['error']}'); }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Color _col(String s) => s == 'CONNECTED' ? Colors.green : s == 'NO_DATA' ? Colors.grey : Colors.orange;
  String _lbl(Map s) => s['status'] == 'CONNECTED' ? 'CONNECTED' : s['status'] == 'NO_DATA' ? 'Tracking start nahi' : 'DISCONNECTED  ${s['outMin']} min${s['outMin'] > 15 ? '  (ALERT)' : ''}';

  @override
  Widget build(BuildContext c) {
    final pages = [
      RefreshIndicator(onRefresh: load, child: ListView(children: [
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(err)),
        for (final s in staff) ListTile(
          leading: Icon(Icons.circle, size: 14, color: _col(s['status'])),
          title: Text('${s['name']}'), subtitle: Text(_lbl(s)),
          trailing: Text('${s['userId']}')),
        if (staff.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Abhi koi staff nahi. "Staff" tab se add karo.')),
      ])),
      ListView(children: [
        for (final s in staff) ListTile(
          title: Text('${s['name']}'), subtitle: Text('ID: ${s['userId']}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.key), tooltip: 'Reset PIN', onPressed: () async {
              final r = await Session.call('manageUser', {'userId': s['userId'], 'op': 'reset'});
              if (!mounted) return; _snack(r['ok'] == true ? 'Naya PIN: ${r['pin']}' : '${r['error']}'); }),
            IconButton(icon: const Icon(Icons.person_remove), tooltip: 'Remove', onPressed: () async {
              await Session.call('manageUser', {'userId': s['userId'], 'op': 'remove'}); load(); }),
          ])),
        Padding(padding: const EdgeInsets.all(8), child: Text('${staff.length} / 15 staff', textAlign: TextAlign.center)),
      ]),
      ListView(children: [
        for (final d in duties) CheckboxListTile(
          value: d['done'] == 1, title: Text('${d['aisle']}  ${d['task'] ?? ''}'),
          subtitle: Text(staff.where((s) => s['userId'] == d['staff']).map((s) => s['name']).join()),
          onChanged: (v) async { await Session.call('doneDuty', {'id': d['id'], 'done': v == true ? 1 : 0}); load(); }),
        if (duties.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Aaj ki koi duty assign nahi.')),
      ]),
    ];
    return Scaffold(
      appBar: AppBar(title: Text('${Session.name} - ${Session.companyName}'), actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => logout(c))]),
      body: pages[tab],
      floatingActionButton: tab == 1 ? FloatingActionButton(onPressed: addStaff, child: const Icon(Icons.person_add)) : tab == 2 ? FloatingActionButton(onPressed: assign, child: const Icon(Icons.add_task)) : null,
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
        NavigationDestination(icon: Icon(Icons.wifi), label: 'Live team'),
        NavigationDestination(icon: Icon(Icons.group), label: 'Staff'),
        NavigationDestination(icon: Icon(Icons.checklist), label: 'Duties'),
      ]),
    );
  }
}
