import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

String two(int n) => n.toString().padLeft(2, '0');
String keyOf(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String pretty(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

const seeds = [
  Colors.deepPurple, Colors.teal, Colors.orange,
  Colors.pink, Colors.blue, Colors.green,
];

/// ---------- Уведомления ----------
final notifications = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  tz.initializeTimeZones();
  final name = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(name));
  tz.setLocalLocation(tz.getLocation(name));
  await notifications.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ));
  await notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

/// ---------- Хранилище и настройки ----------
class Store extends ChangeNotifier {
  late SharedPreferences prefs;
  late Directory dir;
  List<File> photos = []; // новые первыми

  bool remindersOn = true;
  int hour = 20, minute = 0;
  bool frontCamera = false;
  int seedIndex = 0;
  ThemeMode themeMode = ThemeMode.system;
  String reminderText = 'Время сделать фото дня 📸';

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();
    dir = Directory('${docs.path}/photos')..createSync(recursive: true);
    remindersOn = prefs.getBool('on') ?? true;
    hour = prefs.getInt('h') ?? 20;
    minute = prefs.getInt('m') ?? 0;
    frontCamera = prefs.getBool('front') ?? false;
    seedIndex = prefs.getInt('seed') ?? 0;
    themeMode = ThemeMode.values[prefs.getInt('theme') ?? 0];
    reminderText = prefs.getString('text') ?? reminderText;
    refresh();
    await reschedule();
  }

  void refresh() {
    photos = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jpg'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    notifyListeners();
  }

  DateTime dateOf(File f) {
    final n = f.uri.pathSegments.last.replaceAll('.jpg', '').split('-');
    return DateTime(int.parse(n[0]), int.parse(n[1]), int.parse(n[2]));
  }

  Set<DateTime> get days => photos.map(dateOf).toSet();
  File? get today {
    final k = keyOf(DateTime.now());
    for (final f in photos) {
      if (f.path.endsWith('$k.jpg')) return f;
    }
    return null;
  }

  int get streak {
    final d = days;
    var c = dayOnly(DateTime.now());
    if (!d.contains(c)) c = DateTime(c.year, c.month, c.day - 1);
    var n = 0;
    while (d.contains(c)) {
      n++;
      c = DateTime(c.year, c.month, c.day - 1);
    }
    return n;
  }

  int get bestStreak {
    final d = days.toList()..sort();
    var best = 0, cur = 0;
    DateTime? prev;
    for (final x in d) {
      cur = (prev != null && DateTime(prev.year, prev.month, prev.day + 1) == x)
          ? cur + 1
          : 1;
      if (cur > best) best = cur;
      prev = x;
    }
    return best;
  }

  Future<bool> takePhoto() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice:
          frontCamera ? CameraDevice.front : CameraDevice.rear,
      imageQuality: 90,
    );
    if (x == null) return false;
    await File(x.path).copy('${dir.path}/${keyOf(DateTime.now())}.jpg');
    refresh();
    return true;
  }

  Future<void> delete(File f) async {
    await f.delete();
    refresh();
  }

  Future<void> reschedule() async {
    await notifications.cancelAll();
    if (!remindersOn) return;
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (at.isBefore(now)) at = at.add(const Duration(days: 1));
    await notifications.zonedSchedule(
      1,
      'Фото дня',
      reminderText,
      at,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily', 'Ежедневное напоминание',
          importance: Importance.high, priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> set(Future<void> Function(SharedPreferences) save,
      {bool resched = false}) async {
    await save(prefs);
    notifyListeners();
    if (resched) await reschedule();
  }
}

/// ---------- Приложение ----------
final store = Store();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  await store.load();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, __) => MaterialApp(
          title: 'Фото дня',
          debugShowCheckedModeBanner: false,
          themeMode: store.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: seeds[store.seedIndex]),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
                seedColor: seeds[store.seedIndex], brightness: Brightness.dark),
          ),
          home: const Home(),
        ),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    const pages = [TodayPage(), GalleryPage(), SettingsPage()];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: 'Сегодня'),
          NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              label: 'Галерея'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Настройки'),
        ],
      ),
    );
  }
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (_, __) {
        final photo = store.today;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Фото дня', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 16),
          Card.filled(
            color: cs.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Icon(Icons.local_fire_department,
                    size: 56, color: cs.onPrimaryContainer),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${store.streak} дн. подряд',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(color: cs.onPrimaryContainer)),
                        Text('Рекорд: ${store.bestStreak} • Всего: ${store.photos.length}',
                            style: TextStyle(color: cs.onPrimaryContainer)),
                      ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Card.outlined(
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: photo == null
                  ? Center(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_a_photo_outlined,
                                size: 64, color: cs.outline),
                            const SizedBox(height: 8),
                            const Text('Сегодня ещё нет фото'),
                          ]),
                    )
                  : Image.file(photo, fit: BoxFit.cover, key: UniqueKey()),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              final ok = await store.takePhoto();
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Сохранено! Стрик: ${store.streak} 🔥')));
              }
            },
            icon: const Icon(Icons.photo_camera),
            label: Text(photo == null ? 'Сделать фото' : 'Переснять'),
          ),
        ]);
      },
    );
  }
}

class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, __) {
          if (store.photos.isEmpty) {
            return const Center(child: Text('Пока пусто — сделайте первое фото'));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: store.photos.length,
            itemBuilder: (_, i) {
              final f = store.photos[i];
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _open(context, f),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(fit: StackFit.expand, children: [
                    Image.file(f, fit: BoxFit.cover, cacheWidth: 300),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.all(2),
                        child: Text(pretty(store.dateOf(f)),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11)),
                      ),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      );

  void _open(BuildContext context, File f) => showDialog(
        context: context,
        builder: (_) => Dialog(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(f)),
            ),
            Text(pretty(store.dateOf(f)),
                style: Theme.of(context).textTheme.titleMedium),
            OverflowBar(children: [
              TextButton.icon(
                onPressed: () {
                  store.delete(f);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Удалить'),
              ),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Закрыть')),
            ]),
          ]),
        ),
      );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, __) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Настройки',
                style: Theme.of(context).textTheme.headlineLarge),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Ежедневное напоминание'),
            value: store.remindersOn,
            onChanged: (v) => store.set((p) async {
              store.remindersOn = v;
              await p.setBool('on', v);
            }, resched: true),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Время напоминания'),
            subtitle: Text('${two(store.hour)}:${two(store.minute)}'),
            enabled: store.remindersOn,
            onTap: () async {
              final t = await showTimePicker(
                  context: context,
                  initialTime:
                      TimeOfDay(hour: store.hour, minute: store.minute));
              if (t == null) return;
              store.set((p) async {
                store.hour = t.hour;
                store.minute = t.minute;
                await p.setInt('h', t.hour);
                await p.setInt('m', t.minute);
              }, resched: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_notifications_outlined),
            title: const Text('Текст уведомления'),
            subtitle: Text(store.reminderText),
            onTap: () async {
              final c = TextEditingController(text: store.reminderText);
              final r = await showDialog<String>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Текст уведомления'),
                  content: TextField(controller: c, autofocus: true),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Отмена')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, c.text),
                        child: const Text('Сохранить')),
                  ],
                ),
              );
              if (r == null || r.trim().isEmpty) return;
              store.set((p) async {
                store.reminderText = r.trim();
                await p.setString('text', r.trim());
              }, resched: true);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.cameraswitch_outlined),
            title: const Text('Фронтальная камера по умолчанию'),
            value: store.frontCamera,
            onChanged: (v) => store.set((p) async {
              store.frontCamera = v;
              await p.setBool('front', v);
            }),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Тема'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Авто')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
                ],
                selected: {store.themeMode},
                onSelectionChanged: (s) => store.set((p) async {
                  store.themeMode = s.first;
                  await p.setInt('theme', s.first.index);
                }),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Цвет акцента'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 12, children: [
                for (var i = 0; i < seeds.length; i++)
                  GestureDetector(
                    onTap: () => store.set((p) async {
                      store.seedIndex = i;
                      await p.setInt('seed', i);
                    }),
                    child: CircleAvatar(
                      backgroundColor: seeds[i],
                      child: store.seedIndex == i
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
              ]),
            ),
          ),
        ]),
      );
}
