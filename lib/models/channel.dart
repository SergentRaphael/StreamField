enum StreamStatus { unknown, checking, ok, dead }

class Channel {
  Channel({
    required this.name,
    required this.url,
    this.group = 'Sans catégorie',
    this.logo,
    this.tvgId,
    this.headers = const <String, String>{},
    this.status = StreamStatus.unknown,
  });

  final String name;
  final String url;
  final String group;
  final String? logo;
  final String? tvgId; // pour relier la chaîne au guide TV (EPG) plus tard
  final Map<String, String> headers; // User-Agent, Referer… exigés par certains flux
  StreamStatus status;
}
