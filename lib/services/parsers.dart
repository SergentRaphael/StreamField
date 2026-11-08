import '../models/channel.dart';

/// Détecte le format et renvoie les chaînes.
/// Fonction de premier niveau pour pouvoir tourner en arrière-plan (compute).
List<Channel> parsePlaylist(String content) {
  final text = content.replaceFirst('﻿', '');
  return text.contains('#EXTINF')
      ? M3uParser.parse(text)
      : TextListParser.parse(text);
}

/// Sépare l'URL des en-têtes au format « url|User-Agent=xxx&Referer=yyy ».
(String, Map<String, String>) splitUrlHeaders(String raw) {
  final i = raw.indexOf('|');
  if (i < 0) return (raw.trim(), const <String, String>{});
  final headers = <String, String>{};
  for (final part in raw.substring(i + 1).split('&')) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    var value = part.substring(eq + 1).trim();
    try {
      value = Uri.decodeComponent(value);
    } catch (_) {}
    headers[part.substring(0, eq).trim()] = value;
  }
  return (raw.substring(0, i).trim(), headers);
}

/// Format M3U / M3U8 classique (#EXTM3U + #EXTINF).
class M3uParser {
  static final _attr = RegExp(r'([\w-]+)="([^"]*)"');

  static List<Channel> parse(String content) {
    final out = <Channel>[];
    Map<String, String>? attrs;
    String? name;
    String? extGroup;
    var headers = <String, String>{};

    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF')) {
        attrs = {
          for (final m in _attr.allMatches(line))
            m.group(1)!.toLowerCase(): m.group(2)!,
        };
        final comma = _nameComma(line);
        name = comma >= 0 ? line.substring(comma + 1).trim() : null;
        final ua = attrs['user-agent'] ?? attrs['http-user-agent'];
        if (ua != null && ua.isNotEmpty) headers['User-Agent'] = ua;
        final ref = attrs['referer'] ?? attrs['http-referrer'];
        if (ref != null && ref.isNotEmpty) headers['Referer'] = ref;
      } else if (line.startsWith('#EXTGRP:')) {
        extGroup = line.substring(8).trim();
      } else if (line.startsWith('#EXTVLCOPT:')) {
        final opt = line.substring(11);
        final eq = opt.indexOf('=');
        if (eq > 0) {
          final key = opt.substring(0, eq).trim().toLowerCase();
          final value = opt.substring(eq + 1).trim();
          if (key == 'http-user-agent') {
            headers['User-Agent'] = value;
          } else if (key == 'http-referrer' || key == 'http-referer') {
            headers['Referer'] = value;
          } else if (key == 'http-origin') {
            headers['Origin'] = value;
          }
        }
      } else if (line.startsWith('#')) {
        continue; // #EXTM3U et autres commentaires
      } else {
        if (attrs == null && !line.contains('://')) continue;
        final (url, extra) = splitUrlHeaders(line);
        final a = attrs ?? const <String, String>{};
        final group = a['group-title'];
        final logo = a['tvg-logo'];
        final tvgId = a['tvg-id'];
        out.add(Channel(
          name: (name != null && name.isNotEmpty)
              ? name
              : (a['tvg-name'] ?? url),
          url: url,
          group: (group != null && group.trim().isNotEmpty)
              ? group.trim()
              : (extGroup ?? 'Sans catégorie'),
          logo: (logo != null && logo.isNotEmpty) ? logo : null,
          tvgId: (tvgId != null && tvgId.isNotEmpty) ? tvgId : null,
          headers: {...headers, ...extra},
        ));
        attrs = null;
        name = null;
        extGroup = null;
        headers = <String, String>{};
      }
    }
    return out;
  }

  /// Virgule qui sépare les attributs du nom (hors guillemets).
  static int _nameComma(String line) {
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ',' && !inQuotes) {
        return i;
      }
    }
    return -1;
  }
}

/// Liste en texte simple : un nom sur une ligne, le lien juste en dessous
/// (ou « Nom : lien » sur la même ligne). Accepte le Markdown.
class TextListParser {
  static final _url = RegExp(
    r'''(?:https?|rtmps?|rtsp|udp)://[^\s`"'<>]+''',
    caseSensitive: false,
  );

  static List<Channel> parse(String content) {
    final out = <Channel>[];
    String? pendingName;
    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('```')) continue;
      final m = _url.firstMatch(line);
      if (m == null) {
        final cleaned = _clean(line);
        if (cleaned.isNotEmpty) pendingName = cleaned;
        continue;
      }
      var link = m.group(0)!;
      // Lien Markdown [nom](url) : on retire la parenthèse finale en trop.
      while (link.endsWith(')') &&
          '('.allMatches(link).length < ')'.allMatches(link).length) {
        link = link.substring(0, link.length - 1);
      }
      final (url, headers) = splitUrlHeaders(link);
      final before = _clean(line.substring(0, m.start));
      out.add(Channel(
        name: before.isNotEmpty ? before : (pendingName ?? url),
        url: url,
        headers: headers,
      ));
      pendingName = null;
    }
    return out;
  }

  static String _clean(String s) => s
      .replaceAll(RegExp(r'[*`#>\[\]]'), '')
      .replaceAll(RegExp(r'^[\s\-•]+'), '')
      .replaceAll(RegExp(r'[\s:=\-|(]+$'), '')
      .trim();
}
