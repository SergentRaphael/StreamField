// Prépare le projet pour Android (+ Android TV), iPhone/iPad, Windows et macOS.
// Lancer depuis le dossier streamfield :  dart run tool/setup.dart
import 'dart:io';

Future<void> main() async {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Lance ce script depuis le dossier « streamfield ».');
    exit(1);
  }

  stdout.writeln('1/3  Création des dossiers Android, iOS, Windows et macOS…');
  final r = await Process.run(
    'flutter',
    [
      'create',
      '--org', 'com.streamfield',
      '--project-name', 'streamfield',
      '--platforms=android,ios,windows,macos',
      '.',
    ],
    runInShell: true,
  );
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode != 0) exit(r.exitCode);

  // Le test d'exemple généré par Flutter ne correspond pas à l'app.
  final sample = File('test/widget_test.dart');
  if (sample.existsSync() && sample.readAsStringSync().contains('MyApp')) {
    sample.deleteSync();
  }

  stdout.writeln('2/3  Réglages : réseau, Android TV, icônes, nom de l\'app…');
  _android();
  _ios();
  _macos();
  _windows();

  stdout.writeln('3/3  Terminé ✔');
}

void _copy(String from, String to) {
  final src = File(from);
  if (!src.existsSync()) return;
  File(to).parent.createSync(recursive: true);
  src.copySync(to);
}

void _android() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) return;
  var x = f.readAsStringSync();

  String before(String marker, String snippet, String check) =>
      x.contains(check) ? x : x.replaceFirst(marker, '$snippet\n    $marker');

  x = before('<application', '<uses-permission android:name="android.permission.INTERNET"/>',
      'android.permission.INTERNET');
  // Android TV : l'app apparaît dans le lanceur TV et n'exige pas d'écran tactile.
  x = before('<application', '<uses-feature android:name="android.software.leanback" android:required="false"/>',
      'android.software.leanback');
  x = before('<application', '<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>',
      'android.hardware.touchscreen');

  if (!x.contains('usesCleartextTraffic')) {
    // Beaucoup de flux IPTV sont en http:// (non chiffré).
    x = x.replaceFirst('<application', '<application\n        android:usesCleartextTraffic="true"');
  }
  if (!x.contains('android:banner')) {
    x = x.replaceFirst('<application', '<application\n        android:banner="@drawable/banner"');
  }
  x = x.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="StreamField"');
  if (!x.contains('LEANBACK_LAUNCHER')) {
    x = x.replaceFirstMapped(
      RegExp(r'<category\s+android:name="android\.intent\.category\.LAUNCHER"\s*/>'),
      (m) => '${m[0]}\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
    );
  }
  f.writeAsStringSync(x);

  const res = 'android/app/src/main/res';
  _copy('tool/branding/android/banner.png', '$res/drawable/banner.png');
  for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
    _copy('tool/branding/android/mipmap-$d/ic_launcher.png', '$res/mipmap-$d/ic_launcher.png');
  }
}

void _ios() {
  final plist = File('ios/Runner/Info.plist');
  if (plist.existsSync()) {
    var x = plist.readAsStringSync();
    x = x.replaceFirstMapped(
      RegExp(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)'),
      (m) => '${m[1]}StreamField${m[2]}',
    );
    final extra = <String, String>{
      // Autorise les flux en http:// (non chiffrés), très courants en IPTV.
      'NSAppTransportSecurity':
          '\t<key>NSAppTransportSecurity</key>\n\t<dict>\n\t\t<key>NSAllowsArbitraryLoads</key>\n\t\t<true/>\n\t</dict>\n',
      // Textes exigés par Apple car le sélecteur de fichiers peut ouvrir la photothèque.
      'NSPhotoLibraryUsageDescription':
          '\t<key>NSPhotoLibraryUsageDescription</key>\n\t<string>Permet de choisir un fichier de playlist.</string>\n',
      'NSAppleMusicUsageDescription':
          '\t<key>NSAppleMusicUsageDescription</key>\n\t<string>Permet de choisir un fichier de playlist.</string>\n',
    };
    extra.forEach((key, snippet) {
      if (x.contains(key)) return;
      final i = x.lastIndexOf('</dict>');
      if (i >= 0) x = '${x.substring(0, i)}$snippet${x.substring(i)}';
    });
    plist.writeAsStringSync(x);
  }

  // media_kit demande iOS 13 minimum.
  final project = File('ios/Runner.xcodeproj/project.pbxproj');
  if (project.existsSync()) {
    project.writeAsStringSync(project.readAsStringSync().replaceAll(
        RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = (?:[0-9]|1[0-2])\.[0-9]+;'),
        'IPHONEOS_DEPLOYMENT_TARGET = 13.0;'));
  }
  final podfile = File('ios/Podfile');
  if (podfile.existsSync()) {
    podfile.writeAsStringSync(podfile.readAsStringSync().replaceFirst(
        RegExp(r"^#?[ \t]*platform :ios, '[0-9.]+'", multiLine: true), "platform :ios, '13.0'"));
  }

  const icons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final dir = Directory('tool/branding/ios');
  if (Directory(icons).existsSync() && dir.existsSync()) {
    for (final f in dir.listSync().whereType<File>()) {
      _copy(f.path, '$icons/${f.uri.pathSegments.last}');
    }
  }
}

void _macos() {
  for (final name in ['DebugProfile', 'Release']) {
    final f = File('macos/Runner/$name.entitlements');
    if (!f.existsSync()) continue;
    var x = f.readAsStringSync();
    for (final key in [
      'com.apple.security.network.client', // accès internet
      'com.apple.security.files.user-selected.read-write', // ouvrir / exporter des fichiers
    ]) {
      if (x.contains(key)) continue;
      final i = x.lastIndexOf('</dict>');
      if (i < 0) continue;
      x = '${x.substring(0, i)}\t<key>$key</key>\n\t<true/>\n${x.substring(i)}';
    }
    f.writeAsStringSync(x);
  }

  final info = File('macos/Runner/Configs/AppInfo.xcconfig');
  if (info.existsSync()) {
    info.writeAsStringSync(info
        .readAsStringSync()
        .replaceFirst(RegExp(r'PRODUCT_NAME = .*'), 'PRODUCT_NAME = StreamField'));
  }

  const icons = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
  if (Directory(icons).existsSync()) {
    for (final s in [16, 32, 64, 128, 256, 512, 1024]) {
      _copy('tool/branding/macos/app_icon_$s.png', '$icons/app_icon_$s.png');
    }
  }
}

void _windows() {
  final main = File('windows/runner/main.cpp');
  if (main.existsSync()) {
    main.writeAsStringSync(
        main.readAsStringSync().replaceFirst('L"streamfield"', 'L"StreamField"'));
  }
  _copy('tool/branding/windows/app_icon.ico', 'windows/runner/resources/app_icon.ico');
}
