import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist_source.dart';

/// Tout est enregistré sur l'appareil : aucun compte, aucun serveur.
class Store {
  Store._(this._prefs, this._dir);

  final SharedPreferences _prefs;
  final Directory _dir;

  /// Appelé quand playlists ou favoris changent (pour la synchro du compte).
  void Function()? onChanged;
  int _mute = 0;

  void _changed() {
    if (_mute > 0) return;
    _prefs.setBool('sync_dirty', true);
    onChanged?.call();
  }

  bool get syncDirty => _prefs.getBool('sync_dirty') ?? false;
  Future<void> clearDirty() => _prefs.setBool('sync_dirty', false);

  static Future<Store> open() async {
    final prefs = await SharedPreferences.getInstance();
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}playlists');
    await dir.create(recursive: true);
    return Store._(prefs, dir);
  }

  // ---- Playlists ----

  List<PlaylistSource> get sources {
    final raw = _prefs.getString('sources');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => PlaylistSource.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSources(List<PlaylistSource> list) async {
    await _prefs.setString('sources', jsonEncode([for (final s in list) s.toJson()]));
    _changed();
  }

  bool get initialized => _prefs.getBool('initialized') ?? false;
  Future<void> setInitialized() => _prefs.setBool('initialized', true);

  String? get activeId => _prefs.getString('active');
  Future<void> setActiveId(String id) => _prefs.setString('active', id);

  // ---- Favoris & récents ----

  Set<String> get favorites => (_prefs.getStringList('favorites') ?? []).toSet();
  Future<void> saveFavorites(Set<String> urls) async {
    await _prefs.setStringList('favorites', urls.toList());
    _changed();
  }

  List<String> get recents => _prefs.getStringList('recents') ?? [];
  Future<void> addRecent(String url) {
    final list = [...recents]
      ..remove(url)
      ..insert(0, url);
    return _prefs.setStringList('recents', list.take(30).toList());
  }

  // ---- Cache des playlists (démarrage instantané, marche même si le lien tombe) ----

  File _cache(String id) => File('${_dir.path}${Platform.pathSeparator}$id.m3u');

  Future<String?> readCache(String id) async {
    final f = _cache(id);
    if (!await f.exists()) return null;
    return utf8.decode(await f.readAsBytes(), allowMalformed: true);
  }

  Future<Duration> cacheAge(String id) async {
    final f = _cache(id);
    if (!await f.exists()) return const Duration(days: 9999);
    return DateTime.now().difference(await f.lastModified());
  }

  Future<void> writeCache(String id, String content) =>
      _cache(id).writeAsString(content, flush: true);

  Future<void> deleteCache(String id) async {
    final f = _cache(id);
    if (await f.exists()) await f.delete();
  }

  // ---- Synchro du compte ----

  /// Tout ce qui part sur le compte : playlists, favoris, récents
  /// (+ contenu des fichiers importés, qui n'existent que sur cet appareil).
  Future<Map<String, dynamic>> snapshot() async {
    final list = sources;
    final files = <String, String>{};
    for (final s in list.where((s) => s.type == SourceType.file)) {
      final content = await readCache(s.id);
      if (content != null && content.length < 3000000) files[s.id] = content;
    }
    return {
      'v': 1,
      'sources': [for (final s in list) s.toJson()],
      'favorites': favorites.toList(),
      'recents': recents,
      'files': files,
    };
  }

  /// Applique les données du compte. [merge] = garder aussi ce qui est sur l'appareil.
  Future<void> applySnapshot(Map<String, dynamic> data, {bool merge = false}) async {
    _mute++;
    try {
      final remote = [
        for (final e in (data['sources'] as List? ?? const []))
          if (e is Map) PlaylistSource.fromJson(Map<String, dynamic>.from(e)),
      ];
      final local = sources;
      final remoteIds = {for (final s in remote) s.id};
      final result = merge
          ? [...remote, ...local.where((s) => !remoteIds.contains(s.id))]
          : remote;
      if (!merge) {
        for (final s in local.where((s) => !remoteIds.contains(s.id))) {
          await deleteCache(s.id);
        }
      }

      final files = data['files'];
      if (files is Map) {
        for (final s in remote.where((s) => s.type == SourceType.file)) {
          final content = files[s.id];
          if (content is String) await writeCache(s.id, content);
        }
      }
      await saveSources(result);

      final favs = {for (final e in (data['favorites'] as List? ?? const [])) '$e'};
      await saveFavorites(merge ? {...favorites, ...favs} : favs);

      final rec = [for (final e in (data['recents'] as List? ?? const [])) '$e'];
      final allRec = merge ? [...rec, ...recents.where((u) => !rec.contains(u))] : rec;
      await _prefs.setStringList('recents', allRec.take(30).toList());

      await setInitialized();
    } finally {
      _mute--;
    }
  }
}
