import 'dart:io';
import 'package:flutter/material.dart';
import '../store.dart';
import '../widgets.dart';
import 'viewer.dart';
import '../animations.dart';

const _basePage = 1200;
const _weekdays = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];

DateTime _monthOf(int page) {
  final n = DateTime.now();
  return DateTime(n.year, n.month + (page - _basePage));
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final controller = PageController(initialPage: _basePage);
  int page = _basePage;
  DateTime selected = dayOnly(DateTime.now());

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _goToday() {
    store.tap();
    setState(() => selected = dayOnly(DateTime.now()));
    controller.animateToPage(_basePage, duration: ms(420), curve: Curves.easeInOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final month = _monthOf(page);
    return ListenableBuilder(
      listenable: store,
      builder: (_, __) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Row(children: [
            IconButton(
              onPressed: () => controller.previousPage(duration: ms(320), curve: Curves.easeOutCubic),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: ms(200),
                child: Text(
                  '${monthNom[month.month - 1]} ${month.year}',
                  key: ValueKey(month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            IconButton(
              onPressed: () => controller.nextPage(duration: ms(320), curve: Curves.easeOutCubic),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            AnimatedSize(
              duration: ms(200),
              child: page == _basePage
                  ? const SizedBox(width: 0)
                  : Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: FilledButton.tonal(onPressed: _goToday, child: const Text('Сегодня')),
                    ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final w in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(w, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 6 * 58.0 + 5 * 6,
            child: PageView.builder(
              controller: controller,
              onPageChanged: (p) {
                store.tap();
                setState(() => page = p);
              },
              itemBuilder: (_, p) => _MonthGrid(
                month: _monthOf(p),
                selected: selected,
                onSelect: (d) {
                  store.tap();
                  setState(() => selected = d);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: ms(260),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SizeTransition(sizeFactor: a, child: c)),
            child: _DayPanel(key: ValueKey('${keyOf(selected)}-${store.photoOn(selected) != null}'), day: selected),
          ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  const _MonthGrid({required this.month, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday - 1; // Monday-first
    final count = DateTime(month.year, month.month + 1, 0).day;
    final today = dayOnly(DateTime.now());
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        mainAxisExtent: 58,
      ),
      itemCount: 42,
      itemBuilder: (_, i) {
        final n = i - offset + 1;
        if (n < 1 || n > count) return const SizedBox.shrink();
        final d = DateTime(month.year, month.month, n);
        final photo = store.photoOn(d);
        final isSel = d == selected;
        final isToday = d == today;
        final future = d.isAfter(today);
        final fg = isSel
            ? cs.onPrimary
            : (future ? cs.onSurface.withValues(alpha: .38) : cs.onSurface);
        return FadeSlideIn(child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: ms(180 + (i * 8).clamp(0, 240)),
          curve: Curves.easeOut,
          builder: (_, v, child) => Opacity(opacity: v, child: Transform.scale(scale: .9 + .1 * v, child: child)),
          child: Pressable(
            onTap: () => onSelect(d),
            child: AnimatedContainer(
              duration: ms(220),
              curve: Curves.easeOut,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: isSel ? cs.primary : (photo != null ? cs.primaryContainer : Colors.transparent),
                border: isToday && !isSel ? Border.all(color: cs.primary, width: 2) : null,
              ),
              child: Stack(fit: StackFit.expand, children: [
                if (photo != null && !isSel) Opacity(opacity: .85, child: Thumb(photo, width: 120)),
                if (photo != null && !isSel) Container(color: Colors.black26),
                Center(
                  child: Text(
                    '$n',
                    style: TextStyle(
                      fontWeight: (isToday || isSel || photo != null) ? FontWeight.w800 : FontWeight.w500,
                      color: (photo != null && !isSel) ? Colors.white : fg,
                    ),
                  ),
                ),
                if (photo != null && isSel)
                  Positioned(
                    bottom: 5,
                    left: 0,
                    right: 0,
                    child: Center(child: Container(width: 5, height: 5, decoration: BoxDecoration(color: cs.onPrimary, shape: BoxShape.circle))),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _DayPanel extends StatelessWidget {
  final DateTime day;
  const _DayPanel({super.key, required this.day});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final File? photo = store.photoOn(day);
    final isFuture = day.isAfter(dayOnly(DateTime.now()));
    if (photo == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Icon(Icons.event_available_outlined, size: 36, color: cs.primary),
            const SizedBox(height: 8),
            Text(longDate(day), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(isFuture ? 'Этот день ещё впереди' : 'В этот день нет воспоминания', style: TextStyle(color: cs.onSurfaceVariant)),
            if (!isFuture) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final ok = await store.pickFromGallery(day);
                  if (ok && context.mounted) snack(context, 'Воспоминание добавлено');
                },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Добавить из галереи'),
              ),
            ],
          ]),
        ),
      );
    }
    final note = store.noteFor(photo);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Pressable(
        onTap: () => openViewer(context, photo),
        child: Row(children: [
          SizedBox(width: 120, height: 120, child: Hero(tag: heroTag(photo), child: Thumb(photo, width: 360))),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(longDate(day), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  if (store.isFavorite(photo)) Icon(Icons.star_rounded, color: cs.primary, size: 20),
                  if (store.hasVoice(day)) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.mic_rounded, color: cs.primary, size: 20)),
                ]),
                const SizedBox(height: 6),
                Text(note.isEmpty ? 'Без подписи' : note, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
