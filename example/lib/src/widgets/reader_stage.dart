import 'package:eid_ccid_example/src/eid_session.dart';
import 'package:eid_ccid_example/src/palette.dart';
import 'package:eid_ccid_example/src/widgets/id_card.dart';
import 'package:flutter/material.dart';

/// A desk reader with the card above it and a status light.
/// The card goes in upright, chip edge first, where the arrow points.
class ReaderStage extends StatelessWidget {
  const ReaderStage({super.key, required this.session});

  final EidSession session;

  static const _slide = Duration(milliseconds: 700);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardWidth = width * 0.34;
        final cardHeight = cardWidth * cardAspectRatio;
        final readerWidth = width * 0.8;
        final readerHeight = width * 0.26;
        final readerTop = cardHeight + width * 0.05;
        final inserted = session.cardPresent;
        // Inserted, the card shows its top 48 %, the rest inside the reader.
        final insertedTop = readerTop - cardHeight * 0.48;

        return SizedBox(
          height: readerTop + readerHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The top of the reader and its slot, behind the card.
              Positioned(
                left: (width - readerWidth) / 2 + readerWidth * 0.03,
                width: readerWidth * 0.94,
                top: readerTop - width * 0.035,
                height: width * 0.05,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Palette.deviceEdge,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(width * 0.03),
                    ),
                  ),
                  child: Align(
                    alignment: const Alignment(0, -0.1),
                    child: Container(
                      width: cardWidth * 1.18,
                      height: width * 0.012,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E0D0C),
                        borderRadius: BorderRadius.circular(width),
                      ),
                    ),
                  ),
                ),
              ),
              // Clips the part of the card pushed into the reader.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: readerTop + readerHeight * 0.5,
                child: ClipRect(
                  child: Stack(
                    children: [
                      // Only the insertion animates; resizes apply at once.
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: inserted ? 1 : 0),
                        duration: _slide,
                        curve: Curves.easeInOutCubic,
                        builder: (context, depth, card) => Positioned(
                          left: (width - cardWidth) / 2,
                          width: cardWidth,
                          top: insertedTop * depth,
                          child: card!,
                        ),
                        child: AnimatedOpacity(
                          duration: _slide,
                          opacity: session.isSimulated || inserted ? 1 : 0,
                          // Turns the chip edge down, back facing out.
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: IdCard(
                              side: CardSide.back,
                              printedPhoto: session.printedPhoto,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // The front of the reader, in front of the card.
              Positioned(
                left: (width - readerWidth) / 2,
                width: readerWidth,
                top: readerTop,
                height: readerHeight,
                child: _ReaderFront(
                  session: session,
                  width: readerWidth,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReaderFront extends StatelessWidget {
  const _ReaderFront({required this.session, required this.width});

  final EidSession session;
  final double width;

  static Color _color(ReaderLight light) => switch (light) {
        ReaderLight.waiting || ReaderLight.working => Palette.readerBlue,
        ReaderLight.success => Palette.success,
        ReaderLight.warning => _Display._amber,
        ReaderLight.failure => Palette.danger,
      };

  @override
  Widget build(BuildContext context) {
    final light = session.light;
    final color = _color(light);
    final blinking = light == ReaderLight.working;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.06),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.deviceEdge, Palette.device, Color(0xFF1C1A18)],
        ),
        boxShadow: Palette.shadow,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: width * 0.07),
        child: Row(
          children: [
            Expanded(
              // The progress changes many times a read: only the display
              // follows it, and repaints on its own.
              child: RepaintBoundary(
                child: ListenableBuilder(
                  listenable: session.progress,
                  builder: (context, _) => _Display(
                    width: width,
                    text: _label(session),
                    caption:
                        session.isSimulated ? 'SIMULATED READER' : 'USB READER',
                    error: session.busy ? null : session.error,
                    warning: session.errorIsWarning,
                  ),
                ),
              ),
            ),
            SizedBox(width: width * 0.05),
            // The contactless mark lights up with the reader.
            _Glow(
              color: color,
              blinking: blinking,
              builder: (context, color, glow) => DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45 * glow),
                      blurRadius: width * 0.07,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.contactless_outlined,
                  color: Color.lerp(color.withValues(alpha: 0.3), color, glow),
                  size: width * 0.09,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _label(EidSession session) {
    if (session.activity == ReaderActivity.reading) {
      final progress = session.progress;
      final fraction = progress.fraction;
      return fraction == null
          ? 'Reading ${_bytes(progress.bytesRead)}'
          : 'Reading ${(fraction * 100).round()}%';
    }
    if (session.activity == ReaderActivity.awaitingPin) return 'Enter PIN';
    if (session.activity == ReaderActivity.verifying) return 'Checking PIN';
    if (!session.cardPresent) return 'Insert a card';
    if (session.eid != null) return 'Card read';
    return 'Card ready';
  }

  static String _bytes(int count) =>
      count < 1000 ? '${count}B' : '${(count / 1000).toStringAsFixed(1)}kB';
}

/// Eases into [color] and pulses while [blinking]; brightness is 0 to 1.
class _Glow extends StatefulWidget {
  const _Glow({
    required this.color,
    required this.blinking,
    required this.builder,
  });

  final Color color;
  final bool blinking;
  final Widget Function(BuildContext context, Color color, double glow) builder;

  @override
  State<_Glow> createState() => _GlowState();
}

// The pulse is an animation the controller drives; nothing else is state.
class _GlowState extends State<_Glow> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(_Glow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blinking != widget.blinking) _follow();
  }

  void _follow() {
    if (widget.blinking) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The pulse repaints every frame while reading: keep it to itself.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final glow = 0.15 + 0.85 * Curves.easeInOut.transform(_pulse.value);
          return TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: widget.color),
            duration: const Duration(milliseconds: 300),
            builder: (context, color, _) =>
                widget.builder(context, color ?? widget.color, glow),
          );
        },
      ),
    );
  }
}

/// The reader's small LED screen: light blue text, or an [error] in red.
class _Display extends StatelessWidget {
  const _Display({
    required this.width,
    required this.text,
    required this.caption,
    this.error,
    this.warning = false,
  });

  static const _lit = Color(0xFFDCEBFF);
  static const _red = Color(0xFFFF5A5F);
  static const _amber = Color(0xFFFFA53A);

  final double width;
  final String text;
  final String caption;
  final String? error;

  /// Shows [error] in amber rather than red.
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: width * 0.14,
      padding: EdgeInsets.symmetric(horizontal: width * 0.035),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0C0B),
        borderRadius: BorderRadius.circular(width * 0.018),
        border: Border.all(
          color: const Color(0xFF020302),
          width: width * 0.004,
        ),
        boxShadow: [
          // A thin highlight under the glass, where the case catches light.
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.08),
            offset: Offset(0, width * 0.004),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: const _DotMatrix(),
        child: error != null
            ? Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error!.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: width * 0.032,
                    fontWeight: FontWeight.w700,
                    letterSpacing: width * 0.002,
                    height: 1.2,
                    color: warning ? _amber : _red,
                    shadows: [
                      Shadow(
                        color: (warning ? _amber : _red).withValues(alpha: 0.6),
                        blurRadius: width * 0.02,
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: width * 0.04,
                      fontWeight: FontWeight.w700,
                      letterSpacing: width * 0.004,
                      height: 1.1,
                      color: _lit,
                      shadows: [
                        Shadow(
                          color: _lit.withValues(alpha: 0.6),
                          blurRadius: width * 0.02,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    caption,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: width * 0.024,
                      letterSpacing: width * 0.003,
                      height: 1.3,
                      color: _lit.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The fine grid of an LED screen, drawn over the text.
class _DotMatrix extends CustomPainter {
  const _DotMatrix();

  @override
  void paint(Canvas canvas, Size size) {
    // A zero pitch would never end the loops below.
    if (size.isEmpty) return;
    final pitch = size.height / 18;
    final paint = Paint()
      ..color = const Color(0xFF0A0C0B).withValues(alpha: 0.55)
      ..strokeWidth = pitch * 0.35;
    for (var y = pitch / 2; y < size.height; y += pitch) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (var x = pitch / 2; x < size.width; x += pitch) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_DotMatrix oldDelegate) => false;
}
