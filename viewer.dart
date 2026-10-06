import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../store.dart';
import '../widgets.dart';
import 'voice.dart';

String heroTag(File f) => 'photo-${keyOf(store.dateOf(f))}';

Future<void> openViewer(BuildContext context, File f) => Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: ms(380),
        reverseTransitionDuration: ms(300),
        pageBuilder: (_, __, ___) => PhotoViewer(initial: f),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
      ),
    );

class PhotoViewer extends StatefulWidget {
  final File initial;
  const PhotoViewer({super.key, required this.initial});
  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final List<File> list = List.of(store.photos);
  late final PageController controller;
  late int index;
  bool chrome = true;

  @override
  void initState() {
    super.initState();
    index = list.indexWhere((e) => e.path == widget.initial.path);
    if (index < 0) {
      list.insert(0, widget.initial);
      index = 0;
    }
    controller = PageController(initialPage: index);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  File get current => list[index];

  Future<void> _share() async {
    try {
      await Share.shareXFiles([XFile(current.path, mimeType: 'image/jpeg')], text: longDate(store.dateOf(current)));
    } catch (_) {
      if (mounted) snack(context, 'Не удалось открыть меню «Поделиться»');
    }
  }

  void _voice() => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Голосовая заметка', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            VoiceNoteCard(day: store.dateOf(current)),
          ]),
        ),
      );

  void _info() => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .7,
          maxChildSize: .95,
          minChildSize: .4,
          builder: (_, sc) => InfoSheet(file: current, controller: sc),
        ),
      );

  Future<void> _delete() async {
    final f = current;
    if (!await confirmDelete(context, f)) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    nav.pop();
    await store.delete(f);
    messenger.showSnackBar(SnackBar(
      content: const Text('Воспоминание удалено'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: ListenableBuilder(
          listenable: store,
          builder: (_, __) {
            final f = current;
            final d = store.dateOf(f);
            final note = store.noteFor(f);
            return Stack(fit: StackFit.expand, children: [
              PageView.builder(
                controller: controller,
                itemCount: list.length,
                onPageChanged: (i) => setState(() => index = i),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => setState(() => chrome = !chrome),
                  child: Hero(
                    tag: heroTag(list[i]),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Image(
                        image: ResizeImage.resizeIfNeeded(2048, null, FileImage(list[i])),
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !chrome,
                  child: AnimatedOpacity(
                    opacity: chrome ? 1 : 0,
                    duration: ms(200),
                    child: SafeArea(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(color: Colors.white, onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !chrome,
                  child: AnimatedOpacity(
                    opacity: chrome ? 1 : 0,
                    duration: ms(200),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 40, 12, 8),
                      child: SafeArea(
                        top: false,
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(longDate(d), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                          MetaFuture(
                            file: f,
                            builder: (m) => Text(
                              m == null ? ' ' : '${two(m.created.hour)}:${two(m.created.minute)}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(note, style: const TextStyle(color: Colors.white70)),
                          ],
                          const SizedBox(height: 4),
                          Row(children: [
                            IconButton(
                              color: Colors.white,
                              onPressed: () {
                                store.tap();
                                store.toggleFavorite(f);
                              },
                              icon: AnimatedSwitcher(
                                duration: ms(220),
                                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                                child: Icon(store.isFavorite(f) ? Icons.star_rounded : Icons.star_border_rounded, key: ValueKey(store.isFavorite(f))),
                              ),
                            ),
                            IconButton(color: Colors.white, onPressed: _share, icon: const Icon(Icons.share_outlined)),
                            if (store.voiceEnabled)
                              IconButton(
                                color: Colors.white,
                                onPressed: _voice,
                                icon: Icon(store.hasVoice(d) ? Icons.mic_rounded : Icons.mic_none_rounded),
                              ),
                            if (store.metadataEnabled) IconButton(color: Colors.white, onPressed: _info, icon: const Icon(Icons.info_outline_rounded)),
                            const Spacer(),
                            PopupMenuButton<String>(
                              iconColor: Colors.white,
                              onSelected: (v) {
                                if (v == 'note') editNote(context, f);
                                if (v == 'delete') _delete();
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'note', child: Text('Изменить подпись')),
                                PopupMenuItem(value: 'delete', child: Text('Удалить')),
                              ],
                            ),
                          ]),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ]);
          },
        ),
      );
}

/// Loads metadata once per file; keeps the future in state so the UI doesn't flicker.
class MetaFuture extends StatefulWidget {
  final File file;
  final Widget Function(Meta? meta) builder;
  const MetaFuture({super.key, required this.file, required this.builder});
  @override
  State<MetaFuture> createState() => _MetaFutureState();
}

class _MetaFutureState extends State<MetaFuture> {
  late Future<Meta> future = store.metaFor(widget.file);
  @override
  void didUpdateWidget(MetaFuture old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path) future = store.metaFor(widget.file);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Meta>(future: future, builder: (_, s) => widget.builder(s.data));
}

String _size(int b) {
  if (b < 1024) return '$b Б';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} КБ';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} МБ';
}

Future<void> openMap(BuildContext context, double lat, double lon, String label) async {
  final geo = Uri.parse('geo:$lat,$lon?q=$lat,$lon(${Uri.encodeComponent(label)})');
  final web = Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=15/$lat/$lon');
  try {
    if (await launchUrl(geo, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  try {
    if (await launchUrl(web, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  if (context.mounted) snack(context, 'Не удалось открыть карту');
}

class InfoSheet extends StatelessWidget {
  final File file;
  final ScrollController controller;
  const InfoSheet({super.key, required this.file, required this.controller});

  @override
  Widget build(BuildContext context) => MetaFuture(
        file: file,
        builder: (m) {
          if (m == null) return const Center(child: CircularProgressIndicator());
          return ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
            Text('Информация', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _section(context, 'Основное'),
            _row('Файл', m.name),
            _row('Размер', _size(m.bytes)),
            _row('Формат', m.format),
            _row('Разрешение', m.width == null ? '—' : '${m.width} × ${m.height}'),
            _row('Ширина', m.width == null ? '—' : '${m.width} px'),
            _row('Высота', m.height == null ? '—' : '${m.height} px'),
            _section(context, 'Дата'),
            _row('Дата создания', longDate(m.created)),
            _row('Время создания', '${two(m.created.hour)}:${two(m.created.minute)}'),
            if (!m.createdFromExif) const Padding(padding: EdgeInsets.only(top: 4), child: Text('В EXIF нет даты съёмки — показана дата файла.', style: TextStyle(fontSize: 12))),
            const SizedBox(height: 8),
            Card(
              child: ExpansionTile(
                initiallyExpanded: m.hasCamera,
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Камера'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: m.hasCamera
                    ? [
                        _row('Производитель', m.make ?? '—'),
                        _row('Модель', m.model ?? '—'),
                        _row('ISO', m.iso ?? '—'),
                        _row('Выдержка', m.exposure ?? '—'),
                        _row('Диафрагма', m.fnumber ?? '—'),
                        _row('Фокусное расстояние', m.focal ?? '—'),
                      ]
                    : const [Padding(padding: EdgeInsets.all(8), child: Text('Данные камеры (EXIF) отсутствуют'))],
              ),
            ),
            _section(context, 'Место'),
            if (m.hasGps) _LocationBlock(lat: m.lat!, lon: m.lon!) else const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.location_off_outlined), title: Text('Местоположение отсутствует')),
          ]);
        },
      );

  Widget _section(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
        child: Text(t.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Theme.of(context).colorScheme.primary)),
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 4, child: Text(k)),
          Expanded(flex: 5, child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

class _LocationBlock extends StatefulWidget {
  final double lat, lon;
  const _LocationBlock({required this.lat, required this.lon});
  @override
  State<_LocationBlock> createState() => _LocationBlockState();
}

class _LocationBlockState extends State<_LocationBlock> {
  late final Future<String?> place = _lookup();

  Future<String?> _lookup() async {
    try {
      final p = (await placemarkFromCoordinates(widget.lat, widget.lon)).first;
      final parts = [p.locality?.isNotEmpty == true ? p.locality : p.administrativeArea, p.country].where((e) => e != null && e.isNotEmpty).toList();
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      return null; // offline / no geocoder: fall back to plain coordinates
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final coords = '${widget.lat.toStringAsFixed(5)}, ${widget.lon.toStringAsFixed(5)}';
    return FutureBuilder<String?>(
      future: place,
      builder: (_, s) {
        final name = s.data;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Pressable(
            onTap: () => openMap(context, widget.lat, widget.lon, name ?? 'Chronos'),
            child: Container(
              height: 140,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(24)),
              child: CustomPaint(painter: _MapPainter(cs.onSecondaryContainer.withValues(alpha: .12), cs.primary), child: const SizedBox.expand()),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.place_outlined, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(name ?? coords, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          ]),
          if (name != null) Padding(padding: const EdgeInsets.only(left: 32), child: Text(coords, style: TextStyle(color: cs.onSurfaceVariant))),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => openMap(context, widget.lat, widget.lon, name ?? 'Chronos'),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Открыть на карте'),
          ),
        ]);
      },
    );
  }
}

/// Stylised card (not real map tiles) — only marks that the photo has real coordinates.
class _MapPainter extends CustomPainter {
  final Color grid, pin;
  _MapPainter(this.grid, this.pin);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = grid..strokeWidth = 1.5;
    for (var x = 0.0; x < s.width; x += 28) {
      c.drawLine(Offset(x, 0), Offset(x, s.height), p);
    }
    for (var y = 0.0; y < s.height; y += 28) {
      c.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
    final ctr = Offset(s.width / 2, s.height / 2);
    c.drawCircle(ctr, 26, Paint()..color = pin.withValues(alpha: .18));
    c.drawCircle(ctr, 9, Paint()..color = pin);
    c.drawCircle(ctr, 9, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_MapPainter o) => o.grid != grid || o.pin != pin;
}
