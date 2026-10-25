import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kHelpline = '0306 9348405';
const kDevName = 'Imtiaz Ali Qumbrani';
const kDevEmail = 'imtiazalee02@gmail.com';
const kPolicyUrl = 'https://imtiaz623.github.io/MartOps/privacy.html';

const kAbout = r'''MartOps is a business app for shop and company owners. The owner adds branches and the Wi-Fi network names of each branch, then adds a manager. The manager logs in once on his Android phone. Whenever the phone connects to the Wi-Fi of a branch, the app records which branch it was, when the manager arrived and when he left. The owner sees this visit log in the app and on the web panel, so he knows which branches his manager visited.''';

const kPolicy = <List<String>>[
  [r'''1. About this policy''', r'''This policy explains what information the MartOps app and its web panel collect, why, and what choices you have. MartOps is developed by Imtiaz Ali Qumbrani (imtiazalee02@gmail.com, help line 0306 9348405). Last updated: 25 October 2026.'''],
  [r'''2. What MartOps does''', r'''MartOps is a business app for shop and company owners. The owner adds branches and the Wi-Fi network names of each branch, then adds a manager. The manager logs in once on his Android phone. Whenever the phone connects to the Wi-Fi of a branch, the app records which branch it was, when the manager arrived and when he left. The owner sees this visit log in the app and on the web panel, so he knows which branches his manager visited.'''],
  [r'''3. Information we collect''', r'''Account details: company name, owner name, phone number, optional WhatsApp number for reports, manager names and optional phone numbers, and login IDs. Passwords and PINs are stored only in hashed form.

Branch details typed by the owner: branch name, location name, and the names of the Wi-Fi networks of each branch.

Visit records (manager phones): the branch whose Wi-Fi the phone connected to, the arrival time, the departure time, the duration, the time the app was last active, and the name of the Wi-Fi network the phone was connected to.

Payment details typed by the owner: the plan, the amount and the Transaction ID (TID) of a payment made outside the app. We never ask for card, bank or wallet passwords or PINs.

Optional backup: if the owner pastes a link to his own Google Sheet, visit records are also written to that sheet.

We do not collect your GPS coordinates, contacts, photos, files, messages, call history or advertising ID.'''],
  [r'''4. Location permission and background use''', r'''Android requires the Location permission before any app can read the name of the Wi-Fi network the phone is connected to. MartOps uses it only for this. It does not read, store or show your GPS position or a map location.

On manager phones the app runs a foreground service with a visible notification, and asks for "Allow all the time" location access, so that it can check the Wi-Fi name every few seconds even when the app is closed. This is how visits are recorded automatically. The check stops if the app is uninstalled.

This record is visible to the owner of the manager's company. Owners must tell their managers that this tracking is used and must follow the laws that apply to them.'''],
  [r'''5. How we use the information''', r'''To show visit logs and reports to the owner, to run login and subscription (trial, payment verification, expiry), to send daily reports if the owner enables them, to give support, and to keep the service secure. We do not use it for advertising and we do not sell it.'''],
  [r'''6. Who we share it with''', r'''We do not sell or rent personal information. Data is stored with Google (Google Sheets and Google Apps Script) which acts as our service provider. The web panel is hosted on GitHub Pages, which does not store your records.

If the owner turns on WhatsApp reports, the owner's number and the report text are sent through the WhatsApp Business platform. If the owner connects his own Google Sheet, records are sent to that sheet.

Inside a company, the owner can see all of his managers' visit records. A manager can see his own records. We may disclose information if the law requires it.'''],
  [r'''7. Storage and security''', r'''Data travels over HTTPS. Passwords and PINs are hashed. Access to records needs a login token. No system is completely secure, so we cannot guarantee absolute security.'''],
  [r'''8. Retention and deletion''', r'''Records are kept while the company account is active. An owner can remove a manager at any time. To delete a company account and its data, or a single person's data, follow the steps at https://imtiaz623.github.io/MartOps/delete-account.html or email imtiazalee02@gmail.com. We delete the data within 30 days. Payment records (plan, amount, date, TID) may be kept as needed for accounting.'''],
  [r'''9. Your choices''', r'''You can ask us to show, correct or delete your information, and you can withdraw location permission in Android settings. Without Location permission the app cannot record branch visits.'''],
  [r'''10. Children''', r'''MartOps is made for business use by adults. It is not directed at children under 18.'''],
  [r'''11. Changes''', r'''If we change this policy we will update the date above and the page at https://imtiaz623.github.io/MartOps/privacy.html.'''],
  [r'''12. Contact''', r'''Developer: Imtiaz Ali Qumbrani

Email: imtiazalee02@gmail.com

Help line: 0306 9348405'''],
];

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Widget _copy(BuildContext c, String label, String value, IconData icon) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          subtitle: SelectableText(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () { Clipboard.setData(ClipboardData(text: value)); ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Copy ho gaya'))); }),
        ),
      );

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('About / Help')),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('MartOps', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(kAbout),
            const SizedBox(height: 16),
            _copy(c, 'Help line', kHelpline, Icons.call),
            _copy(c, 'Email', kDevEmail, Icons.email_outlined),
            _copy(c, 'Developer', kDevName, Icons.person_outline),
            _copy(c, 'Privacy Policy (web)', kPolicyUrl, Icons.privacy_tip_outlined),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const PolicyScreen())), child: const Text('Privacy Policy padho')),
          ]),
        ),
      );
}

class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Privacy Policy')),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            for (final s in kPolicy) ...[
              Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(s[0], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              Text(s[1]),
            ],
          ]),
        ),
      );
}
