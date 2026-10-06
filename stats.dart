import 'package:flutter/material.dart';
import '../store.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, __) {
          final cs = Theme.of(context).colorScheme;
          final now = DateTime.now();
          final tt = Theme.of(context).textTheme;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
            Text('Статистика', style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _card(context, '${store.photos.length}', 'всего фото', Icons.photo_library_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _card(context, '${store.bestStreak}', 'лучший стрик', Icons.emoji_events_rounded)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _card(context, '${store.currentMonthCount}', 'этот месяц', Icons.calendar_month_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _card(context, '${store.currentYearCount}', 'этот год', Icons.date_range_rounded)),
            ]),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${monthNom[now.month - 1]} ${now.year}', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: store.completionRate),
                    duration: ms(600),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 10, borderRadius: BorderRadius.circular(20)),
                  ),
                  const SizedBox(height: 8),
                  Text('${(store.completionRate * 100).round()}% дней уже сохранено', style: TextStyle(color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Последние 35 дней', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  _heatmap(context),
                ]),
              ),
            ),
          ]);
        },
      );

  Widget _card(BuildContext context, String value, String label, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon),
            const SizedBox(height: 12),
            Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      );

  Widget _heatmap(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = dayOnly(DateTime.now());
    final have = store.days;
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: List.generate(35, (i) {
        final d = today.subtract(Duration(days: 34 - i));
        final active = have.contains(d);
        return Tooltip(
          message: '${pretty(d)}${active ? ' • фото есть' : ''}',
          child: AnimatedContainer(
            duration: ms(300),
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: active ? cs.primary : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
          ),
        );
      }),
    );
  }
}
