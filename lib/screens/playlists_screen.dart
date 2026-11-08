import 'package:flutter/material.dart';

import '../models/playlist_source.dart';
import '../services/playlist_repository.dart';
import '../services/storage.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets.dart';

/// Liste des playlists enregistrées. Renvoie l'id de la playlist choisie.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({
    super.key,
    required this.store,
    required this.repo,
    this.activeId,
  });

  final Store store;
  final PlaylistRepository repo;
  final String? activeId;

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  late List<PlaylistSource> _sources = widget.store.sources;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Playlists')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              ListTile(
                autofocus: true,
                leading: const CircleAvatar(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.black,
                  child: Icon(Icons.add_rounded),
                ),
                title: const Text('Ajouter une playlist'),
                subtitle: const Text('Lien M3U, compte Xtream ou fichier',
                    style: TextStyle(color: kMuted)),
                onTap: _busy ? null : _add,
              ),
              const SizedBox(height: 8),
              for (final s in _sources)
                ListTile(
                  selected: s.id == widget.activeId,
                  leading: Icon(_icon(s.type)),
                  title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    _describe(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kMuted),
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Options',
                    onSelected: (v) => v == 'rename' ? _rename(s) : _delete(s),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Renommer')),
                      PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                    ],
                  ),
                  onTap: _busy ? null : () => Navigator.pop(context, s.id),
                ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x88000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  IconData _icon(SourceType t) => switch (t) {
        SourceType.builtin => Icons.verified_rounded,
        SourceType.file => Icons.insert_drive_file_rounded,
        SourceType.m3uUrl => Icons.link_rounded,
        SourceType.xtream => Icons.dns_rounded,
      };

  String _host(String url) {
    final u = Uri.tryParse(url.contains('://') ? url : 'http://$url');
    return (u == null || u.host.isEmpty) ? url : u.host;
  }

  String _describe(PlaylistSource s) => switch (s.type) {
        SourceType.builtin => 'Incluse dans StreamField',
        SourceType.file => 'Fichier enregistré sur l\'appareil',
        SourceType.m3uUrl => 'Lien · ${_host(s.url)}',
        SourceType.xtream => 'Xtream · ${s.username} @ ${_host(s.url)}',
      };

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _add() async {
    final type = await showDialog<SourceType>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Ajouter une playlist'),
        children: [
          _option(ctx, SourceType.m3uUrl, Icons.link_rounded, 'Lien M3U', 'Une adresse https://…/playlist.m3u'),
          _option(ctx, SourceType.xtream, Icons.dns_rounded, 'Compte Xtream', 'Serveur, identifiant et mot de passe'),
          _option(ctx, SourceType.file, Icons.insert_drive_file_rounded, 'Fichier', 'Un fichier .m3u ou .txt de l\'appareil'),
        ],
      ),
    );
    if (type == null || !mounted) return;

    PlaylistSource? source;
    switch (type) {
      case SourceType.m3uUrl:
        final link = await askFields(context, 'Lien M3U', const [
          FieldSpec('Nom', hint: 'Ma playlist'),
          FieldSpec('Lien', hint: 'https://exemple.com/playlist.m3u'),
        ]);
        if (link == null || link[1].trim().isEmpty) return;
        source = PlaylistSource(
          id: newId(),
          name: link[0].trim().isEmpty ? _host(link[1].trim()) : link[0].trim(),
          type: SourceType.m3uUrl,
          url: link[1].trim(),
        );
      case SourceType.xtream:
        final xt = await askFields(context, 'Compte Xtream', const [
          FieldSpec('Nom', hint: 'Mon abonnement'),
          FieldSpec('Serveur', hint: 'http://exemple.com:8080'),
          FieldSpec('Identifiant'),
          FieldSpec('Mot de passe', obscure: true),
        ]);
        if (xt == null || xt[1].trim().isEmpty || xt[2].trim().isEmpty) return;
        source = PlaylistSource(
          id: newId(),
          name: xt[0].trim().isEmpty ? _host(xt[1].trim()) : xt[0].trim(),
          type: SourceType.xtream,
          url: xt[1].trim(),
          username: xt[2].trim(),
          password: xt[3],
        );
      case SourceType.file:
        setState(() => _busy = true);
        try {
          source = await widget.repo.importFile();
        } catch (e) {
          _snack(friendlyError(e));
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      case SourceType.builtin:
        return;
    }
    if (source == null || !mounted) return;

    // On vérifie que la playlist se charge avant de l'enregistrer.
    if (type != SourceType.file) {
      setState(() => _busy = true);
      try {
        await widget.repo.load(source, refresh: true);
      } catch (e) {
        await widget.store.deleteCache(source.id);
        _snack('Impossible de charger : ${friendlyError(e)}');
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    _sources = [..._sources, source];
    await widget.store.saveSources(_sources);
    if (mounted) Navigator.pop(context, source.id);
  }

  Widget _option(BuildContext ctx, SourceType type, IconData icon, String title, String subtitle) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, type),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: kAccent),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(PlaylistSource s) async {
    final v = await askFields(context, 'Renommer', [FieldSpec('Nom', initial: s.name)]);
    final name = v?.first.trim() ?? '';
    if (name.isEmpty) return;
    setState(() => s.name = name);
    await widget.store.saveSources(_sources);
  }

  Future<void> _delete(PlaylistSource s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la playlist ?'),
        content: Text('« ${s.name} » sera retirée de StreamField.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _sources = [..._sources]..remove(s));
    await widget.store.saveSources(_sources);
    await widget.store.deleteCache(s.id);
  }
}
