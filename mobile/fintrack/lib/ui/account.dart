import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'profile_photo.dart';
import '../data/ledger.dart';
import '../domain/finance.dart';
import 'editor.dart';
import 'navigation.dart';
import 'patterns.dart';

class AccountScreen extends StatefulWidget {
  final Ledger ledger;
  final Future<void> Function() feedback;
  final Future<void> Function() onSignOut;
  const AccountScreen({
    super.key,
    required this.ledger,
    required this.feedback,
    required this.onSignOut,
  });
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      phone = TextEditingController(),
      password = TextEditingController();
  Data? profile;
  Uint8List? preview;
  bool editing = false, busy = false, loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.ledger.api.request('/api/v1/account');
      if (!mounted) return;
      apply(result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
    if (mounted) setState(() => loading = false);
  }

  void apply(Data result, {bool preserveDraft = false}) {
    setState(() {
      profile = result;
      if (!preserveDraft) {
        name.text = text(result, 'name');
        email.text = text(result, 'email');
        phone.text = text(result, 'phone');
      }
      error = null;
    });
    widget.ledger.api.updateUser(result);
    widget.ledger.notifyAccountChanged();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.ledger.api.request(
        '/api/v1/account',
        method: 'PATCH',
        body: {
          'name': name.text.trim(),
          'email': email.text.trim(),
          'phone': phone.text.trim(),
          if (email.text.trim() != text(profile ?? {}, 'email'))
            'currentPassword': password.text,
        },
      );
      if (!mounted) return;
      apply(result);
      setState(() {
        editing = false;
        password.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved')));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changePhoto() async {
    if (busy) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() {
        busy = true;
        error = null;
      });
      final bytes = await prepareProfilePhoto(await picked.readAsBytes());
      if (!mounted) return;
      setState(() => preview = bytes);
      await upload();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> upload() async {
    if (preview == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.ledger.api.uploadPhoto(preview!);
      if (mounted) {
        apply(result, preserveDraft: true);
        setState(() => preview = null);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> removePhoto() async {
    if (busy ||
        !await confirm(
          context,
          'Remove your profile photo?',
          action: 'Remove photo',
          destructive: true,
        )) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.ledger.api.request(
        '/api/v1/account/photo',
        method: 'DELETE',
      );
      if (mounted) {
        apply(result, preserveDraft: true);
        setState(() => preview = null);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    password.dispose();
    super.dispose();
  }

  Widget avatar() => ClipOval(
    child: preview != null
        ? Image.memory(preview!, width: 112, height: 112, fit: BoxFit.cover)
        : profile?['image'] is String
        ? Image.network(
            '${widget.ledger.api.baseUrl}${profile!['image']}',
            headers: {
              'Authorization':
                  'Bearer ${widget.ledger.api.session?['accessToken']}',
            },
            width: 112,
            height: 112,
            fit: BoxFit.cover,
            errorBuilder: (_, e, st) => const CircleAvatar(
              radius: 56,
              child: FinIcon('user', size: 48),
            ),
          )
        : const CircleAvatar(radius: 56, child: FinIcon('user', size: 48)),
  );
  Widget input(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    bool secret = false,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: secret,
          keyboardType: keyboard,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            fillColor: Theme.of(context).colorScheme.surface,
            hintText: label == 'Phone' ? 'Include your country code' : null,
          ),
          validator: (v) => required && (v == null || v.trim().isEmpty)
              ? 'Required'
              : label == 'Email' &&
                    !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v ?? '')
              ? 'Enter a valid email'
              : null,
        ),
      ],
    ),
  );
  void closeEditor() {
    setState(() {
      editing = false;
      password.clear();
      if (profile != null) {
        name.text = text(profile!, 'name');
        email.text = text(profile!, 'email');
        phone.text = text(profile!, 'phone');
      }
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !editing,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !busy && editing) closeEditor();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: busy
              ? null
              : () {
                  if (editing) {
                    closeEditor();
                  } else {
                    navigateBack(context);
                  }
                },
          icon: const FinIcon('back'),
        ),
        title: Text(editing ? 'Edit profile' : 'My account'),
        centerTitle: true,
      ),
      body: loading
          ? const BrandLoading(label: 'Loading your account…')
          : SafeArea(
              child: SingleChildScrollView(
                key: const PageStorageKey('account'),
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              avatar(),
                              Positioned(
                                right: -6,
                                bottom: -4,
                                child: Material(
                                  color: Theme.of(context).colorScheme.surface,
                                  shape: const CircleBorder(),
                                  child: editing
                                      ? PopupMenuButton<String>(
                                          tooltip: 'Edit profile photo',
                                          enabled: !busy,
                                          icon: const FinIcon('edit', size: 20),
                                          onSelected: (action) {
                                            if (action == 'upload') {
                                              changePhoto();
                                            } else {
                                              removePhoto();
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: 'upload',
                                              enabled:
                                                  profile?['photoUploadEnabled'] ==
                                                  true,
                                              child: const Row(
                                                children: [
                                                  FinIcon('camera', size: 18),
                                                  SizedBox(width: 8),
                                                  Text('Change photo'),
                                                ],
                                              ),
                                            ),
                                            if (profile?['image'] != null ||
                                                preview != null)
                                              const PopupMenuItem(
                                                value: 'remove',
                                                child: Row(
                                                  children: [
                                                    FinIcon('trash', size: 18),
                                                    SizedBox(width: 8),
                                                    Text('Remove photo'),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        )
                                      : IconButton(
                                          tooltip: 'Edit profile',
                                          onPressed: busy
                                              ? null
                                              : () => setState(
                                                  () => editing = true,
                                                ),
                                          icon: const FinIcon('edit', size: 20),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (!editing)
                          Text(
                            text(
                              profile ??
                                  widget.ledger.api.session?['user'] ??
                                  {},
                              'name',
                              'My profile',
                            ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        const SizedBox(height: 28),
                        if (busy) const LinearProgressIndicator(),
                        if (error != null) ...[
                          Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (preview != null)
                            TextButton(
                              onPressed: busy ? null : upload,
                              child: const Text('Retry photo upload'),
                            ),
                          if (profile == null)
                            TextButton(
                              onPressed: busy ? null : load,
                              child: const Text('Retry loading profile'),
                            ),
                        ],
                        if (editing)
                          Form(
                            key: form,
                            child: Column(
                              children: [
                                input(name, 'Name', required: true),
                                input(
                                  email,
                                  'Email',
                                  keyboard: TextInputType.emailAddress,
                                  required: true,
                                ),
                                input(
                                  phone,
                                  'Phone',
                                  keyboard: TextInputType.phone,
                                ),
                                if (email.text.trim() !=
                                    text(profile ?? {}, 'email'))
                                  input(
                                    password,
                                    'Current password',
                                    secret: true,
                                    required: true,
                                  ),
                                if (profile?['photoUploadEnabled'] != true)
                                  const Text(
                                    'Photo uploads are not configured yet.',
                                  ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        onPressed: busy
                                            ? null
                                            : () {
                                                if (profile != null) {
                                                  apply(profile!);
                                                }
                                                setState(() => editing = false);
                                              },
                                        child: const Text('Cancel'),
                                      ),
                                    ),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: busy ? null : save,
                                        child: Text(
                                          busy ? 'Saving…' : 'Save details',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                        else
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  FinContact(
                                    icon: 'phone',
                                    label: 'Phone',
                                    value: text(profile ?? {}, 'phone').isEmpty
                                        ? 'Add your phone number'
                                        : text(profile!, 'phone'),
                                    onTap: profile == null
                                        ? null
                                        : () => setState(() => editing = true),
                                  ),
                                  FinContact(
                                    icon: 'mail',
                                    label: 'Email',
                                    value: text(profile ?? {}, 'email'),
                                    onTap: profile == null
                                        ? null
                                        : () => setState(() => editing = true),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: busy ? null : widget.feedback,
                          icon: const FinIcon('feedback'),
                          label: const Text('Give feedback'),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xff482829)
                                : const Color(0xfffce8e6),
                            foregroundColor:
                                Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xffffc5bf)
                                : const Color(0xff9c3030),
                          ),
                          onPressed: busy ? null : widget.onSignOut,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Sign out'),
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'FinTrack v1.2.1 · Developed by Eucodes',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    ),
  );
}
