import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'storage.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Compte StreamField : connexion email + mot de passe et synchro des playlists,
/// favoris et chaînes récentes entre tous les appareils.
/// Simples requêtes HTTP vers Supabase (aucun module supplémentaire = app plus légère).
class Account {
  Account._(this._prefs, this.store);

  static Future<Account> open(Store store) async {
    final account = Account._(await SharedPreferences.getInstance(), store);
    store.onChanged = account._schedulePush;
    return account;
  }

  final SharedPreferences _prefs;
  final Store store;
  Timer? _pushTimer;

  static bool get configured => kSupabaseUrl.isNotEmpty && kSupabaseKey.isNotEmpty;

  String? get email => _prefs.getString('acc_email');
  String? get _userId => _prefs.getString('acc_uid');
  String? get _access => _prefs.getString('acc_access');
  String? get _refresh => _prefs.getString('acc_refresh');
  int get _expiresAt => _prefs.getInt('acc_expires') ?? 0;

  bool get signedIn => configured && _refresh != null && _userId != null;

  String get _base => kSupabaseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _anonHeaders => {
        'apikey': kSupabaseKey,
        'Content-Type': 'application/json',
      };

  Map<String, String> _authed(String token) => {
        ..._anonHeaders,
        'Authorization': 'Bearer $token',
      };

  // ---------------- Connexion ----------------

  Future<void> signIn(String email, String password) async {
    final j = await _authPost('token?grant_type=password', {
      'email': email.trim(),
      'password': password,
    });
    await _saveSession(j);
    await _firstSync();
  }

  /// Renvoie false si Supabase demande de confirmer l'email avant de se connecter.
  Future<bool> signUp(String email, String password) async {
    final j = await _authPost('signup', {
      'email': email.trim(),
      'password': password,
    });
    if (j['access_token'] == null) return false;
    await _saveSession(j);
    await _firstSync();
    return true;
  }

  Future<void> signOut() async {
    _pushTimer?.cancel();
    final token = _access;
    if (token != null) {
      try {
        await http
            .post(Uri.parse('$_base/auth/v1/logout'), headers: _authed(token))
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    for (final k in ['acc_access', 'acc_refresh', 'acc_expires', 'acc_uid', 'acc_email']) {
      await _prefs.remove(k);
    }
  }

  Future<Map<String, dynamic>> _authPost(String path, Map<String, dynamic> body) async {
    final res = await http
        .post(Uri.parse('$_base/auth/v1/$path'), headers: _anonHeaders, body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    Map<String, dynamic> j = {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map) j = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (res.statusCode >= 400) throw AuthException(_authMessage(j, res.statusCode));
    return j;
  }

  static String _authMessage(Map<String, dynamic> j, int code) {
    final raw = [j['error_code'], j['code'], j['msg'], j['message'], j['error_description'], j['error']]
        .whereType<Object>()
        .join(' ')
        .toLowerCase();
    if (raw.contains('invalid_credentials') || raw.contains('invalid login') || raw.contains('invalid_grant')) {
      return 'Email ou mot de passe incorrect.';
    }
    if (raw.contains('not_confirmed') || raw.contains('not confirmed')) {
      return 'Confirme d\'abord ton compte avec le lien reçu par email.';
    }
    if (raw.contains('already') || raw.contains('exists')) {
      return 'Un compte existe déjà avec cet email : connecte-toi.';
    }
    if (raw.contains('weak_password') || raw.contains('password should')) {
      return 'Mot de passe trop court (6 caractères minimum).';
    }
    if (raw.contains('email_address_invalid') || raw.contains('invalid format') || raw.contains('email address')) {
      return 'Adresse email invalide.';
    }
    if (code == 429) return 'Trop d\'essais. Réessaie dans quelques minutes.';
    return 'Le serveur de comptes a répondu une erreur ($code).';
  }

  Future<void> _saveSession(Map<String, dynamic> j) async {
    final access = j['access_token'];
    final refresh = j['refresh_token'];
    if (access is! String || refresh is! String) {
      throw AuthException('Réponse inattendue du serveur de comptes.');
    }
    final expiresIn = (j['expires_in'] as num?)?.toInt() ?? 3600;
    await _prefs.setString('acc_access', access);
    await _prefs.setString('acc_refresh', refresh);
    await _prefs.setInt(
        'acc_expires', DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn - 60);
    final user = j['user'];
    if (user is Map) {
      await _prefs.setString('acc_uid', '${user['id']}');
      if (user['email'] != null) await _prefs.setString('acc_email', '${user['email']}');
    }
  }

  Future<String> _token() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final access = _access;
    if (access != null && now < _expiresAt) return access;
    final refresh = _refresh;
    if (refresh == null) throw AuthException('Session expirée : reconnecte-toi.');
    try {
      await _saveSession(
          await _authPost('token?grant_type=refresh_token', {'refresh_token': refresh}));
    } on AuthException {
      await signOut();
      throw AuthException('Session expirée : reconnecte-toi.');
    }
    return _access!;
  }

  // ---------------- Synchro ----------------

  /// À la connexion : on fusionne l'appareil avec le compte, puis on envoie le tout.
  Future<void> _firstSync() async {
    final remote = await _download();
    if (remote != null) await store.applySnapshot(remote, merge: true);
    await _upload();
  }

  /// Au démarrage et avec « Synchroniser maintenant ».
  /// Le compte fait foi, sauf si l'appareil a des changements pas encore envoyés.
  Future<void> sync() async {
    if (!signedIn) return;
    _pushTimer?.cancel();
    final remote = await _download();
    if (remote == null) {
      await _upload();
    } else if (store.syncDirty) {
      await store.applySnapshot(remote, merge: true);
      await _upload();
    } else {
      await store.applySnapshot(remote);
    }
  }

  void _schedulePush() {
    if (!signedIn) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 3), () async {
      try {
        await _upload();
      } catch (_) {
        // Pas de réseau : les changements restent en attente et partent au prochain démarrage.
      }
    });
  }

  Future<Map<String, dynamic>?> _download() async {
    final token = await _token();
    final res = await http
        .get(Uri.parse('$_base/rest/v1/user_data?select=data&user_id=eq.$_userId'),
            headers: _authed(token))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode >= 400) throw Exception(_restMessage(res));
    final list = jsonDecode(utf8.decode(res.bodyBytes));
    if (list is! List || list.isEmpty) return null;
    final data = (list.first as Map)['data'];
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  Future<void> _upload() async {
    final token = await _token();
    final body = jsonEncode({
      'user_id': _userId,
      'data': await store.snapshot(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final res = await http
        .post(
          Uri.parse('$_base/rest/v1/user_data?on_conflict=user_id'),
          headers: {..._authed(token), 'Prefer': 'resolution=merge-duplicates,return=minimal'},
          body: body,
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode >= 400) throw Exception(_restMessage(res));
    await store.clearDirty();
  }

  static String _restMessage(http.Response res) {
    if (res.statusCode == 404 || res.body.contains('PGRST205') || res.body.contains('42P01')) {
      return 'La table « user_data » n\'existe pas encore : colle supabase/schema.sql dans Supabase.';
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      return 'Accès refusé par le serveur de comptes.';
    }
    return 'Erreur de synchronisation (${res.statusCode}).';
  }
}
