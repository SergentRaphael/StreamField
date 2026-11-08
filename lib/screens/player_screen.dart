import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../models/channel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Lecteur plein écran.
/// Télécommande / clavier : ▲▼ ou CH+/CH- = changer de chaîne · OK = liste des chaînes
/// Retour = fermer · F = plein écran (PC) · M = muet · Espace = pause.
/// Tactile : toucher = afficher les commandes · glisser haut/bas = changer de chaîne.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.channels,
    required this.initialIndex,
    required this.onWatched,
  });

  final List<Channel> channels;
  final int initialIndex;
  final void Function(Channel channel) onWatched;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _itemExtent = 56.0;
  static const _maxRetries = 3;

  // ▲ / CH- = chaîne précédente · ▼ / CH+ = chaîne suivante
  static final _zapKeys = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.arrowUp: -1,
    LogicalKeyboardKey.pageUp: -1,
    LogicalKeyboardKey.channelDown: -1,
    LogicalKeyboardKey.arrowDown: 1,
    LogicalKeyboardKey.pageDown: 1,
    LogicalKeyboardKey.channelUp: 1,
  };

  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final _focus = FocusNode(debugLabel: 'player');
  final _currentItemFocus = FocusNode(debugLabel: 'current-channel');
  final _subs = <StreamSubscription<dynamic>>[];
  ScrollController? _panelScroll;

  late int _index = widget.initialIndex;
  bool _ui = true;
  bool _list = false;
  bool _buffering = true;
  bool _fullscreen = false;
  String? _error;
  int _retries = 0;
  Timer? _hideTimer;
  Timer? _retryTimer;

  Channel get _ch => widget.channels[_index];

  @override
  void initState() {
    super.initState();
    if (isMobile) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _subs.addAll([
      _player.stream.buffering.listen((b) {
        if (mounted) setState(() => _buffering = b);
      }),
      _player.stream.width.listen((w) {
        // L'image arrive : la chaîne fonctionne.
        if (w != null && w > 0) {
          _retries = 0;
          if (mounted && _error != null) setState(() => _error = null);
        }
      }),
      _player.stream.error.listen(_onFailure),
      _player.stream.completed.listen((done) {
        // Un direct ne devrait jamais « finir » : on relance.
        if (done) _onFailure('Le flux s\'est interrompu');
      }),
    ]);
    _play();
    widget.onWatched(_ch);
    _poke();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _retryTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _focus.dispose();
    _currentItemFocus.dispose();
    _panelScroll?.dispose();
    if (isMobile) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_fullscreen) windowManager.setFullScreen(false);
    super.dispose();
  }

  // ---------------- Lecture ----------------

  void _openChannel() {
    _retries = 0;
    _retryTimer?.cancel();
    setState(() {
      _error = null;
      _buffering = true;
    });
    _play();
    widget.onWatched(_ch);
    _poke();
  }

  void _play() {
    final c = _ch;
    _player.open(Media(c.url, httpHeaders: c.headers.isEmpty ? null : c.headers));
  }

  /// Reconnexion automatique (3 essais), puis message d'erreur.
  void _onFailure(String reason) {
    if (!mounted || (_retryTimer?.isActive ?? false)) return;
    if (_retries >= _maxRetries) {
      setState(() {
        _error = reason;
        _buffering = false;
      });
      return;
    }
    _retries++;
    _retryTimer = Timer(Duration(seconds: 2 * _retries), () {
      if (mounted) _play();
    });
  }

  void _zap(int delta) {
    if (widget.channels.length < 2) return;
    // En Dart, % renvoie toujours un résultat positif : on boucle sur la liste.
    _index = (_index + delta) % widget.channels.length;
    _openChannel();
  }

  void _jump(int i) {
    _closeList();
    if (i == _index) return;
    _index = i;
    _openChannel();
  }

  // ---------------- Interface ----------------

  void _poke() {
    if (!_ui) setState(() => _ui = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_list) setState(() => _ui = false);
    });
  }

  void _openList() {
    if (_list) return;
    _panelScroll?.dispose();
    _panelScroll = ScrollController(
      initialScrollOffset: math.max(0.0, (_index - 3) * _itemExtent),
    );
    setState(() => _list = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _list) _currentItemFocus.requestFocus();
    });
  }

  void _closeList() {
    if (!_list) return;
    setState(() => _list = false);
    _focus.requestFocus();
    _poke();
  }

  Future<void> _toggleFullscreen() async {
    if (!isDesktop) return;
    _fullscreen = !_fullscreen;
    await windowManager.setFullScreen(_fullscreen);
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;

    // Liste ouverte : les flèches et OK servent à naviguer dedans.
    if (_list) {
      if (e is KeyDownEvent &&
          (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack)) {
        _closeList();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final isArrow = _zapKeys.containsKey(k) ||
        k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight;

    if (e is KeyRepeatEvent) {
      return isArrow ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;

    final delta = _zapKeys[k];
    if (delta != null) {
      _zap(delta);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA) {
      _openList();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.info) {
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.mediaPlayPause) {
      _player.playOrPause();
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyM) {
      _player.setVolume(_player.state.volume > 0 ? 0.0 : 100.0);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (_fullscreen) {
        _toggleFullscreen();
      } else {
        Navigator.maybePop(context);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_list,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeList();
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: MouseRegion(
            cursor: _ui ? MouseCursor.defer : SystemMouseCursors.none,
            onHover: (_) => _poke(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_ui) {
                  setState(() => _ui = false);
                } else {
                  _poke();
                }
              },
              onDoubleTap: _toggleFullscreen,
              onVerticalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() > 300) _zap(v < 0 ? 1 : -1);
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Video(controller: _video, controls: NoVideoControls, fill: Colors.black),
                  if (_buffering && _error == null)
                    const Center(child: CircularProgressIndicator()),
                  if (_error != null) _errorCard(),
                  IgnorePointer(
                    ignoring: !_ui,
                    child: AnimatedOpacity(
                      opacity: _ui ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: _overlay(),
                    ),
                  ),
                  if (_list) ...[
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _closeList,
                        child: const ColoredBox(color: Color(0x66000000)),
                      ),
                    ),
                    _channelPanel(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay() {
    final c = _ch;
    final pad = MediaQuery.paddingOf(context);
    return ExcludeFocus(
      // Les boutons restent cliquables, mais la télécommande pilote directement le lecteur.
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(8 + pad.left, 8 + pad.top, 8 + pad.right, 32),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Retour',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Liste des chaînes (OK)',
                    icon: const Icon(Icons.format_list_bulleted_rounded),
                    onPressed: _openList,
                  ),
                  if (isDesktop)
                    IconButton(
                      tooltip: 'Plein écran (F)',
                      icon: Icon(_fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                      onPressed: _toggleFullscreen,
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20 + pad.left, 40, 12 + pad.right, 16 + pad.bottom),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xDD000000), Color(0x00000000)],
                ),
              ),
              child: Row(
                children: [
                  ChannelLogo(url: c.logo, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${c.group}  ·  ${_index + 1} / ${widget.channels.length}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: kMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Chaîne précédente (▲)',
                    icon: const Icon(Icons.skip_previous_rounded),
                    onPressed: () => _zap(-1),
                  ),
                  IconButton(
                    tooltip: 'Chaîne suivante (▼)',
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: () => _zap(1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelPanel() {
    final width = math.min(380.0, MediaQuery.sizeOf(context).width * 0.85);
    return Positioned(
      top: 0,
      bottom: 0,
      left: 0,
      width: width,
      child: Material(
        color: kBg.withAlpha(240),
        child: SafeArea(
          right: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Chaînes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    ExcludeFocus(
                      child: IconButton(
                        tooltip: 'Fermer',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _closeList,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _panelScroll,
                  itemExtent: _itemExtent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: widget.channels.length,
                  itemBuilder: (_, i) {
                    final c = widget.channels[i];
                    return ListTile(
                      focusNode: i == _index ? _currentItemFocus : null,
                      selected: i == _index,
                      leading: ChannelLogo(url: c.logo, size: 32),
                      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _jump(i),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorCard() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.signal_wifi_bad_rounded, size: 40, color: kMuted),
            const SizedBox(height: 12),
            const Text('Cette chaîne ne répond pas',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              'Elle est peut-être hors ligne, géo-bloquée ou momentanément indisponible.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMuted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(onPressed: _openChannel, child: const Text('Réessayer')),
                FilledButton(onPressed: () => _zap(1), child: const Text('Chaîne suivante')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
