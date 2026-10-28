import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const kHelpEmail = 'imtiazalee02@gmail.com';

Future<void> openEmail(BuildContext c) async {
  var ok = false;
  try { ok = await launchUrl(Uri.parse('mailto:$kHelpEmail?subject=MartOps%20help'), mode: LaunchMode.externalApplication); } catch (_) {}
  if (!ok && c.mounted) {
    await Clipboard.setData(const ClipboardData(text: kHelpEmail));
    if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Email app nahi khuli. Email address copy ho gaya.')));
  }
}

/// "Help: email [Email]" row for the front, login and register screens.
class HelpBar extends StatelessWidget {
  const HelpBar({super.key});
  @override
  Widget build(BuildContext c) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
          const Text('Help: $kHelpEmail', style: TextStyle(color: Colors.grey)),
          TextButton.icon(onPressed: () => openEmail(c), icon: const Icon(Icons.email_outlined, size: 18), label: const Text('Email')),
        ]),
      );
}
