import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../models/playlist_source.dart';
import '../services/account.dart';
import '../services/m3u_writer.dart';
import '../services/playlist_repository.dart';
import '../services/storage.dart';
import '../services/stream_checker.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets.dart';
import 'account_screen.dart';
import 'player_screen.dart';
import 'playlists_screen.dart';

// Vues spéciales (le caractère \u0000 évite toute collision avec un nom de catégorie).
const _kAll = '\u0000all';
const _kFavs = '\u0000favs';
const _kRecents = '\u0000recents';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.account});

  final Store store;
  final Account account;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Store get _store => widget.store;
  late final PlaylistRepository _repo = PlaylistRepository(widget.store);
  final _checker = StreamChecker();
  final _search = TextEditingController();

  List<PlaylistSource> _sources = [];
  PlaylistSource? _active;
  List<Channel> _channels = [];
  Map<String, int> _groups = {};
  late Set<String> _favorites = _store.favorites;
  String _view = _kAll;
  String _query = '';
  bool _loading = true;
  String? _error;

  bool _checking = false;
  bool _cancel = false;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _cancel = true;
    _search.dispose();
    super.dispose();
  }

  // ---------------- Chargement ----------------

  Future<void> _bootstrap() async {
    await Future<void>.delayed(Duration.zero); // laisse l'écran s'afficher d'abord
    if (!_store.initialized) {
      await _store.saveSources(PlaylistRepository.defaults());
      await _store.setInitialized();
    }
    if (widget.account.signedIn) {
      try {
        // Récupère les playlists et favoris du compte (sans bloquer si pas de réseau).
        await widget.account.sync().timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    final migrated = PlaylistRepository.migrate(_store.sources);
    if (migrated != null) {
      await _store.saveSources(migrated);
      if (!migrated.any((s) => s.id == _store.activeId) && migrated.isNotEmpty) {
        await _store.setActiveId(migrated.first.id);
      }
    }
    _favorites = _store.favorites;
    _sources = _store.sources;
    final active = _sources.where((s) => s.id == _store.activeId).firstOrNull ??
        _sources.firstOrNull;
    if (active != null) {
      await _open(active);
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _open(PlaylistSource source, {bool refresh = false}) async {
    _cancel = true; // arrête un test en cours
    setState(() {
      _active = source;
      _loading = true;
      _error = null;
    });
    try {
      final channels = await _repo.load(source, refresh: refresh);
      await _store.setActiveId(source.id);
      if (!mounted) return;
      _setChannels(channels);
      _view = _kAll;
      _query = '';
      _search.clear();
    } catch (e) {
      _error = friendlyError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setChannels(List<Channel> channels) {
    final groups = <String, int>{};
    for (final c in channels) {
      groups[c.group] = (groups[c.group] ?? 0) + 1;
    }
    _channels = channels;
    _groups = groups;
    if (!_view.startsWith('\u0000') && !_groups.containsKey(_view)) _view = _kAll;
  }

  Future<void> _managePlaylists() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistsScreen(store: _store, repo: _repo, activeId: _active?.id),
      ),
    );
    if (!mounted) return;
    await _reloadFromStore(id);
  }

  Future<void> _openAccount() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AccountScreen(account: widget.account)),
    );
    if (!mounted) return;
    if (changed == true) {
      await _reloadFromStore(null, forceReopen: true);
    } else {
      setState(() {}); // icône du compte
    }
  }

  /// Relit playlists et favoris (après gestion des playlists ou synchro du compte).
  Future<void> _reloadFromStore(String? id, {bool forceReopen = false}) async {
    _sources = _store.sources;
    _favorites = _store.favorites;
    final wanted = id ?? _active?.id ?? _store.activeId;
    final target = _sources.where((s) => s.id == wanted).firstOrNull;
    if (target == null) {
      // La playlist active a été supprimée.
      if (_sources.isNotEmpty) {
        await _open(_sources.first);
      } else {
        setState(() {
          _active = null;
          _error = null;
          _channels = [];
          _groups = {};
        });
      }
    } else if (forceReopen || target.id != _active?.id || _error != null) {
      await _open(target);
    } else {
      setState(() => _active = target); // le nom a peut-être changé
    }
  }

  // ---------------- Filtres ----------------

  List<Channel> _visible() {
    Iterable<Channel> list = switch (_view) {
      _kAll => _channels,
      _kFavs => _channels.where((c) => _favorites.contains(c.url)),
      _kRecents => _recentChannels(),
      _ => _channels.where((c) => c.group == _view),
    };
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) list = list.where((c) => c.name.toLowerCase().contains(q));
    return list.toList();
  }

  Iterable<Channel> _recentChannels() {
    final byUrl = {for (final c in _channels) c.url: c};
    return _store.recents.map((u) => byUrl[u]).whereType<Channel>();
  }

  List<(String, String, IconData?, int?)> get _navEntries => [
        (_kAll, 'Toutes les chaînes', Icons.apps_rounded, _channels.length),
        (_kFavs, 'Favoris', Icons.star_rounded, null),
        (_kRecents, 'Récents', Icons.history_rounded, null),
        for (final e in _groups.entries) (e.key, e.key, null, e.value),
      ];

  // ---------------- Actions ----------------

  void _toggleFavorite(Channel c) {
    setState(() {
      if (!_favorites.remove(c.url)) _favorites.add(c.url);
    });
    _store.saveFavorites(_favorites);
  }

  Future<void> _play(List<Channel> list, int index) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          channels: list,
          initialIndex: index,
          onWatched: (c) => _store.addRecent(c.url),
        ),
      ),
    );
    if (mounted) setState(() {}); // met à jour « Récents »
  }

  Future<void> _runCheck() async {
    final targets = _visible();
    if (targets.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _cancel = false;
      _done = 0;
      _total = targets.length;
    });
    await _checker.checkAll(
      targets,
      isCancelled: () => _cancel,
      onProgress: (done, _) {
        if (mounted) setState(() => _done = done);
      },
    );
    if (!mounted) return;
    setState(() => _checking = false);
    final ok = targets.where((c) => c.status == StreamStatus.ok).length;
    final dead = targets.where((c) => c.status == StreamStatus.dead).length;
    _snack('Test terminé : $ok en ligne · $dead hors ligne');
  }

  Future<void> _removeDead() async {
    final kept = _channels.where((c) => c.status != StreamStatus.dead).toList();
    final removed = _channels.length - kept.length;
    if (removed == 0) {
      _snack('Rien à retirer. Lance d\'abord « Tester les chaînes ».');
      return;
    }
    setState(() => _setChannels(kept));
    final active = _active;
    if (active != null) await _repo.saveCleaned(active, kept);
    _snack('$removed chaîne${removed > 1 ? 's' : ''} hors ligne retirée${removed > 1 ? 's' : ''}');
  }

  Future<void> _export() async {
    final list = _visible();
    if (list.isEmpty) return;
    final bytes = Uint8List.fromList(utf8.encode(M3uWriter.write(list)));
    final base = (_active?.name ?? 'playlist').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final mobile = Platform.isAndroid || Platform.isIOS;
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Exporter la playlist',
        fileName: '$base.m3u',
        bytes: mobile ? bytes : null,
      );
      if (path == null) return;
      if (!mobile) await File(path).writeAsBytes(bytes);
      _snack('${list.length} chaînes exportées');
    } catch (e) {
      _snack('Export impossible : ${friendlyError(e)}');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- Interface ----------------

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final visible = _visible();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(wide),
            if (!wide && _channels.isNotEmpty && !_loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _searchField(),
              ),
            if (_checking) _checkBar(),
            Expanded(child: _body(wide, visible)),
          ],
        ),
      ),
    );
  }

  Widget _header(bool wide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          const Wordmark(),
          const SizedBox(width: 16),
          Flexible(child: _playlistButton()),
          if (wide && _channels.isNotEmpty) ...[
            const SizedBox(width: 16),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: _searchField(),
                ),
              ),
            ),
          ] else
            const Spacer(),
          IconButton(
            tooltip: widget.account.signedIn ? 'Compte : ${widget.account.email ?? ''}' : 'Compte',
            icon: Icon(
              widget.account.signedIn ? Icons.account_circle_rounded : Icons.account_circle_outlined,
              color: widget.account.signedIn ? kAccent : null,
            ),
            onPressed: _openAccount,
          ),
          IconButton(
            tooltip: 'Actualiser la playlist',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: (_active == null || _loading) ? null : () => _open(_active!, refresh: true),
          ),
          _menu(),
        ],
      ),
    );
  }

  Widget _playlistButton() {
    return TextButton(
      onPressed: _managePlaylists,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: kSurface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.playlist_play_rounded, size: 20, color: kAccent),
          const SizedBox(width: 8),
          Flexible(child: Text(_active?.name ?? 'Playlists', overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded, size: 18),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: 'Rechercher une chaîne',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
      ),
    );
  }

  Widget _menu() {
    return PopupMenuButton<String>(
      tooltip: 'Outils',
      icon: const Icon(Icons.more_vert_rounded),
      enabled: _channels.isNotEmpty && !_loading,
      onSelected: (v) {
        switch (v) {
          case 'check':
            _runCheck();
          case 'stop':
            _cancel = true;
          case 'clean':
            _removeDead();
          case 'export':
            _export();
        }
      },
      itemBuilder: (_) => [
        if (!_checking)
          const PopupMenuItem(
            value: 'check',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.network_check_rounded),
              title: Text('Tester les chaînes affichées'),
            ),
          )
        else
          const PopupMenuItem(
            value: 'stop',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.stop_circle_outlined),
              title: Text('Arrêter le test'),
            ),
          ),
        const PopupMenuItem(
          value: 'clean',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cleaning_services_rounded),
            title: Text('Retirer les chaînes hors ligne'),
          ),
        ),
        const PopupMenuItem(
          value: 'export',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.save_alt_rounded),
            title: Text('Exporter en .m3u'),
          ),
        ),
      ],
    );
  }

  Widget _checkBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _total == 0 ? null : _done / _total,
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('Test $_done / $_total', style: const TextStyle(color: kMuted)),
          TextButton(onPressed: () => _cancel = true, child: const Text('Arrêter')),
        ],
      ),
    );
  }

  Widget _body(bool wide, List<Channel> visible) {
    if (_loading) {
      return _centered(
        loading: true,
        title: _active == null ? 'Chargement…' : 'Chargement de « ${_active!.name} »…',
      );
    }
    if (_error != null && _active != null) {
      return _centered(
        icon: Icons.cloud_off_rounded,
        title: 'Impossible de charger la playlist',
        message: _error,
        actions: [
          OutlinedButton(onPressed: _managePlaylists, child: const Text('Changer de playlist')),
          FilledButton(
            autofocus: true,
            onPressed: () => _open(_active!, refresh: true),
            child: const Text('Réessayer'),
          ),
        ],
      );
    }
    if (_active == null) {
      return _centered(
        icon: Icons.playlist_add_rounded,
        title: 'Aucune playlist',
        message: 'Ajoute un lien M3U, un compte Xtream ou un fichier.',
        actions: [
          FilledButton(
            autofocus: true,
            onPressed: _managePlaylists,
            child: const Text('Ajouter une playlist'),
          ),
        ],
      );
    }
    final list = _channelList(visible);
    if (!wide) return Column(children: [_chips(), Expanded(child: list)]);
    return Row(
      children: [
        SizedBox(width: 250, child: _sidebar()),
        const VerticalDivider(width: 1),
        Expanded(child: list),
      ],
    );
  }

  Widget _centered({
    IconData? icon,
    required String title,
    String? message,
    bool loading = false,
    List<Widget> actions = const [],
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator()
            else if (icon != null)
              Icon(icon, size: 56, color: kMuted),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: actions),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sidebar() {
    final entries = _navEntries;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      itemCount: entries.length + 1,
      itemBuilder: (context, i) {
        if (i == 3) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              'CATÉGORIES',
              style: TextStyle(color: kMuted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600),
            ),
          );
        }
        final (id, label, icon, count) = entries[i > 3 ? i - 1 : i];
        return ListTile(
          dense: true,
          selected: _view == id,
          leading: icon == null ? null : Icon(icon, size: 20),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: count == null
              ? null
              : Text('$count', style: const TextStyle(color: kMuted, fontSize: 12)),
          onTap: () => setState(() => _view = id),
        );
      },
    );
  }

  Widget _chips() {
    final entries = _navEntries;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (id, label, icon, _) = entries[i];
          return ChoiceChip(
            label: Text(label),
            avatar: icon == null ? null : Icon(icon, size: 16),
            selected: _view == id,
            showCheckmark: false,
            onSelected: (_) => setState(() => _view = id),
          );
        },
      ),
    );
  }

  Widget _channelList(List<Channel> visible) {
    if (visible.isEmpty) {
      final msg = switch (_view) {
        _ when _query.isNotEmpty => 'Aucun résultat pour « $_query »',
        _kFavs => 'Pas encore de favoris.\nAppuie sur ☆ à côté d\'une chaîne pour l\'ajouter.',
        _kRecents => 'Les chaînes que tu regardes apparaîtront ici.',
        _ => 'Aucune chaîne ici.',
      };
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${visible.length} chaîne${visible.length > 1 ? 's' : ''}',
              style: const TextStyle(color: kMuted, fontSize: 12),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final c = visible[i];
              return ChannelTile(
                channel: c,
                favorite: _favorites.contains(c.url),
                autofocus: i == 0,
                onTap: () => _play(visible, i),
                onFavorite: () => _toggleFavorite(c),
              );
            },
          ),
        ),
      ],
    );
  }
}
