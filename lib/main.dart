import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'api.dart';
import 'payment.dart';
import 'about.dart';
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

Widget homeFor(String? role) => role == 'owner' ? const OwnerHome() : const StaffHome();

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
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ok ? homeFor(Session.role) : const Welcome()));
    });
  }

  @override
  Widget build(BuildContext c) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class Welcome extends StatelessWidget {
  const Welcome({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('MartOps', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Manager branch visit tracking', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 40),
                  SizedBox(width: double.infinity, height: 52, child: FilledButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const Register())), child: const Text('Register Company'))),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, height: 52, child: OutlinedButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const Login())), child: const Text('Login'))),
                  const SizedBox(height: 20),
                  TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const AboutScreen())), child: const Text('About / Help / Privacy Policy')),
                  const Text('Help line: '+kHelpline, style: TextStyle(color: Colors.grey)),
                ]),
              ),
            ),
          ),
        ),
      );
}

class Register extends StatefulWidget {
  const Register({super.key});
  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  final cn = TextEditingController(), on = TextEditingController(), ph = TextEditingController(), wa = TextEditingController(), pw = TextEditingController();
  String err = '';
  bool busy = false;
  Map? done;

  Future<void> _go() async {
    if (cn.text.trim().isEmpty) { setState(() => err = 'Company ka naam likho.'); return; }
    if (pw.text.length < 6) { setState(() => err = 'Password kam az kam 6 characters ka ho.'); return; }
    setState(() { busy = true; err = ''; });
    final r = await rawCall(null, 'register', {'companyName': cn.text.trim(), 'ownerName': on.text.trim(), 'phone': ph.text.trim(), 'wa': wa.text.trim(), 'password': pw.text});
    if (!mounted) return;
    if (r['ok'] == true) {
      await Session.save({'token': r['token'], 'role': 'owner', 'name': on.text.trim().isEmpty ? 'Owner' : on.text.trim(), 'userId': 'owner', 'company': {'name': cn.text.trim(), 'code': r['code']}});
      if (!mounted) return;
      setState(() { busy = false; done = r; });
    } else {
      setState(() { busy = false; err = r['error'] == 'network' ? 'Internet check karo.' : '${r['error']}'; });
    }
  }

  Widget _copyRow(String label, String v) => Card(
        child: ListTile(
          title: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          subtitle: SelectableText(v, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () { Clipboard.setData(ClipboardData(text: v)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copy ho gaya'))); }),
        ),
      );

  Widget _form() => Column(children: [
        const Text('Register Company', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('14 din ka free trial', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 24),
        TextField(controller: cn, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Company name', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: on, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Owner name', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: ph, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (92300XXXXXXX)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: wa, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'WhatsApp for reports (optional)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'Password (6+ characters)', border: OutlineInputBorder())),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err, style: const TextStyle(color: Colors.redAccent))),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: busy ? null : _go, child: Text(busy ? 'Please wait...' : 'Register'))),
      ]);

  Widget _success() => Column(children: [
        const Icon(Icons.check_circle, size: 56, color: Colors.greenAccent),
        const SizedBox(height: 8),
        const Text('Company register ho gayi', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        _copyRow('Company Code', '${done!['code']}'),
        _copyRow('Web Admin URL', '${done!['portalUrl']}'),
        const SizedBox(height: 8),
        const Text('Owner login ID: owner\nCompany Code managers ko bhi dena hai.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const OwnerHome()), (_) => false), child: const Text('Continue'))),
      ]);

  @override
  Widget build(BuildContext c) => PopScope(
        canPop: done == null,
        child: Scaffold(
          appBar: done == null ? AppBar() : null,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: done == null ? _form() : _success()),
              ),
            ),
          ),
        ),
      );
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
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => homeFor(r['role'])), (_) => false);
    } else {
      setState(() { busy = false; err = {'bad_credentials': 'ID ya password ghalat hai.', 'company_not_found': 'Company code nahi mila.', 'network': 'Internet check karo.', 'subscription_inactive': 'Subscription band hai, owner se rabta karo.'}[r['error']] ?? '${r['error']}'; });
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(children: [
                  const Text('MartOps', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Owner ya Manager login', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),
                  TextField(controller: co, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Company code', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: id, decoration: const InputDecoration(labelText: 'User ID (owner / manager ID)', border: OutlineInputBorder())),
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
  if (c.mounted) Navigator.pushAndRemoveUntil(c, MaterialPageRoute(builder: (_) => const Welcome()), (_) => false);
}

class OwnerHome extends StatelessWidget {
  const OwnerHome({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(Session.companyName ?? 'Owner'), actions: [IconButton(icon: const Icon(Icons.info_outline), tooltip: 'About / Help', onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const AboutScreen()))), IconButton(icon: const Icon(Icons.payments_outlined), tooltip: 'Payment', onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const PaymentScreen()))), IconButton(icon: const Icon(Icons.logout), onPressed: () => logout(c))]),
        body: FutureBuilder<Map>(
          future: Session.call('dashboard'),
          builder: (c, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final d = s.data!;
            if (d['ok'] != true) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(d['error'] == 'subscription_inactive' ? ({'PENDING': 'Payment verify ho rahi hai. Approve hote hi access khul jayega.', 'REJECTED': 'Payment reject ho gayi. Sahi TID dobara bhejo.'}[d['status']] ?? 'Subscription khatam / band hai. Payment karo.') : 'Network masla: ${d['error']}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const PaymentScreen())), child: const Text('Payment')),
                ]),
              );
            }
            final st = (d['users'] as List).where((u) => u['role'] == 'staff').toList();
            final names = {for (final b in d['branches'] as List) b['id']: '${b['name']}'};
            final vis = (d['visits'] as List).take(20).toList();
            return ListView(padding: const EdgeInsets.all(16), children: [
              ListTile(title: Text('${st.length} manager, ${(d['branches'] as List).length} branches'), subtitle: Text('Branches, Wi-Fi aur managers web panel se manage karo:\n${d['company']['portalUrl']}')),
              const Padding(padding: EdgeInsets.only(top: 8, left: 16), child: Text('Managers abhi', style: TextStyle(fontWeight: FontWeight.w600))),
              for (final u in st)
                ListTile(
                  leading: Icon(Icons.circle, size: 14, color: u['status'] == 'CONNECTED' ? Colors.green : (u['status'] == 'NO_SIGNAL' || u['status'] == 'NONET') ? Colors.redAccent : Colors.orange),
                  title: Text('${u['name']}'),
                  subtitle: Text(stLabel(u['status'], branch: '${names[u['branch']] ?? ''}', detail: '${u['detail'] ?? ''}')),
                ),
              const Padding(padding: EdgeInsets.only(top: 12, left: 16), child: Text('Recent activity', style: TextStyle(fontWeight: FontWeight.w600))),
              for (final v in vis)
                ListTile(
                  dense: true,
                  title: Text('${v['manager']} - ${v['state'] == 'BRANCH' ? v['branchName'] : stLabel(v['state'], detail: '${v['detail'] ?? ''}')}'),
                  subtitle: Text(v['left'] == '' ? '${fmtT(v['arrived'])}  (abhi yahan)' : '${fmtT(v['arrived'])} - ${fmtT(v['left'])}   ${v['minutes']} min'),
                ),
              if (vis.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Abhi koi visit nahi.')),
            ]);
          },
        ),
      );
}
