import 'dart:convert';
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
const monthNames = ['января','февраля','марта','апреля','мая','июня','июля','августа','сентября','октября','ноября','декабря'];
String monthName(DateTime d) => monthNames[d.month - 1];
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

const seeds = [
  Colors.deepPurple,
  Colors.teal,
  Colors.orange,
  Colors.pink,
  Colors.blue,
  Colors.green,
];

final notifications = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  tz.initializeTimeZones();
  final name = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(name));
  await notifications.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ));
  await notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

class Store extends ChangeNotifier {
  late SharedPreferences prefs;
  late Directory dir;
  List<File> photos = [];
  bool remindersOn = true;
  int hour = 20, minute = 0;
  bool frontCamera = false;
  int seedIndex = 0;
  ThemeMode themeMode = ThemeMode.system;
  String reminderText = 'Время сделать фото дня 📸';
  bool compactGallery = false;
  bool showStreak = true;
  Set<String> favorites = {};
  Map<String, String> notes = {};

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();
    dir = Directory('${docs.path}/photos')..createSync(recursive: true);
    remindersOn = prefs.getBool('on') ?? true;
    hour = prefs.getInt('h') ?? 20;
    minute = prefs.getInt('m') ?? 0;
    frontCamera = prefs.getBool('front') ?? false;
    seedIndex = prefs.getInt('seed') ?? 0;
    final themeIndex = prefs.getInt('theme') ?? 0;
    themeMode = ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)];
    reminderText = prefs.getString('text') ?? reminderText;
    compactGallery = prefs.getBool('compact') ?? false;
    showStreak = prefs.getBool('showStreak') ?? true;
    favorites = (prefs.getStringList('favorites') ?? []).toSet();
    final rawNotes = prefs.getString('notes_json');
    if (rawNotes != null) {
      try {
        final decoded = jsonDecode(rawNotes);
        notes = decoded is Map
            ? decoded.map((k, v) => MapEntry(k.toString(), v.toString()))
            : {};
      } catch (_) {
        notes = {};
      }
    } else {
      // Compatibility with older 0.2/1.x builds.
      final savedNotes = prefs.getStringList('notes') ?? [];
      notes = {};
      for (final item in savedNotes) {
        final i = item.indexOf('|');
        if (i > 0) notes[item.substring(0, i)] = item.substring(i + 1);
      }
    }
    refresh();
    await reschedule();
  }

  void refresh() {
    photos = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.jpg'))
        .toList()
      ..sort((a, b) => dateOf(b).compareTo(dateOf(a)));
    notifyListeners();
  }

  DateTime dateOf(File f) {
    final n = f.uri.pathSegments.last.replaceAll('.jpg', '').split('-');
    return DateTime(int.parse(n[0]), int.parse(n[1]), int.parse(n[2]));
  }

  Set<DateTime> get days => photos.map(dateOf).map(dayOnly).toSet();
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
      cur = (prev != null && x.difference(prev!).inDays == 1) ? cur + 1 : 1;
      if (cur > best) best = cur;
      prev = x;
    }
    return best;
  }

  int get currentMonthCount => photos.where((f) {
        final d = dateOf(f);
        final n = DateTime.now();
        return d.year == n.year && d.month == n.month;
      }).length;

  int get currentYearCount => photos.where((f) => dateOf(f).year == DateTime.now().year).length;
  double get completionRate {
    final n = DateTime.now();
    final start = DateTime(n.year, n.month, 1);
    final daysInMonth = DateTime(n.year, n.month + 1, 0).day;
    final elapsed = n.day.clamp(1, daysInMonth);
    return (currentMonthCount / elapsed).clamp(0.0, 1.0);
  }

  bool isFavorite(File f) => favorites.contains(keyOf(dateOf(f)));
  String noteFor(File f) => notes[keyOf(dateOf(f))] ?? '';

  Future<bool> takePhoto() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: frontCamera ? CameraDevice.front : CameraDevice.rear,
      imageQuality: 92,
    );
    if (x == null) return false;
    await File(x.path).copy('${dir.path}/${keyOf(DateTime.now())}.jpg');
    refresh();
    return true;
  }

  Future<void> delete(File f) async {
    final k = keyOf(dateOf(f));
    await f.delete();
    favorites.remove(k);
    notes.remove(k);
    await _saveMeta();
    refresh();
  }

  Future<void> toggleFavorite(File f) async {
    final k = keyOf(dateOf(f));
    if (!favorites.add(k)) favorites.remove(k);
    await _saveMeta();
    notifyListeners();
  }

  Future<void> saveNote(File f, String value) async {
    final k = keyOf(dateOf(f));
    if (value.trim().isEmpty) {
      notes.remove(k);
    } else {
      notes[k] = value.trim();
    }
    await _saveMeta();
    notifyListeners();
  }

  Future<void> _saveMeta() async {
    await prefs.setStringList('favorites', favorites.toList());
    await prefs.setString('notes_json', jsonEncode(notes));
  }

  Future<void> reschedule() async {
    await notifications.cancelAll();
    if (!remindersOn) return;
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (at.isBefore(now)) at = at.add(const Duration(days: 1));
    await notifications.zonedSchedule(
      1,
      'Chronos',
      reminderText,
      at,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily',
          'Ежедневное напоминание',
          importance: Importance.high,
          priority: Priority.high,
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
          title: 'Chronos',
          debugShowCheckedModeBanner: false,
          themeMode: store.themeMode,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: const Home(),
        ),
      );

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seeds[store.seedIndex],
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF101014)
          : const Color(0xFFF7F6FA),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      navigationBarTheme: const NavigationBarThemeData(height: 72),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  final pages = const [TodayPage(), GalleryPage(), StatsPage(), SettingsPage()];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: pages[tab]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Сегодня'),
            NavigationDestination(icon: Icon(Icons.photo_library_outlined), selectedIcon: Icon(Icons.photo_library), label: 'Фото'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Статистика'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Настройки'),
          ],
        ),
      );
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, __) {
          final photo = store.today;
          final cs = Theme.of(context).colorScheme;
          final now = DateTime.now();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(Icons.hourglass_bottom_rounded, color: cs.onPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Chronos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text('${now.day} ${monthName(now)} ${now.year}', style: TextStyle(color: cs.onSurfaceVariant)),
                ])),
                IconButton(onPressed: () => _showQuickInfo(context), icon: const Icon(Icons.info_outline)),
              ]),
              const SizedBox(height: 18),
              if (store.showStreak) _streakCard(context),
              const SizedBox(height: 14),
              _photoCard(context, photo),
              const SizedBox(height: 14),
              if (photo != null) _noteCard(context, photo),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: () async {
                  final ok = await store.takePhoto();
                  if (ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Фото сохранено • ${store.streak} дн. подряд 🔥')),
                    );
                  }
                },
                icon: const Icon(Icons.camera_alt_rounded),
                label: Text(photo == null ? 'Сделать фото дня' : 'Переснять фото'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _miniStat(context, Icons.photo_library_outlined, '${store.photos.length}', 'фото')),
                const SizedBox(width: 10),
                Expanded(child: _miniStat(context, Icons.calendar_month_outlined, '${store.currentMonthCount}', 'в этом месяце')),
              ]),
            ],
          );
        },
      );

  Widget _streakCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: cs.primary.withOpacity(.15), shape: BoxShape.circle),
            child: Icon(Icons.local_fire_department_rounded, size: 34, color: cs.primary),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${store.streak} дней подряд', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(store.streak == 0 ? 'Сегодня можно начать новую серию' : 'Рекорд: ${store.bestStreak} • не прерывай линию', style: TextStyle(color: cs.onPrimaryContainer.withOpacity(.75))),
          ])),
        ]),
      ),
    );
  }

  Widget _photoCard(BuildContext context, File? photo) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: photo == null
            ? Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.surfaceContainerHighest, cs.surface]),
                ),
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.photo_camera_back_outlined, size: 68, color: cs.primary.withOpacity(.65)),
                  const SizedBox(height: 12),
                  Text('Сохрани сегодняшний момент', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Одно фото. Один день.', style: TextStyle(color: cs.onSurfaceVariant)),
                ])),
              )
            : GestureDetector(
                onTap: () => PhotoViewer.open(context, photo),
                child: Stack(fit: StackFit.expand, children: [
                  Image.file(photo, fit: BoxFit.cover, key: ValueKey(photo.path)),
                  Positioned(left: 12, top: 12, child: _tag(context, 'СЕГОДНЯ')),
                  Positioned(right: 8, top: 8, child: IconButton.filledTonal(onPressed: () => store.toggleFavorite(photo), icon: Icon(store.isFavorite(photo) ? Icons.favorite : Icons.favorite_border))),
                ]),
              ),
      ),
    );
  }

  Widget _noteCard(BuildContext context, File photo) {
    final note = store.noteFor(photo);
    return Card(child: ListTile(
      leading: const Icon(Icons.notes_rounded),
      title: Text(note.isEmpty ? 'Добавить подпись' : note, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(note.isEmpty ? 'Сохрани мысль или короткое описание' : 'Заметка к фото'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _editNote(context, photo),
    ));
  }

  Widget _tag(BuildContext context, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .7)),
      );

  Widget _miniStat(BuildContext context, IconData icon, String value, String label) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Icon(icon, size: 22), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))]))])));

  Future<void> _editNote(BuildContext context, File f) async {
    final c = TextEditingController(text: store.noteFor(f));
    final result = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Подпись к фото'),
      content: TextField(controller: c, maxLength: 120, autofocus: true, decoration: const InputDecoration(hintText: 'Например: прогулка после школы')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Сохранить'))],
    ));
    if (result != null) await store.saveNote(f, result);
  }

  Future<void> _showQuickInfo(BuildContext context) => showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 28), child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: Icon(Icons.lock_outline), title: Text('Личные воспоминания'), subtitle: Text('Фото хранятся локально на устройстве.')), ListTile(leading: Icon(Icons.local_fire_department_outlined), title: Text('Серия дней'), subtitle: Text('Сделай фото сегодня, чтобы не прервать серию.')), ListTile(leading: Icon(Icons.auto_awesome_outlined), title: Text('Chronos'), subtitle: Text('Один день — один момент.'))])));
}

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  String query = '';
  bool onlyFavorites = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (_, __) {
    final list = store.photos.where((f) {
      final q = query.trim().toLowerCase();
      final note = store.noteFor(f).toLowerCase();
      final matches = q.isEmpty || pretty(store.dateOf(f)).contains(q) || note.contains(q);
      return matches && (!onlyFavorites || store.isFavorite(f));
    }).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Row(children: [Expanded(child: Text('Мои моменты', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800))), IconButton(onPressed: () => setState(() => onlyFavorites = !onlyFavorites), icon: Icon(onlyFavorites ? Icons.favorite : Icons.favorite_border)), PopupMenuButton<bool>(onSelected: (v) async { setState(() => store.compactGallery = v); await store.set((p) async { await p.setBool('compact', v); }); }, itemBuilder: (_) => const [PopupMenuItem(value: false, child: Text('Крупные плитки')), PopupMenuItem(value: true, child: Text('Компактная сетка'))])])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: TextField(onChanged: (v) => setState(() => query = v), decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: 'Поиск по датам и подписям', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none), suffixIcon: query.isEmpty ? null : IconButton(onPressed: () => setState(() => query = ''), icon: const Icon(Icons.close_rounded))))),
      Expanded(child: list.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(store.photos.isEmpty ? Icons.photo_camera_back_rounded : Icons.search_off_rounded, size: 52, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 14), Text(store.photos.isEmpty ? 'Пока здесь пусто' : 'Ничего не найдено', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text(store.photos.isEmpty ? 'Сделай первое фото дня — оно появится здесь.' : 'Попробуй изменить запрос или снять фильтр.', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))])) : GridView.builder(padding: const EdgeInsets.all(12), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: store.compactGallery ? 4 : 3, mainAxisSpacing: 8, crossAxisSpacing: 8), itemCount: list.length, itemBuilder: (_, i) => _tile(context, list[i]))),
    ]);
  });

  Widget _tile(BuildContext context, File f) => GestureDetector(
    onTap: () => PhotoViewer.open(context, f),
    onLongPress: () => _actions(context, f),
    child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Stack(fit: StackFit.expand, children: [Image.file(f, fit: BoxFit.cover, cacheWidth: 360), if (store.isFavorite(f)) const Positioned(right: 5, top: 5, child: Icon(Icons.favorite, color: Colors.white, size: 17)), Positioned(bottom: 0, left: 0, right: 0, child: Container(color: Colors.black54, padding: const EdgeInsets.symmetric(vertical: 4), child: Text(pretty(store.dateOf(f)), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10))))])));

  Future<void> _actions(BuildContext context, File f) async {
    await showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: Icon(store.isFavorite(f) ? Icons.favorite : Icons.favorite_border), title: Text(store.isFavorite(f) ? 'Убрать из избранного' : 'В избранное'), onTap: () { Navigator.pop(context); store.toggleFavorite(f); }), ListTile(leading: const Icon(Icons.notes_outlined), title: const Text('Изменить подпись'), onTap: () { Navigator.pop(context); _editNote(context, f); }), ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Удалить'), onTap: () { Navigator.pop(context); _confirmDelete(context, f); })])));
  }

  Future<void> _editNote(BuildContext context, File f) async {
    final c = TextEditingController(text: store.noteFor(f));
    final r = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Подпись к фото'), content: TextField(controller: c, maxLength: 120, autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Сохранить'))]));
    if (r != null) await store.saveNote(f, r);
  }

  Future<void> _confirmDelete(BuildContext context, File f) async {
    final yes = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Удалить фото?'), content: Text(pretty(store.dateOf(f))), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))]));
    if (yes == true) await store.delete(f);
  }
}

class PhotoViewer {
  static void open(BuildContext context, File f) => showDialog(context: context, barrierColor: Colors.black, builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(pretty(store.dateOf(f))), actions: [IconButton(onPressed: () => store.toggleFavorite(f), icon: Icon(store.isFavorite(f) ? Icons.favorite : Icons.favorite_border))]), body: Center(child: InteractiveViewer(minScale: .8, maxScale: 4, child: Image.file(f))), bottomNavigationBar: store.noteFor(f).isEmpty ? null : SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Text(store.noteFor(f), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70))))));
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (_, __) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      Text('Статистика', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 16),
      Row(children: [Expanded(child: _card(context, '${store.photos.length}', 'всего фото', Icons.photo_library_rounded)), const SizedBox(width: 10), Expanded(child: _card(context, '${store.bestStreak}', 'лучший стрик', Icons.emoji_events_rounded))]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: _card(context, '${store.currentMonthCount}', 'этот месяц', Icons.calendar_month_rounded)), const SizedBox(width: 10), Expanded(child: _card(context, '${store.currentYearCount}', 'этот год', Icons.date_range_rounded))]),
      const SizedBox(height: 18),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${monthName(DateTime.now()).replaceFirst(monthName(DateTime.now())[0], monthName(DateTime.now())[0].toUpperCase())} ${DateTime.now().year}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 12), LinearProgressIndicator(value: store.completionRate, minHeight: 10, borderRadius: BorderRadius.circular(20)), const SizedBox(height: 8), Text('${(store.completionRate * 100).round()}% дней уже сохранено', style: TextStyle(color: cs.onSurfaceVariant))]))),
      const SizedBox(height: 14),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Последние 35 дней', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 14), _heatmap(context)]))),
      const SizedBox(height: 14),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Твоя серия', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 8), Text(store.streak == 0 ? 'Сегодня ещё можно начать новую серию.' : 'Сейчас: ${store.streak} дней подряд. Не останавливайся!', style: TextStyle(color: cs.onSurfaceVariant))]))),
    ]);
  });

  Widget _card(BuildContext context, String value, String label, IconData icon) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon), const SizedBox(height: 12), Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)), Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))])));

  Widget _heatmap(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = dayOnly(DateTime.now());
    return Wrap(spacing: 5, runSpacing: 5, children: List.generate(35, (i) {
      final d = today.subtract(Duration(days: 34 - i));
      final active = store.days.contains(d);
      return Tooltip(message: '${pretty(d)}${active ? ' • фото есть' : ''}', child: Container(width: 24, height: 24, decoration: BoxDecoration(color: active ? cs.primary : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6))));
    }));
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (_, __) => ListView(children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Text('Настройки', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800))),
    const _SectionTitle('Напоминания'),
    SwitchListTile(secondary: const Icon(Icons.notifications_active_outlined), title: const Text('Ежедневное напоминание'), value: store.remindersOn, onChanged: (v) => store.set((p) async { store.remindersOn = v; await p.setBool('on', v); }, resched: true)),
    ListTile(leading: const Icon(Icons.schedule), title: const Text('Время'), subtitle: Text('${two(store.hour)}:${two(store.minute)}'), enabled: store.remindersOn, onTap: () async { final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: store.hour, minute: store.minute)); if (t == null) return; await store.set((p) async { store.hour = t.hour; store.minute = t.minute; await p.setInt('h', t.hour); await p.setInt('m', t.minute); }, resched: true); }),
    ListTile(leading: const Icon(Icons.edit_notifications_outlined), title: const Text('Текст уведомления'), subtitle: Text(store.reminderText), onTap: () async { final c = TextEditingController(text: store.reminderText); final r = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Текст уведомления'), content: TextField(controller: c, maxLength: 80, autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Сохранить'))])); if (r == null || r.trim().isEmpty) return; await store.set((p) async { store.reminderText = r.trim(); await p.setString('text', r.trim()); }, resched: true); }),
    const _SectionTitle('Камера и интерфейс'),
    SwitchListTile(secondary: const Icon(Icons.cameraswitch_outlined), title: const Text('Фронтальная камера'), value: store.frontCamera, onChanged: (v) => store.set((p) async { store.frontCamera = v; await p.setBool('front', v); })),
    SwitchListTile(secondary: const Icon(Icons.local_fire_department_outlined), title: const Text('Показывать серию'), value: store.showStreak, onChanged: (v) => store.set((p) async { store.showStreak = v; await p.setBool('showStreak', v); })),
    const _SectionTitle('Оформление'),
    ListTile(leading: const Icon(Icons.brightness_6_outlined), title: const Text('Тема'), subtitle: Padding(padding: const EdgeInsets.only(top: 8), child: SegmentedButton<ThemeMode>(showSelectedIcon: false, segments: const [ButtonSegment(value: ThemeMode.system, label: Text('Авто')), ButtonSegment(value: ThemeMode.light, label: Text('Светлая')), ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная'))], selected: {store.themeMode}, onSelectionChanged: (s) => store.set((p) async { store.themeMode = s.first; await p.setInt('theme', s.first.index); }))),
    ListTile(leading: const Icon(Icons.palette_outlined), title: const Text('Цвет Chronos'), subtitle: Padding(padding: const EdgeInsets.only(top: 12), child: Wrap(spacing: 12, runSpacing: 10, children: [for (var i = 0; i < seeds.length; i++) GestureDetector(onTap: () => store.set((p) async { store.seedIndex = i; await p.setInt('seed', i); }), child: CircleAvatar(backgroundColor: seeds[i], child: store.seedIndex == i ? const Icon(Icons.check, color: Colors.white) : null))]))),
    const _SectionTitle('О приложении'),
    const ListTile(leading: Icon(Icons.hourglass_bottom_rounded), title: Text('Chronos'), subtitle: Text('Один день — один момент.\nВерсия 0.25 • локальные воспоминания')),
  ])));
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 4), child: Text(text.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Theme.of(context).colorScheme.primary)));
}
