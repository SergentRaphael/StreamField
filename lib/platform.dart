import 'dart:io' show Platform;

final bool isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
final bool isMobile = Platform.isAndroid || Platform.isIOS;
