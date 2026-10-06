import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Theme.of(context).colorScheme.primary)),
      );
}

Future<void> _open(BuildContext context, String url) async {
  try {
    if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  if (context.mounted) snack(context, 'Не удалось открыть ссылку');
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  String _mb(int b) => b < 1024 * 1024 ? '${(b / 1024).toStringAsFixed(0)} КБ' : '${(b / 1024 / 1024).toStringAsFixed(1)} МБ';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, __) => ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('Настройки', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const _Section('Внешний вид'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Тема, цвет, шрифт, иконка, анимации'),
            subtitle: Text('${store.seedIndex >= 0 ? palettes[store.seedIndex].name : 'Свой цвет'} • ${store.font}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearancePage())),
          ),
          const _Section('Воспоминания'),
          SwitchListTile(
            secondary: const Icon(Icons.cameraswitch_outlined),
            title: const Text('Фронтальная камера'),
            value: store.frontCamera,
            onChanged: (v) => store.set((p) async {
              store.frontCamera = v;
              await p.setBool('front', v);
            }),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.local_fire_department_outlined),
            title: const Text('Показывать серию'),
            value: store.showStreak,
            onChanged: (v) => store.set((p) async {
              store.showStreak = v;
              await p.setBool('showStreak', v);
            }),
          ),
          ListTile(
            leading: const Icon(Icons.high_quality_outlined),
            title: const Text('Качество фотографий'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 100, label: Text('Оригинал')),
                  ButtonSegment(value: 85, label: Text('Высокое')),
                  ButtonSegment(value: 70, label: Text('Эконом')),
                ],
                selected: {store.photoQuality},
                onSelectionChanged: (s) => store.set((p) async {
                  store.photoQuality = s.first;
                  await p.setInt('quality', s.first);
                }),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 4),
            child: Text('«Оригинал» сохраняет EXIF (камера, GPS). Сжатие экономит место, но может удалить метаданные.', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.mic_none_rounded),
            title: const Text('Голосовые заметки'),
            value: store.voiceEnabled,
            onChanged: (v) => store.set((p) async {
              store.voiceEnabled = v;
              await p.setBool('voiceOn', v);
            }),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.info_outline),
            title: const Text('Метаданные фотографий'),
            value: store.metadataEnabled,
            onChanged: (v) => store.set((p) async {
              store.metadataEnabled = v;
              await p.setBool('metaOn', v);
            }),
          ),
          const _Section('Уведомления'),
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
              final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: store.hour, minute: store.minute));
              if (t == null) return;
              await store.set((p) async {
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
                  content: TextField(controller: c, maxLength: 80, autofocus: true),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                    FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Сохранить')),
                  ],
                ),
              );
              if (r == null || r.trim().isEmpty) return;
              await store.set((p) async {
                store.reminderText = r.trim();
                await p.setString('text', r.trim());
              }, resched: true);
            },
          ),
          const _Section('Данные'),
          FutureBuilder<int>(
            future: store.storageBytes(),
            builder: (_, s) => ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('Хранилище'),
              subtitle: Text(s.hasData ? '${store.photos.length} фото • ${_mb(s.data!)}' : 'Считаем…'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Очистка кэша'),
            subtitle: const Text('Воспоминания не удаляются'),
            onTap: () async {
              await store.clearCache();
              if (context.mounted) snack(context, 'Кэш очищен');
            },
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_outlined),
            title: const Text('Экспорт'),
            subtitle: const Text('Отправить все фото через системное меню'),
            onTap: () async {
              if (store.photos.isEmpty) {
                snack(context, 'Пока нечего экспортировать');
                return;
              }
              try {
                await Share.shareXFiles([for (final f in store.photos) XFile(f.path, mimeType: 'image/jpeg')]);
              } catch (_) {
                if (context.mounted) snack(context, 'Не удалось выполнить экспорт');
              }
            },
          ),
          const _Section('О приложении'),
          const ListTile(
            leading: Icon(Icons.hourglass_bottom_rounded),
            title: Text('Chronos'),
            subtitle: Text('Версия $appVersion Beta'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(Icons.science_outlined, color: Theme.of(context).colorScheme.onTertiaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Вы используете тестовую версию Chronos. Возможны ошибки и нестабильная работа некоторых функций.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.code_rounded),
            title: const Text('GitHub'),
            subtitle: const Text('Исходный код проекта'),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: () => _open(context, repoUrl),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Сообщить об ошибке'),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: () => _open(context, '$repoUrl/issues/new'),
          ),
          const ListTile(
            leading: Icon(Icons.person_outline),
            title: Text('Разработчик'),
            subtitle: Text('UseurHead281'),
          ),
          const SizedBox(height: 24),
        ]),
      );
}

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Внешний вид')),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final cs = Theme.of(context).colorScheme;
            return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              const _Section('Тема'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Системная')),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Светлая')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Тёмная')),
                  ],
                  selected: {store.themeMode},
                  onSelectionChanged: (s) => store.set((p) async {
                    store.tap();
                    store.themeMode = s.first;
                    await p.setInt('theme', s.first.index);
                  }),
                ),
              ),
              const _Section('Цвет'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Wrap(spacing: 12, runSpacing: 12, children: [
                  for (var i = 0; i < palettes.length; i++)
                    _Swatch(
                      color: palettes[i].color,
                      label: palettes[i].name,
                      selected: store.seedIndex == i,
                      onTap: () => store.set((p) async {
                        store.tap();
                        store.seedIndex = i;
                        await p.setInt('seed', i);
                      }),
                    ),
                  _Swatch(
                    color: Color(store.customColor),
                    label: 'Свой',
                    icon: Icons.colorize_rounded,
                    selected: store.seedIndex == -1,
                    onTap: () async {
                      final c = await pickColor(context, Color(store.customColor));
                      if (c == null) return;
                      await store.set((p) async {
                        store.seedIndex = -1;
                        store.customColor = c.toARGB32();
                        await p.setInt('seed', -1);
                        await p.setInt('customColor', c.toARGB32());
                      });
                    },
                  ),
                ]),
              ),
              const _Section('Шрифт'),
              for (final f in fontNames)
                RadioListTile<String>(
                  value: f,
                  groupValue: store.font,
                  title: Text(f, style: fontTheme(f, Theme.of(context).textTheme).bodyLarge),
                  onChanged: (v) => store.set((p) async {
                    store.tap();
                    store.font = v!;
                    await p.setString('font', v);
                  }),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Text('Шрифты Inter, Manrope, Nunito и Roboto загружаются при первом выборе (нужен интернет).', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
              const _Section('Иконка приложения'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: [for (var i = 1; i <= 6; i++) _IconTile(i)],
                ),
              ),
              const _Section('Анимации'),
              SwitchListTile(
                secondary: const Icon(Icons.animation_outlined),
                title: const Text('Анимации'),
                value: store.animations,
                onChanged: (v) => store.set((p) async {
                  store.animations = v;
                  await p.setBool('anim', v);
                }),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.vibration_rounded),
                title: const Text('Вибро-отклик'),
                value: store.haptics,
                onChanged: (v) => store.set((p) async {
                  store.haptics = v;
                  await p.setBool('haptics', v);
                }),
              ),
            ]);
          },
        ),
      );
}

class _Swatch extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;
  const _Swatch({required this.color, required this.label, required this.selected, required this.onTap, this.icon});
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: SizedBox(
          width: 56,
          child: Column(children: [
            AnimatedContainer(
              duration: ms(220),
              curve: Curves.easeOut,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3),
              ),
              child: AnimatedScale(
                scale: selected ? 1 : 0,
                duration: ms(220),
                curve: Curves.easeOutBack,
                child: const Icon(Icons.check_rounded, color: Colors.white),
              ),
            ),
            const SizedBox(height: 4),
            icon != null && !selected
                ? Icon(icon, size: 14)
                : Text(label, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
          ]),
        ),
      );
}

class _IconTile extends StatelessWidget {
  final int n;
  const _IconTile(this.n);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = store.iconIndex == n;
    return Pressable(
      onTap: () async {
        if (selected) return;
        final ok = await store.setIcon(n);
        if (context.mounted) snack(context, ok ? 'Иконка изменена. Лаунчер может обновить её не сразу.' : 'Не удалось сменить иконку');
      },
      child: AnimatedScale(
        scale: selected ? 1.04 : 1,
        duration: ms(240),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: ms(240),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: selected ? cs.primary : Colors.transparent, width: 2),
          ),
          child: Stack(alignment: Alignment.center, children: [
            ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.asset('assets/icons/icon$n.png', width: 64, height: 64, cacheWidth: 192)),
            Positioned(
              right: 10,
              top: 10,
              child: AnimatedScale(
                scale: selected ? 1 : 0,
                duration: ms(260),
                curve: Curves.easeOutBack,
                child: Icon(Icons.check_circle_rounded, color: cs.primary),
              ),
            ),
            if (selected) Positioned(bottom: 6, child: Text('Текущая', style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer))),
          ]),
        ),
      ),
    );
  }
}
