import 'package:flutter/material.dart';
import 'store.dart';
import 'theme.dart';
import 'pages/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initNotifications();
  } catch (_) {}
  await store.load();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, __) => MaterialApp(
          title: 'Chronos',
          debugShowCheckedModeBanner: false,
          themeMode: store.themeMode,
          themeAnimationDuration: ms(450),
          themeAnimationCurve: Curves.easeInOutCubic,
          theme: buildTheme(Brightness.light, store.seedColor, store.mono, store.font),
          darkTheme: buildTheme(Brightness.dark, store.seedColor, store.mono, store.font),
          home: const Home(),
        ),
      );
}
