import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'api.dart';
import 'captain.dart';
import 'staff.dart';

void main() {
  FlutterForegroundTask.initCommunicationPort();
  runApp(const MartOps());
}

class MartOps extends StatelessWidget {
  const MartOps({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'MartOps',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF2B84B), brightness: Brightness.dark)),
        home: const Boot(),
      );
}

Widget homeFor(String? role) => role == 'captain' ? const CaptainHome() : role == 'staff' ? const StaffHome() : const OwnerHome();

class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  @override
  void initState() {
    super.initState();
    Session.restore().then((ok) {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ok ? homeFor(Session.role) : const Login()));
    });
  }

  @override
  Widget build(BuildContext c) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class Login extends StatefulWidget {
  const Login({super.key});
  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final co = TextEditingController(), id = TextEditingController(), pw = TextEditingController();
  String err = '';
  bool busy = false;

  Future<void> _go() async {
    setState(() { busy = true; err = ''; });
    final r = await rawCall(null, 'login', {'company': co.text.trim(), 'userId': id.text.trim(), 'password': pw.text});
    if (r['ok'] == true) {
      await Session.save(r);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => homeFor(r['role'])));
    } else {
      setState(() { busy = false; err = {'bad_credentials': 'ID ya password ghalat hai.', 'company_not_found': 'Company code nahi mila.', 'network': 'Internet check karo.', 'subscription_inactive': 'Subscription band hai, owner se rabta karo.'}[r['error']] ?? '${r['error']}'; });
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(children: [
                  const Text('MartOps', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Owner, Captain ya Staff login', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),
                  TextField(controller: co, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Company code', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: id, decoration: const InputDecoration(labelText: 'User ID (owner / captain / staff ID)', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'Password / PIN', border: OutlineInputBorder())),
                  if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err, style: const TextStyle(color: Colors.redAccent))),
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: FilledButton(onPressed: busy ? null : _go, child: Text(busy ? 'Please wait...' : 'Log in'))),
                ]),
              ),
            ),
          ),
        ),
      );
}

Future<void> logout(BuildContext c) async {
  await FlutterForegroundTask.stopService();
  await Session.clear();
  if (c.mounted) Navigator.pushAndRemoveUntil(c, MaterialPageRoute(builder: (_) => const Login()), (_) => false);
}

class OwnerHome extends StatelessWidget {
  const OwnerHome({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(Session.companyName ?? 'Owner'), actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => logout(c))]),
        body: FutureBuilder<Map>(
          future: Session.call('dashboard'),
          builder: (c, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final d = s.data!;
            if (d['ok'] != true) return Center(child: Text('Subscription ya network masla: ${d['error']}\nWeb panel se payment karo.', textAlign: TextAlign.center));
            final st = (d['users'] as List).where((u) => u['role'] == 'staff').toList();
            final inn = st.where((u) => u['status'] == 'CONNECTED').length;
            return ListView(padding: const EdgeInsets.all(16), children: [
              ListTile(title: Text('${st.length} staff'), subtitle: Text('$inn store mein, ${st.length - inn} bahar / signal nahi')),
              ListTile(title: Text('${(d['branches'] as List).length} / 10 branches')),
              ListTile(title: const Text('Branches, Wi-Fi, captains aur payment ke liye web panel use karo'), subtitle: Text('${d['company']['portalUrl']}')),
              for (final u in st)
                ListTile(
                  leading: Icon(Icons.circle, size: 14, color: u['status'] == 'CONNECTED' ? Colors.green : Colors.orange),
                  title: Text('${u['name']}'),
                  subtitle: Text(u['outMin'] > 0 ? '${u['outMin']} min bahar' : '${u['status']}'),
                ),
            ]);
          },
        ),
      );
}
