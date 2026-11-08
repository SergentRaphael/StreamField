import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/channel.dart';
import '../models/playlist_source.dart';
import 'm3u_writer.dart';
import 'parsers.dart';
import 'storage.dart';
import 'xtream_client.dart';

const kUserAgent = 'StreamField/1.0';

String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

class PlaylistRepository {
  PlaylistRepository(this.store);

  final Store store;

  /// Playlists ajoutées au premier lancement.
  /// Avec --dart-define=STORE_BUILD=true (version App Store / Play Store),
  /// l'app démarre vide : l'utilisateur ajoute ses propres playlists.
  static List<PlaylistSource> defaults() => const bool.fromEnvironment('STORE_BUILD')
      ? []
      : [
        PlaylistSource(
          id: 'sport-gratuit',
          name: 'Sport gratuit',
          type: SourceType.builtin,
          url: 'assets/playlists/sport_gratuit.m3u',
        ),
        PlaylistSource(
          id: 'fr-gratuit',
          name: 'Chaînes FR gratuites',
          type: SourceType.m3uUrl,
          url: 'https://iptv-org.github.io/iptv/countries/fr.m3u',
        ),
      ];

  /// Charge une playlist : depuis le cache de l'appareil si possible,
  /// sinon (ou si [refresh]) depuis sa source.
  Future<List<Channel>> load(PlaylistSource s, {bool refresh = false}) async {
    final useCache = !refresh || s.type == SourceType.file;
    String? text = useCache ? await store.readCache(s.id) : null;
    if (text == null) {
      text = await _fetch(s);
      await store.writeCache(s.id, text);
    }
    // Analyse en arrière-plan : l'interface reste fluide même avec 50 000 chaînes.
    final channels = await compute(parsePlaylist, text);
    if (channels.isEmpty) {
      throw Exception('Aucune chaîne trouvée dans « ${s.name} »');
    }
    return channels;
  }

  Future<String> _fetch(PlaylistSource s) async {
    switch (s.type) {
      case SourceType.builtin:
        return rootBundle.loadString(s.url);
      case SourceType.m3uUrl:
        final res = await http.get(Uri.parse(s.url.trim()),
            headers: {'User-Agent': kUserAgent}).timeout(const Duration(seconds: 45));
        if (res.statusCode != 200) {
          throw Exception('Le lien répond avec une erreur ${res.statusCode}');
        }
        return utf8.decode(res.bodyBytes, allowMalformed: true);
      case SourceType.xtream:
        final channels =
            await XtreamClient(s.url, s.username, s.password).liveChannels();
        return M3uWriter.write(channels);
      case SourceType.file:
        throw Exception('Fichier introuvable : ajoute-le à nouveau');
    }
  }

  /// Ouvre un fichier .m3u / .txt de l'appareil et l'enregistre comme playlist.
  Future<PlaylistSource?> importFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) throw Exception('Impossible de lire ce fichier');
    final text = utf8.decode(bytes, allowMalformed: true);
    final channels = await compute(parsePlaylist, text);
    if (channels.isEmpty) throw Exception('Aucune chaîne trouvée dans ce fichier');
    final source = PlaylistSource(
      id: newId(),
      name: file.name.replaceAll(
          RegExp(r'\.(m3u8?|txt|md)$', caseSensitive: false), ''),
      type: SourceType.file,
    );
    await store.writeCache(source.id, text);
    return source;
  }

  /// Garde la version nettoyée (sans les chaînes hors ligne) sur l'appareil.
  Future<void> saveCleaned(PlaylistSource s, List<Channel> channels) =>
      store.writeCache(s.id, M3uWriter.write(channels));
}
