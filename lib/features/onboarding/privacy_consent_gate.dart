import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sitemark/features/onboarding/privacy_consent_store.dart';
import 'package:sitemark/l10n/app_strings.dart';

export 'package:sitemark/features/onboarding/privacy_consent_store.dart';

class PrivacyConsentGate extends StatefulWidget {
  const PrivacyConsentGate({
    super.key,
    required this.store,
    required this.child,
    this.onAccepted,
    this.onExit,
  });

  final PrivacyConsentStore store;
  final Widget child;
  final VoidCallback? onAccepted;
  final VoidCallback? onExit;

  @override
  State<PrivacyConsentGate> createState() => _PrivacyConsentGateState();
}

class _PrivacyConsentGateState extends State<PrivacyConsentGate> {
  bool? _accepted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accepted = await widget.store.isAccepted();
    if (!mounted) return;
    setState(() => _accepted = accepted);
    if (accepted) widget.onAccepted?.call();
  }

  Future<void> _accept() async {
    await widget.store.accept();
    if (!mounted) return;
    setState(() => _accepted = true);
    widget.onAccepted?.call();
  }

  void _exit() {
    final onExit = widget.onExit;
    if (onExit != null) {
      onExit();
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted == true) return widget.child;
    if (_accepted == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final strings = AppStrings.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.privacyConsentTitle, style: textTheme.headlineSmall),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(strings.privacyConsentBody),
                ),
              ),
              FilledButton(
                onPressed: _accept,
                child: Text(strings.privacyConsentAgree),
              ),
              TextButton(
                onPressed: _exit,
                child: Text(strings.privacyConsentExit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
