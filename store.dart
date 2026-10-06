import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'theme.dart';

const appVersion = '0.9.0';
const repoUrl = 'https://github.com/UseurHead281/Chronos';

String two(int n) => n.toString().padLeft(2, '0');
String keyOf(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String pretty(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';
const monthGen = ['января','февраля','марта','апреля','мая','июня','июля','августа','сентября','октября','ноября','декабря'];
const monthNom = ['Январь','Февраль','Март','Апрель','Май','Июнь','Июль','Август','Сентябрь','Октябрь','Ноябрь','Декабрь'];
String monthName(DateTime d) => monthGen[d.month - 1];
String longDate(DateTime d) => '${d.day} ${monthName(d)} ${d.year}';
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Duration helper that respects the "animations" setting.
Duration ms(int v) => store.animations ? Duration(milliseconds: v) : Duration.zero;

final notifications = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  tz.initializeTimeZones();
  try {
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
  } catch (_) {}
  await notifications.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ));
  await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

// ---------------------------------------------------------------- metadata

class Meta {
  String name = '';
  int bytes = 0;
  String format = '?';
  int? width, height;
  DateTime created = DateTime.now();
  bool createdFromExif = false;
  String? make, model, iso, exposure, fnumber, focal;
  double? lat, lon;
  bool get hasGps => lat != null && lon != null;
  bool get hasCamera => [make, model, iso, exposure, fnumber, focal].any((e) => e != null);
}

Future<Map<String, Object?>> _parseExif(Uint8List bytes) async {
  final out = <String, Object?>{};
  try {
    final tags = await readExifFromBytes(bytes);
    String? s(String k) {
      final v = tags[k]?.printable.trim();
      return (v == null || v.isEmpty) ? null : v;
    }
    String? ratio(String? v, {String prefix = '', String suffix = ''}) {
      if (v == null) return null;
      final p = v.split('/');
      if (p.length == 2) {
        final a = double.tryParse(p[0]), b = double.tryParse(p[1]);
        if (a != null && b != null && b != 0) {
          final r = a / b;
          return '$prefix${r == r.roundToDouble() ? r.toInt() : r.toStringAsFixed(1)}$suffix';
        }
      }
      return '$prefix$v$suffix';
    }
    double? coord(String k, String refKey) {
      final t = tags[k];
      if (t == null) return null;
      final l = t.values.toList();
      if (l.length < 3) return null;
      double v(dynamic r) => r.denominator == 0 ? 0.0 : r.numerator / r.denominator;
      var d = v(l[0]) + v(l[1]) / 60 + v(l[2]) / 3600;
      final ref = tags[refKey]?.printable;
      if (ref == 'S' || ref == 'W') d = -d;
      return d;
    }
    out['make'] = s('Image Make');
    out['model'] = s('Image Model');
    out['iso'] = s('EXIF ISOSpeedRatings');
    final exp = s('EXIF ExposureTime');
    out['exposure'] = exp == null ? null : '$exp с';
    out['fnumber'] = ratio(s('EXIF FNumber'), prefix: 'f/');
    out['focal'] = ratio(s('EXIF FocalLength'), suffix: ' мм');
    out['date'] = s('EXIF DateTimeOriginal');
    final lat = coord('GPS GPSLatitude', 'GPS GPSLatitudeRef');
    final lon = coord('GPS GPSLongitude', 'GPS GPSLongitudeRef');
    if (lat != null && lon != null && !(lat == 0 && lon == 0)) {
      out['lat'] = lat;
      out['lon'] = lon;
    }
  } catch (_) {}
  return out;
}

String _sniffFormat(Uint8List b) {
  if (b.length > 12) {
    if (b[0] == 0xFF && b[1] == 0xD8) return 'JPEG';
    if (b[0] == 0x89 && b[1] == 0x50) return 'PNG';
    if (b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57) return 'WebP';
    if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) return 'HEIC';
  }
  return '?';
}

// ---------------------------------------------------------------- store

class Store extends ChangeNotifier {
  late SharedPreferences prefs;
  late Directory dir;
  late Directory voiceDir;
  List<File> photos = [];
  final Map<String, Meta> _meta = {};
  Set<String> _voices = {};

  bool remindersOn = true;
  int hour = 20, minute = 0;
  bool frontCamera = false;
  String reminderText = 'Время сделать фото дня 📸';
  bool compactGallery = false;
  bool showStreak = true;
  Set<String> favorites = {};
  Map<String, String> notes = {};

  // v0.9
  int seedIndex = 0; // -1 => custom
  int customColor = 0xFF6750A4;
  ThemeMode themeMode = ThemeMode.system;
  String font = 'System';
  int iconIndex = 1;
  bool animations = true;
  bool haptics = true;
  bool voiceEnabled = true;
  bool metadataEnabled = true;
  int photoQuality = 100; // 100 = original (keeps EXIF)

  Color get seedColor => seedIndex >= 0 && seedIndex < palettes.length
      ? palettes[seedIndex].color
      : Color(customColor);
  bool get mono => seedIndex >= 0 && seedIndex < palettes.length && palettes[seedIndex].mono;

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();
    dir = Directory('${docs.path}/photos')..createSync(recursive: true);
    voiceDir = Directory('${docs.path}/voices')..createSync(recursive: true);
    remindersOn = prefs.getBool('on') ?? true;
    hour = prefs.getInt('h') ?? 20;
    minute = prefs.getInt('m') ?? 0;
    frontCamera = prefs.getBool('front') ?? false;
    seedIndex = prefs.getInt('seed') ?? 0;
    if (seedIndex >= palettes.length) seedIndex = 0;
    customColor = prefs.getInt('customColor') ?? customColor;
    final themeIndex = prefs.getInt('theme') ?? 0;
    themeMode = ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)];
    font = prefs.getString('font') ?? 'System';
    if (!fontNames.contains(font)) font = 'System';
    iconIndex = prefs.getInt('icon') ?? 1;
    animations = prefs.getBool('anim') ?? true;
    haptics = prefs.getBool('haptics') ?? true;
    voiceEnabled = prefs.getBool('voiceOn') ?? true;
    metadataEnabled = prefs.getBool('metaOn') ?? true;
    photoQuality = prefs.getInt('quality') ?? 100;
    reminderText = prefs.getString('text') ?? reminderText;
    compactGallery = prefs.getBool('compact') ?? false;
    showStreak = prefs.getBool('showStreak') ?? true;
    favorites = (prefs.getStringList('favorites') ?? []).toSet();
    final rawNotes = prefs.getString('notes_json');
    if (rawNotes != null) {
      try {
        final decoded = jsonDecode(rawNotes);
        notes = decoded is Map ? decoded.map((k, v) => MapEntry(k.toString(), v.toString())) : {};
      } catch (_) {
        notes = {};
      }
    } else {
      final saved = prefs.getStringList('notes') ?? [];
      notes = {};
      for (final item in saved) {
        final i = item.indexOf('|');
        if (i > 0) notes[item.substring(0, i)] = item.substring(i + 1);
      }
    }
    await refresh();
    try {
      await reschedule();
    } catch (_) {}
  }

  // ------------------------------------------------ photos

  DateTime? _parse(File f) {
    try {
      final n = f.uri.pathSegments.last.replaceAll('.jpg', '').split('-');
      if (n.length != 3) return null;
      return DateTime(int.parse(n[0]), int.parse(n[1]), int.parse(n[2]));
    } catch (_) {
      return null;
    }
  }

  DateTime dateOf(File f) => _parse(f) ?? DateTime(1970);

  /// Async, so the UI thread is never blocked by directory listing.
  Future<void> refresh() async {
    final list = <File>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.jpg') && _parse(e) != null) list.add(e);
    }
    list.sort((a, b) => dateOf(b).compareTo(dateOf(a)));
    photos = list;
    final v = <String>{};
    await for (final e in voiceDir.list()) {
      if (e is File && e.path.endsWith('.m4a')) {
        v.add(e.uri.pathSegments.last.replaceAll('.m4a', ''));
      }
    }
    _voices = v;
    notifyListeners();
  }

  Set<DateTime> get days => photos.map(dateOf).map(dayOnly).toSet();

  File? photoOn(DateTime d) {
    final k = keyOf(d);
    for (final f in photos) {
      if (f.path.endsWith('$k.jpg')) return f;
    }
    return null;
  }

  File? get today => photoOn(DateTime.now());

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
      cur = (prev != null && x.difference(prev).inDays == 1) ? cur + 1 : 1;
      if (cur > best) best = cur;
      prev = x;
    }
    return best;
  }

  int get currentMonthCount {
    final n = DateTime.now();
    return photos.where((f) {
      final d = dateOf(f);
      return d.year == n.year && d.month == n.month;
    }).length;
  }

  int get currentYearCount => photos.where((f) => dateOf(f).year == DateTime.now().year).length;

  double get completionRate {
    final n = DateTime.now();
    final daysInMonth = DateTime(n.year, n.month + 1, 0).day;
    final elapsed = n.day.clamp(1, daysInMonth);
    return (currentMonthCount / elapsed).clamp(0.0, 1.0);
  }

  bool isFavorite(File f) => favorites.contains(keyOf(dateOf(f)));
  String noteFor(File f) => notes[keyOf(dateOf(f))] ?? '';

  /// Saves [src] as the memory for [day]. Returns false if the user cancelled.
  Future<bool> _import(XFile? x, DateTime day) async {
    if (x == null) return false;
    final target = '${dir.path}/${keyOf(day)}.jpg';
    await File(x.path).copy(target);
    _meta.remove(target);
    imageCache.clear();
    imageCache.clearLiveImages();
    await refresh();
    return true;
  }

  Future<bool> takePhoto() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: frontCamera ? CameraDevice.front : CameraDevice.rear,
      imageQuality: photoQuality >= 100 ? null : photoQuality,
    );
    return _import(x, DateTime.now());
  }

  /// Android Photo Picker via image_picker; needs no storage permission.
  Future<bool> pickFromGallery(DateTime day) async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: photoQuality >= 100 ? null : photoQuality,
    );
    return _import(x, day);
  }

  Future<void> delete(File f) async {
    final k = keyOf(dateOf(f));
    await f.delete();
    final v = voiceFile(dateOf(f));
    if (v.existsSync()) await v.delete();
    _meta.remove(f.path);
    favorites.remove(k);
    notes.remove(k);
    await _saveMeta();
    imageCache.clear();
    await refresh();
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

  // ------------------------------------------------ voice

  File voiceFile(DateTime d) => File('${voiceDir.path}/${keyOf(d)}.m4a');
  bool hasVoice(DateTime d) => _voices.contains(keyOf(d));

  Future<void> voiceChanged() => refresh();

  Future<void> deleteVoice(DateTime d) async {
    final f = voiceFile(d);
    if (f.existsSync()) await f.delete();
    await refresh();
  }

  // ------------------------------------------------ metadata (cached, parsed off the UI thread)

  Future<Meta> metaFor(File f) async {
    final cached = _meta[f.path];
    if (cached != null) return cached;
    final m = Meta();
    m.name = f.uri.pathSegments.last;
    final stat = await f.stat();
    m.bytes = stat.size;
    m.created = stat.modified;
    try {
      final bytes = await f.readAsBytes();
      m.format = _sniffFormat(bytes);
      try {
        final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
        final desc = await ui.ImageDescriptor.encoded(buf);
        m.width = desc.width;
        m.height = desc.height;
        desc.dispose();
        buf.dispose();
      } catch (_) {}
      final x = await compute(_parseExif, bytes);
      m.make = x['make'] as String?;
      m.model = x['model'] as String?;
      m.iso = x['iso'] as String?;
      m.exposure = x['exposure'] as String?;
      m.fnumber = x['fnumber'] as String?;
      m.focal = x['focal'] as String?;
      m.lat = x['lat'] as double?;
      m.lon = x['lon'] as double?;
      final ds = x['date'] as String?;
      if (ds != null) {
        final p = ds.split(RegExp(r'[: ]'));
        if (p.length >= 6) {
          final dt = DateTime.tryParse('${p[0]}-${p[1]}-${p[2]} ${p[3]}:${p[4]}:${p[5]}');
          if (dt != null) {
            m.created = dt;
            m.createdFromExif = true;
          }
        }
      }
    } catch (_) {}
    _meta[f.path] = m;
    return m;
  }

  // ------------------------------------------------ icon

  static const _iconChannel = MethodChannel('chronos/icon');

  Future<bool> setIcon(int i) async {
    try {
      await _iconChannel.invokeMethod('setIcon', i);
      iconIndex = i;
      await prefs.setInt('icon', i);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------ storage

  Future<int> storageBytes() async {
    var total = 0;
    for (final d in [dir, voiceDir]) {
      await for (final e in d.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
    }
    return total;
  }

  Future<void> clearCache() async {
    imageCache.clear();
    imageCache.clearLiveImages();
    _meta.clear();
    try {
      final t = await getTemporaryDirectory();
      if (t.existsSync()) {
        await for (final e in t.list()) {
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  // ------------------------------------------------ reminders

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
        android: AndroidNotificationDetails('daily', 'Ежедневное напоминание',
            importance: Importance.high, priority: Priority.high),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> set(Future<void> Function(SharedPreferences) save, {bool resched = false}) async {
    await save(prefs);
    notifyListeners();
    if (resched) await reschedule();
  }

  void tap() {
    if (haptics) HapticFeedback.selectionClick();
  }
}

final store = Store();
