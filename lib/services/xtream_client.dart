import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';

/// Connexion à un serveur « Xtream Codes » (adresse + identifiant + mot de passe).
class XtreamClient {
  XtreamClient(String server, this.username, this.password)
      : server = normalizeServer(server);

  final String server;
  final String username;
  final String password;

  static String normalizeServer(String s) {
    var v = s.trim();
    if (!v.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      v = 'http://$v';
    }
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  Future<List<dynamic>> _list(String action) async {
    final uri = Uri.parse('$server/player_api.php').replace(queryParameters: {
      'username': username,
      'password': password,
      'action': action,
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 40));
    if (res.statusCode != 200) {
      throw Exception('Serveur Xtream : erreur HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (data is List) return data;
    throw Exception('Identifiant ou mot de passe refusé par le serveur');
  }

  /// Chaînes en direct, classées par catégorie.
  Future<List<Channel>> liveChannels() async {
    final categories = await _list('get_live_categories');
    final names = <String, String>{
      for (final c in categories.whereType<Map>())
        '${c['category_id']}': _s(c['category_name']) ?? 'Sans catégorie',
    };
    final streams = await _list('get_live_streams');
    final user = Uri.encodeComponent(username);
    final pass = Uri.encodeComponent(password);
    return [
      for (final s in streams.whereType<Map>())
        if (s['stream_id'] != null)
          Channel(
            name: _s(s['name']) ?? 'Sans nom',
            url: '$server/live/$user/$pass/${s['stream_id']}.ts',
            group: names['${s['category_id']}'] ?? 'Sans catégorie',
            logo: _s(s['stream_icon']),
            tvgId: _s(s['epg_channel_id']),
          ),
    ];
  }

  static String? _s(dynamic v) {
    final t = v?.toString().trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
