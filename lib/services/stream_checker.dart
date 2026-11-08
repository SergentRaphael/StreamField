import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
import 'playlist_repository.dart' show kUserAgent;

/// Vérifie que les flux répondent et envoient de vraies données.
class StreamChecker {
  StreamChecker({
    this.timeout = const Duration(seconds: 8),
    this.concurrency = 8,
  });

  final Duration timeout;
  final int concurrency;

  /// true = en ligne, false = hors ligne, null = impossible à tester (rtmp, udp…).
  Future<bool?> check(Channel c) async {
    final uri = Uri.tryParse(c.url);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    final client = http.Client();
    try {
      final req = http.Request('GET', uri)
        ..headers.addAll({'User-Agent': kUserAgent, ...c.headers});
      final res = await client.send(req).timeout(timeout);
      if (res.statusCode >= 400) return false;
      final chunk = await res.stream.first.timeout(timeout);
      final isHls = c.url.toLowerCase().contains('.m3u8') ||
          (res.headers['content-type']?.contains('mpegurl') ?? false);
      if (isHls) {
        // Une page d'erreur HTML n'est pas un flux : on vérifie l'en-tête HLS.
        final head = utf8
            .decode(chunk.take(64).toList(), allowMalformed: true)
            .replaceFirst('﻿', '')
            .trimLeft();
        return head.startsWith('#EXTM3U');
      }
      return chunk.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Teste les chaînes par paquets de [concurrency] en parallèle.
  Future<void> checkAll(
    List<Channel> channels, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var next = 0;
    var done = 0;

    Future<void> worker() async {
      while (next < channels.length) {
        if (isCancelled?.call() ?? false) return;
        final channel = channels[next++];
        channel.status = StreamStatus.checking;
        onProgress?.call(done, channels.length);
        final ok = await check(channel);
        channel.status = switch (ok) {
          true => StreamStatus.ok,
          false => StreamStatus.dead,
          null => StreamStatus.unknown,
        };
        done++;
        onProgress?.call(done, channels.length);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
  }
}
