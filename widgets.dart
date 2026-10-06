import 'dart:io';
import 'package:flutter/material.dart';
import 'store.dart';

/// Small press reaction (scale) + optional haptic.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => down = true),
        onTapCancel: () => setState(() => down = false),
        onTapUp: (_) => setState(() => down = false),
        onTap: widget.onTap == null
            ? null
            : () {
                store.tap();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: down ? .96 : 1,
          duration: ms(110),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// Thumbnail: decoded at a small size (never the original), fades in, skeleton while loading.
class Thumb extends StatelessWidget {
  final File file;
  final int width;
  final BoxFit fit;
  const Thumb(this.file, {super.key, this.width = 360, this.fit = BoxFit.cover});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Image(
        image: ResizeImage.resizeIfNeeded(width, null, FileImage(file)),
        fit: fit,
        gaplessPlayback: true,
        frameBuilder: (_, child, frame, sync) => AnimatedOpacity(
          opacity: (frame == null && !sync) ? 0 : 1,
          duration: ms(220),
          child: child,
        ),
        errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const EmptyState(this.icon, this.title, this.subtitle, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: ms(450),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Opacity(opacity: v.clamp(0, 1), child: Transform.scale(scale: .85 + .15 * v, child: child)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 52, color: cs.primary),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

void snack(BuildContext context, String text) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(text),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ));
}

Future<bool> confirmDelete(BuildContext context, File f) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Удалить воспоминание?'),
      content: Text('${longDate(store.dateOf(f))}\nФото, подпись и голосовая заметка будут удалены.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
      ],
    ),
  );
  return yes == true;
}

Future<void> editNote(BuildContext context, File f) async {
  final c = TextEditingController(text: store.noteFor(f));
  final r = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Подпись к фото'),
      content: TextField(controller: c, maxLength: 120, autofocus: true, decoration: const InputDecoration(hintText: 'Например: прогулка после школы')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Сохранить')),
      ],
    ),
  );
  if (r != null) await store.saveNote(f, r);
}

/// Simple HSV colour picker dialog (no extra packages).
Future<Color?> pickColor(BuildContext context, Color initial) {
  var hsv = HSVColor.fromColor(initial);
  return showDialog<Color>(
    context: context,
    builder: (_) => StatefulBuilder(builder: (context, setS) {
      final c = hsv.toColor();
      Widget slider(String label, double v, double max, Color active, ValueChanged<double> on) => Row(children: [
            SizedBox(width: 24, child: Text(label)),
            Expanded(child: Slider(value: v, max: max, activeColor: active, onChanged: (x) => setS(() => on(x)))),
          ]);
      return AlertDialog(
        title: const Text('Свой цвет'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: ms(150),
            height: 64,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
            alignment: Alignment.center,
            child: Text('#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                style: TextStyle(color: c.computeLuminance() > .5 ? Colors.black : Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          slider('H', hsv.hue, 360, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(), (x) => hsv = hsv.withHue(x)),
          slider('S', hsv.saturation, 1, c, (x) => hsv = hsv.withSaturation(x)),
          slider('V', hsv.value, 1, c, (x) => hsv = hsv.withValue(x)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, c), child: const Text('Выбрать')),
        ],
      );
    }),
  );
}
