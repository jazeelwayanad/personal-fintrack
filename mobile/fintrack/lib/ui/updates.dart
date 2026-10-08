import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/updates.dart';

class UpdateSettings extends StatefulWidget {
  const UpdateSettings({super.key});
  @override
  State<UpdateSettings> createState() => _UpdateSettingsState();
}

class _UpdateSettingsState extends State<UpdateSettings> {
  static const channel = MethodChannel('fintrack/external_links');
  String installed = appVersion;
  String? message;
  AppRelease? release;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    readInstalledVersion();
  }

  Future<void> readInstalledVersion() async {
    try {
      final version = await channel.invokeMethod<String>('version');
      if (mounted && version != null) setState(() => installed = version);
    } on PlatformException {
      // The bundled version remains available if package metadata is unavailable.
    } on MissingPluginException {
      // Widget previews do not have the Android package bridge.
    }
  }

  Future<void> check() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
      release = null;
    });
    try {
      await readInstalledVersion();
      final latest = await AppRelease.latest();
      if (!mounted) return;
      setState(() {
        release = newerVersion(latest.version, installed) ? latest : null;
        message = release == null
            ? 'You’re up to date.'
            : 'Version ${latest.version} is available.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Couldn’t check for updates. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> download() async {
    final latest = release;
    if (latest == null || busy) return;
    setState(() => busy = true);
    try {
      await channel.invokeMethod('open', latest.download.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Couldn’t open the download. Try again or download the APK from the FinTrack GitHub releases page.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Installed version $installed'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: busy ? null : check,
        icon: const Icon(Icons.system_update_alt_rounded, size: 20),
        label: Text(busy ? 'Please wait…' : 'Check for updates'),
      ),
      if (busy)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: LinearProgressIndicator(
            value: MediaQuery.disableAnimationsOf(context) ? 1 : null,
          ),
        ),
      if (message != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(liveRegion: true, child: Text(message!)),
        ),
      if (release != null) ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : download,
          icon: const Icon(Icons.download_rounded, size: 20),
          label: const Text('Download update'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Open the downloaded APK and approve the Android installation. Install over this app; do not uninstall. Your saved data stays on this device.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ],
  );
}
