import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'platform.dart';
import 'screens/home_screen.dart';
import 'services/account.dart';
import 'services/storage.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (isDesktop) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'StreamField',
        size: Size(1200, 760),
        minimumSize: Size(480, 360),
        center: true,
        backgroundColor: kBg,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  final store = await Store.open();
  final account = await Account.open(store);
  runApp(StreamFieldApp(store: store, account: account));
}

class StreamFieldApp extends StatelessWidget {
  const StreamFieldApp({super.key, required this.store, required this.account});

  final Store store;
  final Account account;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StreamField',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        // Télécommande Android TV : le bouton OK envoie la touche « select ».
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      home: HomeScreen(store: store, account: account),
    );
  }
}
