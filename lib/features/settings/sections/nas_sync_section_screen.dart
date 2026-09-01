// lib/features/settings/sections/nas_sync_section_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/nas_sync_database.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_dialog.dart';
import 'package:sitemark/shared/ui/adaptive_progress.dart';
import 'package:sitemark/shared/ui/adaptive_segmented_button.dart';
import 'package:sitemark/shared/ui/adaptive_toast.dart';
import 'package:sitemark/src/rust/api/nas.dart' as rust_api;
import 'package:sitemark/src/rust/nas.dart' as rust;

/// NAS sync configuration (settings, data & safety). The password lives in
/// secure storage only — the form keeps it in memory and writes it through
/// the credential store on save.
class NasSyncSectionScreen extends ConsumerStatefulWidget {
  const NasSyncSectionScreen({super.key});

  @override
  ConsumerState<NasSyncSectionScreen> createState() =>
      _NasSyncSectionScreenState();
}

class _NasSyncSectionScreenState extends ConsumerState<NasSyncSectionScreen> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _rootController = TextEditingController();

  String _protocol = 'webdav';
  bool _secureTls = true;
  bool _acceptInvalidTls = false;
  bool _wifiOnly = true;
  bool _enabled = false;
  String? _knownFingerprint;
  bool _passwordSet = false;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _rootController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final database = ref.read(databaseProvider);
    final config = await database.nasSyncConfig();
    final password = await ref.read(nasCredentialStoreProvider).read();
    if (!mounted) return;
    setState(() {
      _protocol = config.protocol;
      _hostController.text = config.host;
      _portController.text = config.port?.toString() ?? '';
      _usernameController.text = config.username;
      _rootController.text = config.rootPath;
      _secureTls = config.secureTls;
      _acceptInvalidTls = config.acceptInvalidTls;
      _wifiOnly = config.wifiOnly;
      _enabled = config.enabled;
      _knownFingerprint = config.knownSftpFingerprint;
      _passwordSet = password != null && password.isNotEmpty;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (!_loaded) {
      return SettingsSectionScaffold(
        title: strings.nasSync,
        body: const Center(child: AdaptiveProgressIndicator()),
      );
    }
    return SettingsSectionScaffold(
      title: strings.nasSync,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            key: const Key('nas-enable-switch'),
            title: Text(strings.nasEnable),
            value: _enabled,
            onChanged: (value) => _setEnabled(value),
          ),
          ListTile(
            dense: true,
            title: Text(strings.nasProtocol),
          ),
          AdaptiveSegmentedButton<String>(
            key: const Key('nas-protocol-segmented'),
            segments: [
              ButtonSegment(
                value: 'webdav',
                label: Text(strings.nasProtocolWebdav),
              ),
              ButtonSegment(
                value: 'sftp',
                label: Text(strings.nasProtocolSftp),
              ),
              ButtonSegment(
                value: 'smb',
                label: Text(strings.nasProtocolSmb),
              ),
            ],
            selected: {_protocol},
            onSelectionChanged: (value) =>
                setState(() => _protocol = value.first),
          ),
          TextField(
            key: const Key('nas-host-field'),
            controller: _hostController,
            decoration: InputDecoration(
              labelText: strings.nasHost,
              hintText: strings.nasHostHint,
            ),
            autocorrect: false,
            enableSuggestions: false,
          ),
          TextField(
            key: const Key('nas-port-field'),
            controller: _portController,
            decoration: InputDecoration(
              labelText: strings.nasPort,
              hintText: _portHint(strings),
              counterText: '',
            ),
            keyboardType: TextInputType.number,
            maxLength: 5,
          ),
          TextField(
            key: const Key('nas-username-field'),
            controller: _usernameController,
            decoration: InputDecoration(labelText: strings.nasUsername),
            autocorrect: false,
            enableSuggestions: false,
          ),
          TextField(
            key: const Key('nas-password-field'),
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: strings.nasPassword,
              helperText: _passwordSet ? null : strings.nasPassword,
            ),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
          TextField(
            key: const Key('nas-root-field'),
            controller: _rootController,
            decoration: InputDecoration(
              labelText: strings.nasRootPath,
              hintText: _rootHint(strings),
            ),
            autocorrect: false,
            enableSuggestions: false,
          ),
          if (_protocol == 'webdav') ...[
            SwitchListTile.adaptive(
              title: Text(strings.nasSecureTls),
              value: _secureTls,
              onChanged: (value) => setState(() => _secureTls = value),
            ),
            if (_secureTls)
              SwitchListTile.adaptive(
                title: Text(strings.nasAcceptInvalidTls),
                value: _acceptInvalidTls,
                onChanged: (value) =>
                    setState(() => _acceptInvalidTls = value),
              ),
          ],
          SwitchListTile.adaptive(
            key: const Key('nas-wifi-only-switch'),
            title: Text(strings.nasWifiOnly),
            value: _wifiOnly,
            onChanged: (value) => setState(() => _wifiOnly = value),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('nas-test-connection-button'),
                  onPressed: _saving ? null : () => _testConnection(strings),
                  icon: const Icon(Icons.wifi_tethering),
                  label: Text(strings.nasTestConnection),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('nas-save-button'),
                  onPressed: _saving ? null : () => _save(strings),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(strings.nasSave),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(strings.nasPrivacyNote,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _portHint(AppStrings strings) => switch (_protocol) {
        'sftp' => strings.nasPortHintSftp,
        'smb' => strings.nasPortHintSmb,
        _ => strings.nasPortHintWebdav,
      };

  String _rootHint(AppStrings strings) =>
      _protocol == 'smb' ? strings.nasSmbRootPathHint : strings.nasRootPathHint;

  int? _parsedPort() {
    final text = _portController.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  rust.NasConfig _configFromForm(String password) => rust.NasConfig(
        protocol: switch (_protocol) {
          'sftp' => rust.NasProtocol.sftp,
          'smb' => rust.NasProtocol.smb,
          _ => rust.NasProtocol.webdav,
        },
        host: _hostController.text.trim(),
        port: _parsedPort(),
        username: _usernameController.text.trim(),
        password: password,
        rootPath: _rootController.text.trim().isEmpty
            ? '/'
            : _rootController.text.trim(),
        secureTls: _secureTls,
        acceptInvalidTls: _acceptInvalidTls,
        knownSftpFingerprint: _knownFingerprint,
      );

  Future<void> _testConnection(AppStrings strings) async {
    final host = _hostController.text.trim();
    if (host.isEmpty) {
      if (mounted) showAppToast(context, strings.nasHostRequired);
      return;
    }
    final password = _passwordController.text;
    final config = _configFromForm(password);
    String? failure;
    try {
      final details = await rust_api.nasTestConnection(config: config);
      final fingerprint = details.sftpFingerprint;
      if (fingerprint != null && fingerprint != _knownFingerprint) {
        final accepted = await _confirmFingerprint(fingerprint, strings);
        if (!accepted) return;
        setState(() => _knownFingerprint = fingerprint);
      }
    } on rust.NasError catch (error) {
      failure = error.code.name;
    }
    if (!mounted) return;
    showAppToast(
      context,
      failure == null ? strings.nasTestSucceeded : _errorText(strings, failure),
    );
  }

  Future<bool> _confirmFingerprint(
    String fingerprint,
    AppStrings strings,
  ) async {
    final accepted = await showAppDialog<bool>(
      context: context,
      title: Text(strings.nasFingerprintTitle),
      content: Text(strings.nasFingerprintBody(fingerprint)),
      actions: [
        AppDialogAction(
          label: MaterialLocalizations.of(context).cancelButtonLabel,
          result: false,
        ),
        AppDialogAction(
          key: const Key('nas-fingerprint-accept'),
          label: strings.nasFingerprintAccept,
          result: true,
          isDefault: true,
        ),
      ],
    );
    return accepted ?? false;
  }

  Future<void> _save(AppStrings strings) async {
    final host = _hostController.text.trim();
    if (host.isEmpty) {
      showAppToast(context, strings.nasHostRequired);
      return;
    }
    setState(() => _saving = true);
    final database = ref.read(databaseProvider);
    await database.saveNasSyncConfig(
      protocol: _protocol,
      host: host,
      port: _parsedPort(),
      username: _usernameController.text.trim(),
      rootPath: _rootController.text.trim().isEmpty
          ? '/'
          : _rootController.text.trim(),
      secureTls: _secureTls,
      acceptInvalidTls: _acceptInvalidTls,
      knownSftpFingerprint: _knownFingerprint,
      wifiOnly: _wifiOnly,
      enabled: _enabled,
    );
    final store = ref.read(nasCredentialStoreProvider);
    final password = _passwordController.text;
    if (password.isNotEmpty) {
      await store.write(password);
    } else if (!_passwordSet) {
      await store.delete();
    }
    if (!mounted) return;
    setState(() => _saving = false);
    showAppToast(context, strings.nasSaved);
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    // Persist immediately: the toggle is the master switch of the queue.
    await _save(AppStrings.of(context));
  }

  String _errorText(AppStrings strings, String code) => switch (code) {
        'connection_failed' => strings.nasErrorConnectionFailed,
        'auth_failed' => strings.nasErrorAuthFailed,
        'timeout' => strings.nasErrorTimeout,
        'tls_error' => strings.nasErrorTlsError,
        'tls_unsupported' => strings.nasErrorTlsUnsupported,
        'host_key_changed' => strings.nasErrorHostKeyChanged,
        'quota_insufficient' => strings.nasErrorQuotaInsufficient,
        'path_invalid' => strings.nasErrorPathInvalid,
        'local_io' => strings.nasErrorLocalIo,
        'config_invalid' => strings.nasErrorConfigInvalid,
        _ => strings.nasErrorProtocolError,
      };
}
