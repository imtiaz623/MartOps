import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const kHelpNumber = '0306 9348405';
const kWhatsApp = 'https://wa.me/923069348405?text=MartOps%20help';

Future<void> _open(BuildContext c, String url, String fallbackText) async {
  var ok = false;
  try { ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); } catch (_) {}
  if (!ok && c.mounted) {
    await Clipboard.setData(ClipboardData(text: fallbackText));
    if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('Khul nahi saka. $fallbackText copy ho gaya.')));
  }
}

Future<void> openWhatsApp(BuildContext c) => _open(c, kWhatsApp, kHelpNumber);
Future<void> callHelp(BuildContext c) => _open(c, 'tel:03069348405', kHelpNumber);

/// "Help line 0306 9348405 [WhatsApp] [Call]" row for the front, login and register screens.
class HelpBar extends StatelessWidget {
  const HelpBar({super.key});
  @override
  Widget build(BuildContext c) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
          const Text('Help line: $kHelpNumber', style: TextStyle(color: Colors.grey)),
          TextButton.icon(onPressed: () => openWhatsApp(c), icon: const Icon(Icons.chat, size: 18), label: const Text('WhatsApp')),
          TextButton.icon(onPressed: () => callHelp(c), icon: const Icon(Icons.call, size: 18), label: const Text('Call')),
        ]),
      );
}
