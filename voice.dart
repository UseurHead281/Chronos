import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../store.dart';
import '../widgets.dart';

String _mmss(Duration d) => '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';

class VoiceNoteCard extends StatefulWidget {
  final DateTime day;
  const VoiceNoteCard({super.key, required this.day});
  @override
  State<VoiceNoteCard> createState() => _VoiceNoteCardState();
}

class _VoiceNoteCardState extends State<VoiceNoteCard> {
  final rec = AudioRecorder();
  final player = AudioPlayer();
  bool recording = false, paused = false, playing = false;
  Duration elapsed = Duration.zero, pos = Duration.zero, total = Duration.zero;
  final levels = List<double>.filled(32, .08);
  Timer? timer;
  final subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    subs.add(player.onPositionChanged.listen((p) => mounted ? setState(() => pos = p) : null));
    subs.add(player.onDurationChanged.listen((d) => mounted ? setState(() => total = d) : null));
    subs.add(player.onPlayerStateChanged.listen((s) => mounted ? setState(() => playing = s == PlayerState.playing) : null));
    subs.add(player.onPlayerComplete.listen((_) => mounted ? setState(() => pos = Duration.zero) : null));
    _loadDuration();
  }

  Future<void> _loadDuration() async {
    final f = store.voiceFile(widget.day);
    if (!f.existsSync()) return;
    try {
      await player.setSource(DeviceFileSource(f.path));
      final d = await player.getDuration();
      if (mounted && d != null) setState(() => total = d);
    } catch (_) {}
  }

  @override
  void dispose() {
    timer?.cancel();
    for (final s in subs) {
      s.cancel();
    }
    if (recording) rec.stop();
    rec.dispose();
    player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await rec.hasPermission()) {
        if (mounted) snack(context, 'Нужно разрешение на микрофон');
        return;
      }
      await player.stop();
      await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: store.voiceFile(widget.day).path);
      store.tap();
      setState(() {
        recording = true;
        paused = false;
        elapsed = Duration.zero;
        levels.fillRange(0, levels.length, .08);
      });
      timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!paused && mounted) setState(() => elapsed += const Duration(milliseconds: 100));
      });
      subs.add(rec.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
        if (!mounted || paused) return;
        final l = ((a.current + 45) / 45).clamp(.08, 1.0).toDouble();
        setState(() {
          levels.removeAt(0);
          levels.add(l);
        });
      }));
    } catch (_) {
      if (mounted) snack(context, 'Не удалось начать запись');
    }
  }

  Future<void> _pauseResume() async {
    store.tap();
    if (paused) {
      await rec.resume();
    } else {
      await rec.pause();
    }
    setState(() => paused = !paused);
  }

  Future<void> _stop() async {
    store.tap();
    timer?.cancel();
    try {
      await rec.stop();
    } catch (_) {}
    setState(() {
      recording = false;
      paused = false;
    });
    await store.voiceChanged();
    pos = Duration.zero;
    await _loadDuration();
  }

  Future<void> _toggle() async {
    store.tap();
    final f = store.voiceFile(widget.day);
    if (playing) {
      await player.pause();
    } else if (pos == Duration.zero) {
      await player.play(DeviceFileSource(f.path));
    } else {
      await player.resume();
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить голосовую заметку?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (yes != true) return;
    await player.stop();
    await store.deleteVoice(widget.day);
    if (mounted) {
      setState(() {
        total = Duration.zero;
        pos = Duration.zero;
      });
      snack(context, 'Голосовая заметка удалена');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (_, __) {
        final has = store.hasVoice(widget.day);
        Widget body;
        if (recording) {
          body = Column(key: const ValueKey('rec'), children: [
            Row(children: [
              Icon(Icons.fiber_manual_record, color: paused ? cs.outline : cs.error, size: 16),
              const SizedBox(width: 8),
              Text(paused ? 'Пауза' : 'Запись', style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(_mmss(elapsed), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, fontFeatures: [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 12),
            SizedBox(height: 48, child: _Bars(levels: levels, color: cs.primary)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              FilledButton.tonalIcon(onPressed: _pauseResume, icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded), label: Text(paused ? 'Продолжить' : 'Пауза')),
              const SizedBox(width: 12),
              FilledButton.icon(onPressed: _stop, icon: const Icon(Icons.stop_rounded), label: const Text('Стоп')),
            ]),
          ]);
        } else if (has) {
          final progress = total.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
          body = Row(key: const ValueKey('play'), children: [
            IconButton.filled(onPressed: _toggle, icon: AnimatedSwitcher(duration: ms(180), child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(playing)))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(height: 36, child: _Bars(levels: _staticWave(widget.day), color: cs.primary, progress: progress, animate: playing)),
                const SizedBox(height: 4),
                Text('${_mmss(pos)} / ${_mmss(total)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
            ),
            IconButton(onPressed: _start, tooltip: 'Перезаписать', icon: const Icon(Icons.mic_none_rounded)),
            IconButton(onPressed: _delete, tooltip: 'Удалить', icon: const Icon(Icons.delete_outline_rounded)),
          ]);
        } else {
          body = SizedBox(
            key: const ValueKey('idle'),
            width: double.infinity,
            child: FilledButton.tonalIcon(onPressed: _start, icon: const Icon(Icons.mic_rounded), label: const Text('Добавить голосовую заметку')),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AnimatedSize(
              duration: ms(240),
              curve: Curves.easeOut,
              child: AnimatedSwitcher(duration: ms(220), child: body),
            ),
          ),
        );
      },
    );
  }

  // Deterministic decorative waveform (the file itself isn't analysed).
  List<double> _staticWave(DateTime d) {
    final r = math.Random(d.year * 400 + d.month * 40 + d.day);
    return List.generate(32, (_) => .2 + r.nextDouble() * .8);
  }
}

class _Bars extends StatelessWidget {
  final List<double> levels;
  final Color color;
  final double? progress;
  final bool animate;
  const _Bars({required this.levels, required this.color, this.progress, this.animate = true});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < levels.length; i++)
              Expanded(
                child: Center(
                  child: AnimatedContainer(
                    duration: ms(100),
                    width: 4,
                    height: math.max(4, levels[i] * c.maxHeight),
                    decoration: BoxDecoration(
                      color: (progress == null || i / levels.length <= progress!) ? color : color.withValues(alpha: .28),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}
