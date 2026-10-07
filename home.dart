import 'dart:io';
import 'package:flutter/material.dart';
import '../store.dart';
import '../widgets.dart';
import '../animations.dart';
import 'calendar.dart';
import 'gallery.dart';
import 'settings.dart';
import 'stats.dart';
import 'viewer.dart';
import 'voice.dart';

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;

  Widget _page() {
    switch (tab) {
      case 1:
        return const CalendarPage(key: ValueKey(1));
      case 2:
        return const GalleryPage(key: ValueKey(2));
      case 3:
        return const StatsPage(key: ValueKey(3));
      case 4:
        return const SettingsPage(key: ValueKey(4));
      default:
        return const TodayPage(key: ValueKey(0));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: ms(260),
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, .02), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: FadeSlideIn(key: ValueKey('page-$tab'), child: _page()),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) {
            store.tap();
            setState(() => tab = i);
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Сегодня'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Календарь'),
            NavigationDestination(icon: Icon(Icons.photo_library_outlined), selectedIcon: Icon(Icons.photo_library), label: 'Фото'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Статистика'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ещё'),
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
            physics: const BouncingScrollPhysics(),
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
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Chronos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text(longDate(now), style: TextStyle(color: cs.onSurfaceVariant)),
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
              if (store.showStreak) FadeSlideIn(delay: 20, child: _streakCard(context)),
              const SizedBox(height: 14),
              FadeSlideIn(delay: 60, child: _photoCard(context, photo)),
              const SizedBox(height: 14),
              if (photo != null) FadeSlideIn(delay: 90, child: _noteCard(context, photo)),
              if (photo != null && store.voiceEnabled) ...[
                const SizedBox(height: 14),
                FadeSlideIn(delay: 120, child: VoiceNoteCard(day: dayOnly(now))),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: () async {
                  store.tap();
                  final ok = await store.takePhoto();
                  if (ok && context.mounted) snack(context, 'Фото сохранено • ${store.streak} дн. подряд 🔥');
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
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: .15), shape: BoxShape.circle),
            child: Icon(Icons.local_fire_department_rounded, size: 34, color: cs.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${store.streak} дней подряд', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(
                store.streak == 0 ? 'Сегодня можно начать новую серию' : 'Рекорд: ${store.bestStreak} • не прерывай линию',
                style: TextStyle(color: cs.onPrimaryContainer.withValues(alpha: .75)),
              ),
            ]),
          ),
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
                child: const EmptyState(Icons.photo_camera_back_outlined, 'Сохрани сегодняшний момент', 'Одно фото. Один день.'),
              )
            : Pressable(
                onTap: () => openViewer(context, photo),
                child: Stack(fit: StackFit.expand, children: [
                  Hero(tag: heroTag(photo), child: Thumb(photo, width: 900)),
                  Positioned(left: 12, top: 12, child: _tag('СЕГОДНЯ')),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton.filledTonal(
                      onPressed: () {
                        store.tap();
                        store.toggleFavorite(photo);
                      },
                      icon: AnimatedSwitcher(
                        duration: ms(200),
                        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                        child: Icon(store.isFavorite(photo) ? Icons.star_rounded : Icons.star_border_rounded, key: ValueKey(store.isFavorite(photo))),
                      ),
                    ),
                  ),
                ]),
              ),
      ),
    );
  }

  Widget _noteCard(BuildContext context, File photo) {
    final note = store.noteFor(photo);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.notes_rounded),
        title: Text(note.isEmpty ? 'Добавить подпись' : note, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(note.isEmpty ? 'Сохрани мысль или короткое описание' : 'Заметка к фото'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => editNote(context, photo),
      ),
    );
  }

  Widget _tag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .7)),
      );

  Widget _miniStat(BuildContext context, IconData icon, String value, String label) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(icon, size: 22),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      );
}
