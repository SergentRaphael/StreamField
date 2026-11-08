import '../models/channel.dart';

/// Écrit une liste de chaînes au format M3U (export, cache).
class M3uWriter {
  static String write(Iterable<Channel> channels) {
    final b = StringBuffer('#EXTM3U\n');
    for (final c in channels) {
      b.write('#EXTINF:-1');
      if (c.tvgId != null) b.write(' tvg-id="${_q(c.tvgId!)}"');
      if (c.logo != null) b.write(' tvg-logo="${_q(c.logo!)}"');
      b.write(' group-title="${_q(c.group)}",${c.name.replaceAll('\n', ' ')}\n');
      c.headers.forEach((key, value) {
        switch (key.toLowerCase()) {
          case 'user-agent':
            b.write('#EXTVLCOPT:http-user-agent=$value\n');
          case 'referer':
            b.write('#EXTVLCOPT:http-referrer=$value\n');
          case 'origin':
            b.write('#EXTVLCOPT:http-origin=$value\n');
        }
      });
      b.write('${c.url}\n');
    }
    return b.toString();
  }

  static String _q(String s) => s.replaceAll('"', "'");
}
