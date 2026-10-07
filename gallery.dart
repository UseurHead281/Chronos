import 'dart:io';
import 'package:flutter/material.dart';
import '../store.dart';
import '../widgets.dart';
import 'viewer.dart';
import '../animations.dart';

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  String query = '';
  bool onlyFavorites = false;

  bool _matches(File f, String q) {
    if (q.isEmpty) return true;
    final d = store.dateOf(f);
    final hay = [
      pretty(d),
      keyOf(d),
      longDate(d).toLowerCase(),
      monthNom[d.month - 1].toLowerCase(),
      store.noteFor(f).toLowerCase(),
    ];
    return hay.any((s) => s.contains(q));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, __) {
          final q = query.trim().toLowerCase();
          final list = store.photos.where((f) => _matches(f, q) && (!onlyFavorites || store.isFavorite(f))).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(children: [
                Expanded(child: Text('Мои моменты', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800))),
                PopupMenuButton<bool>(
                  icon: const Icon(Icons.grid_view_rounded),
                  onSelected: (v) async {
                    store.compactGallery = v;
                    await store.set((p) async => p.setBool('compact', v));
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: false, child: Text('Крупные плитки')),
                    PopupMenuItem(value: true, child: Text('Компактная сетка')),
                  ],
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SearchBar(
                hintText: 'Поиск: дата, месяц, подпись',
                elevation: const WidgetStatePropertyAll(0),
                leading: const Icon(Icons.search_rounded),
                onChanged: (v) => setState(() => query = v),
                trailing: [
                  if (query.isNotEmpty) IconButton(onPressed: () => setState(() => query = ''), icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                ChoiceChip(label: const Text('Все'), selected: !onlyFavorites, onSelected: (_) => setState(() => onlyFavorites = false)),
                const SizedBox(width: 8),
                ChoiceChip(
                  avatar: const Icon(Icons.star_rounded, size: 18),
                  label: const Text('Избранное'),
                  selected: onlyFavorites,
                  onSelected: (_) => setState(() => onlyFavorites = true),
                ),
              ]),
            ),
            Expanded(
              child: list.isEmpty
                  ? EmptyState(
                      store.photos.isEmpty ? Icons.photo_camera_back_rounded : (onlyFavorites && q.isEmpty ? Icons.star_border_rounded : Icons.search_off_rounded),
                      store.photos.isEmpty ? 'Пока здесь пусто' : (onlyFavorites && q.isEmpty ? 'Нет избранного' : 'Ничего не найдено'),
                      store.photos.isEmpty ? 'Сделай первое фото дня — оно появится здесь.' : 'Попробуй изменить запрос или фильтр.',
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: store.compactGallery ? 4 : 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: list.length,
                      itemBuilder: (_, i) => FadeSlideIn(delay: (i % 6) * 25, child: _tile(context, list[i])),
                    ),
            ),
          ]);
        },
      );

  Widget _tile(BuildContext context, File f) => Pressable(
        onTap: () => openViewer(context, f),
        onLongPress: () => _actions(context, f),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(fit: StackFit.expand, children: [
            Hero(tag: heroTag(f), child: Thumb(f, width: store.compactGallery ? 240 : 360)),
            if (store.isFavorite(f)) const Positioned(right: 5, top: 5, child: Icon(Icons.star_rounded, color: Colors.white, size: 18)),
            if (store.hasVoice(store.dateOf(f))) const Positioned(left: 5, top: 5, child: Icon(Icons.mic_rounded, color: Colors.white, size: 16)),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(pretty(store.dateOf(f)), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ),
          ]),
        ),
      );

  Future<void> _actions(BuildContext context, File f) async {
    store.tap();
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(store.isFavorite(f) ? Icons.star_rounded : Icons.star_border_rounded),
            title: Text(store.isFavorite(f) ? 'Убрать из избранного' : 'В избранное'),
            onTap: () {
              Navigator.pop(sheet);
              store.toggleFavorite(f);
            },
          ),
          ListTile(
            leading: const Icon(Icons.notes_outlined),
            title: const Text('Изменить подпись'),
            onTap: () {
              Navigator.pop(sheet);
              editNote(context, f);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Удалить'),
            onTap: () async {
              Navigator.pop(sheet);
              if (await confirmDelete(context, f)) {
                await store.delete(f);
                if (context.mounted) snack(context, 'Воспоминание удалено');
              }
            },
          ),
        ]),
      ),
    );
  }
}
