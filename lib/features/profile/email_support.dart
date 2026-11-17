import 'dart:io';

import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/branding.dart';
import '../../core/platform/device_services.dart';
import '../../shared/widgets/ui.dart';

const _supportEmail = 'dhibi.ywsf@gmail.com';
const _mailChannel = MethodChannel('tn.dhibi.fitness_tracker/support');

enum _SupportTopic {
  bug('Report a bug', 'Something is broken or looks wrong.', LucideIcons.bug),
  question(
    'Ask a question',
    'Get help using the app.',
    LucideIcons.messageCircleQuestionMark,
  ),
  suggestion(
    'Suggest an improvement',
    'Tell us what would make the app better.',
    LucideIcons.lightbulb,
  );

  const _SupportTopic(this.title, this.subtitle, this.icon);

  final String title;
  final String subtitle;
  final IconData icon;
}

class EmailSupportButton extends StatefulWidget {
  const EmailSupportButton({required this.buildInfo, super.key});

  final AppBuild? buildInfo;

  @override
  State<EmailSupportButton> createState() => _EmailSupportButtonState();
}

class _EmailSupportButtonState extends State<EmailSupportButton> {
  bool _active = false;

  Future<void> _emailSupport() async {
    setState(() => _active = true);
    try {
      final topic = await chooseOption(
        context,
        'Support & Feedback',
        [
          for (final topic in _SupportTopic.values)
            (value: topic, label: topic.title, subtitle: topic.subtitle),
        ],
        leading: (topic, _) => Icon(topic.icon, size: 20),
        footerText: 'You can review the email and app details before sending.',
      );
      if (!mounted || topic == null) return;

      final build = widget.buildInfo;
      final opened = await _openSupportDraft(
        subject: '${Branding.name} Support - ${topic.title}',
        body: [
          'Describe what you need help with:',
          '',
          '',
          if (build != null && build.version.isNotEmpty)
            'App version: ${build.version}',
          if (build != null && build.number.isNotEmpty)
            'Build: ${build.number}',
          'OS: ${Platform.isIOS ? 'iOS' : 'Android'} ${Platform.operatingSystemVersion}',
        ].join('\n'),
      );
      if (!mounted || opened) return;

      final copy = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Couldn’t open email'),
          content: const Text('You can reach us at $_supportEmail.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Copy email address'),
            ),
          ],
        ),
      );
      if (!mounted || copy != true) return;
      try {
        await Clipboard.setData(const ClipboardData(text: _supportEmail));
        if (mounted) announce(context, 'Email address copied.');
      } on PlatformException {
        if (mounted) announce(context, 'Couldn’t copy the email address.');
      }
    } finally {
      if (mounted) setState(() => _active = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      QuietButton('Email Support', _active ? null : _emailSupport);
}

Future<bool> _openSupportDraft({
  required String subject,
  required String body,
}) async {
  if (Platform.isIOS) {
    try {
      final handled = await _mailChannel.invokeMethod<bool>('compose', {
        'recipient': _supportEmail,
        'subject': subject,
        'body': body,
      });
      if (handled == true) return true;
    } on PlatformException {
      // Try the default email app if the in-app composer fails.
    }
  }

  final uri = Uri(
    scheme: 'mailto',
    path: _supportEmail,
    query:
        'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
  );
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on PlatformException {
    return false;
  }
}
