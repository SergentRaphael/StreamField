import 'package:flutter/material.dart';

import '../services/account.dart';
import '../theme.dart';
import '../utils.dart';

/// Connexion au compte StreamField. Renvoie true si les données ont changé.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.account});

  final Account account;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _changed = false;
  String? _message;
  bool _isError = false;

  Account get _account => widget.account;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final msg = await action();
      _message = msg;
      _isError = false;
    } catch (e) {
      _message = e is AuthException ? e.message : friendlyError(e);
      _isError = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _checkFields() {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() {
        _message = 'Entre une adresse email valide.';
        _isError = true;
      });
      return false;
    }
    if (_password.text.length < 6) {
      setState(() {
        _message = 'Le mot de passe doit faire au moins 6 caractères.';
        _isError = true;
      });
      return false;
    }
    return true;
  }

  void _signIn() {
    if (!_checkFields()) return;
    _run(() async {
      await _account.signIn(_email.text, _password.text);
      _changed = true;
      _password.clear();
      return 'Connecté ✔ Tes playlists et favoris sont synchronisés.';
    });
  }

  void _signUp() {
    if (!_checkFields()) return;
    _run(() async {
      final ok = await _account.signUp(_email.text, _password.text);
      if (!ok) return 'Compte créé. Ouvre le lien reçu par email, puis connecte-toi.';
      _changed = true;
      _password.clear();
      return 'Compte créé et connecté ✔';
    });
  }

  void _sync() => _run(() async {
        await _account.sync();
        _changed = true;
        return 'Synchronisé ✔';
      });

  void _signOut() => _run(() async {
        await _account.signOut();
        return 'Déconnecté. Tes playlists restent sur cet appareil.';
      });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Compte')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                if (!Account.configured)
                  ..._notConfigured()
                else if (_account.signedIn)
                  ..._signedIn()
                else
                  ..._signedOut(),
                if (_busy) ...[
                  const SizedBox(height: 20),
                  const LinearProgressIndicator(),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _isError ? kDanger : kAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _notConfigured() => const [
        Icon(Icons.cloud_off_rounded, size: 56, color: kMuted),
        SizedBox(height: 16),
        Text(
          'Les comptes ne sont pas encore activés dans cette version.\n'
          'L\'app fonctionne normalement, sans synchronisation.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kMuted),
        ),
      ];

  List<Widget> _signedIn() => [
        const Icon(Icons.verified_user_rounded, size: 56, color: kAccent),
        const SizedBox(height: 12),
        Text(_account.email ?? '', textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text(
          'Tes playlists et favoris sont synchronisés sur tous les appareils connectés à ce compte.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kMuted),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          autofocus: true,
          onPressed: _busy ? null : _sync,
          icon: const Icon(Icons.sync_rounded),
          label: const Text('Synchroniser maintenant'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : _signOut,
          child: const Text('Se déconnecter'),
        ),
      ];

  List<Widget> _signedOut() => [
        const Icon(Icons.account_circle_rounded, size: 56, color: kMuted),
        const SizedBox(height: 12),
        const Text(
          'Connecte-toi pour retrouver tes playlists et favoris sur la TV, le PC et le téléphone.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kMuted),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _signIn(),
          decoration: const InputDecoration(labelText: 'Mot de passe', prefixIcon: Icon(Icons.lock_outline_rounded)),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: const Text('Se connecter'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _signUp,
          child: const Text('Créer un compte'),
        ),
      ];
}
