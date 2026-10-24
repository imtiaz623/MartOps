import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';

/// Payment Easypaisa par aati hai.
const kEasypaisaNumber = '03708431602';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final tid = TextEditingController();
  String plan = 'MONTHLY', msg = '';
  bool busy = false, done = false, bad = false;
  Map? sub;

  @override
  void initState() {
    super.initState();
    Session.call('sub').then((r) {
      if (!mounted || r['ok'] != true) return;
      setState(() { sub = r; if (r['pay'] == 'PENDING') done = true; });
    });
  }

  String _date(num ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _statusText() {
    final s = sub;
    if (s == null) return '';
    final st = s['status'];
    final extra = s['pay'] == 'PENDING' && s['allowed'] == true ? '\nNayi payment verify ho rahi hai.' : s['pay'] == 'REJECTED' && s['allowed'] == true ? '\nPichli payment reject hui, sahi TID bhejo.' : '';
    if (st == 'ACTIVE') return 'Active - ${_date(s['validUntil'])} tak$extra';
    if (st == 'TRIAL') return 'Free trial - ${_date(s['trialEnd'])} tak$extra';
    if (st == 'PENDING') return 'Payment verify ho rahi hai. Approve hote hi access khul jayega.';
    if (st == 'REJECTED') return 'Payment reject hui. Sahi TID dobara bhejo.';
    return 'Subscription khatam. Payment karo.';
  }

  Future<void> _submit() async {
    final t = tid.text.trim();
    if (t.isEmpty) { setState(() { bad = true; msg = 'Transaction ID (TID) likho.'; }); return; }
    setState(() { busy = true; msg = ''; });
    final r = await Session.call('pay', {'plan': plan, 'tid': t});
    if (!mounted) return;
    setState(() {
      busy = false;
      if (r['ok'] == true) { done = true; bad = false; msg = 'TID bhej di gayi. Verify hone ke baad access chalu ho jayega.'; }
      else {
        bad = true;
        msg = {'network': 'Internet check karo.', 'tid_already_used': 'Ye TID pehle use ho chuki hai.', 'payment_already_pending': 'Pehli payment abhi verify ho rahi hai.', 'tid_required': 'Sahi Transaction ID likho.'}[r['error']] ?? '${r['error']}';
        if (r['error'] == 'payment_already_pending') done = true;
      }
    });
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 90, child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: SelectableText(v, style: const TextStyle(fontWeight: FontWeight.w600))),
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.copy, size: 18), onPressed: () => Clipboard.setData(ClipboardData(text: v))),
        ]),
      );

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Payment')),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            if (sub != null) Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(_statusText(), style: const TextStyle(fontWeight: FontWeight.w600))),
            DropdownButtonFormField<String>(
              value: plan,
              decoration: const InputDecoration(labelText: 'Plan', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly - PKR 3,000')),
                DropdownMenuItem(value: 'YEARLY', child: Text('Yearly - PKR 30,000')),
              ],
              onChanged: done ? null : (v) => setState(() => plan = v ?? 'MONTHLY'),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Easypaisa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  _row('Number', kEasypaisaNumber),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Payment karne ke baad apni Transaction ID (TID) neeche likh kar submit karo.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(controller: tid, enabled: !done, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Transaction ID (TID)', border: OutlineInputBorder())),
            if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(msg, style: TextStyle(color: bad ? Colors.redAccent : Colors.greenAccent))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: busy || done ? null : _submit, child: Text(busy ? 'Please wait...' : 'Submit'))),
          ]),
        ),
      );
}
