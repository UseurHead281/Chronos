import 'package:flutter/material.dart';
import 'store.dart';

class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int delay;
  final Offset begin;
  const FadeSlideIn({super.key, required this.child, this.delay = 0, this.begin = const Offset(0, .025)});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: ms(420 + delay),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(begin.dx * (1 - value) * 100, begin.dy * (1 - value) * 100),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class AnimatedPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const AnimatedPress({super.key, required this.child, this.onTap});

  @override
  State<AnimatedPress> createState() => _AnimatedPressState();
}

class _AnimatedPressState extends State<AnimatedPress> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => pressed = true),
        onTapCancel: () => setState(() => pressed = false),
        onTapUp: (_) => setState(() => pressed = false),
        onTap: widget.onTap == null ? null : () { store.tap(); widget.onTap!(); },
        child: AnimatedScale(
          scale: pressed ? .975 : 1,
          duration: ms(120),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      );
}
