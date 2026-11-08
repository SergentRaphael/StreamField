enum SourceType { m3uUrl, file, xtream, builtin }

/// Une playlist enregistrée dans l'app (tout reste stocké sur l'appareil).
class PlaylistSource {
  PlaylistSource({
    required this.id,
    required this.name,
    required this.type,
    this.url = '',
    this.username = '',
    this.password = '',
  });

  final String id;
  String name;
  final SourceType type;

  /// Lien M3U, adresse du serveur Xtream, ou chemin de l'asset intégré.
  final String url;
  final String username;
  final String password;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'url': url,
        'username': username,
        'password': password,
      };

  factory PlaylistSource.fromJson(Map<String, dynamic> j) => PlaylistSource(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Playlist',
        type: SourceType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => SourceType.m3uUrl,
        ),
        url: j['url'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
      );
}
