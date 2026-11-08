import 'package:flutter_test/flutter_test.dart';
import 'package:streamfield/services/m3u_writer.dart';
import 'package:streamfield/services/parsers.dart';

void main() {
  test('M3U : attributs, nom, groupe et en-têtes', () {
    const m3u = '''
#EXTM3U
#EXTINF:-1 tvg-id="f24.fr" tvg-logo="https://ex.com/f24.png" group-title="Infos, Monde",France 24
https://example.com/f24.m3u8
#EXTINF:-1,Chaîne simple
#EXTGRP:Divers
#EXTVLCOPT:http-user-agent=MonLecteur
http://example.com/live.ts
#EXTINF:-1 group-title="Sport",Avec pipe
http://example.com/a.m3u8|Referer=https://site.fr&User-Agent=Test
''';
    final list = parsePlaylist(m3u);
    expect(list.length, 3);
    expect(list[0].name, 'France 24');
    expect(list[0].group, 'Infos, Monde');
    expect(list[0].tvgId, 'f24.fr');
    expect(list[1].group, 'Divers');
    expect(list[1].headers['User-Agent'], 'MonLecteur');
    expect(list[2].url, 'http://example.com/a.m3u8');
    expect(list[2].headers['Referer'], 'https://site.fr');
  });

  test('Liste texte / Markdown : nom puis lien', () {
    const txt = '''
Quelques chaînes :

**Ma Chaîne (1080p)**
  ```
  https://cdn.example.com/live/playlist.m3u8
  ```
Autre chaîne : http://1.2.3.4:8080/live/index.m3u8
''';
    final list = parsePlaylist(txt);
    expect(list.length, 2);
    expect(list[0].name, 'Ma Chaîne (1080p)');
    expect(list[0].url, 'https://cdn.example.com/live/playlist.m3u8');
    expect(list[1].name, 'Autre chaîne');
  });

  test('Export puis relecture : rien ne se perd', () {
    final original = parsePlaylist('''
#EXTM3U
#EXTINF:-1 tvg-logo="https://ex.com/l.png" group-title="Sport",Test
#EXTVLCOPT:http-referrer=https://ref.fr
https://example.com/s.m3u8
''');
    final again = parsePlaylist(M3uWriter.write(original));
    expect(again.single.name, 'Test');
    expect(again.single.group, 'Sport');
    expect(again.single.logo, 'https://ex.com/l.png');
    expect(again.single.headers['Referer'], 'https://ref.fr');
  });
}
