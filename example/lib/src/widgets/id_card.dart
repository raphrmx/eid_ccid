import 'dart:math' as math;
import 'dart:typed_data';

import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_ccid_example/src/mrz.dart';
import 'package:eid_ccid_example/src/palette.dart';
import 'package:flutter/material.dart';

/// The ratio of an ID-1 card, 85.60 by 53.98 mm.
const cardAspectRatio = 85.6 / 53.98;

/// Which side of the card is drawn.
enum CardSide { front, back }

/// A Belgian eID drawn as the specimen, filled from the chip.
/// Sizes are in hundredths of the card's width; it is 63 units high.
class IdCard extends StatelessWidget {
  const IdCard({
    super.key,
    this.eid,
    this.side = CardSide.front,
    this.revealKey = 0,
    this.verified = false,
    this.printedPhoto,
  });

  final BelgianEid? eid;

  /// The photo shown until the chip's own is read.
  final Uint8List? printedPhoto;
  final CardSide side;
  final int revealKey;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    // Its own layer: the glow, the turn and the page around it never
    // repaint the card.
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: cardAspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final unit = constraints.maxWidth / 100;
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(unit * 4),
                boxShadow: Palette.shadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(unit * 4),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Many paths that never change: cached apart from the
                    // fields fading in over them.
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: _SecurityPrint(side),
                        isComplex: true,
                      ),
                    ),
                    if (side == CardSide.front)
                      _Front(
                        eid: eid,
                        photo: eid?.photo ?? printedPhoto,
                        unit: unit,
                        revealKey: revealKey,
                        verified: verified,
                      )
                    else
                      _Back(
                        eid: eid,
                        photo: eid?.photo ?? printedPhoto,
                        unit: unit,
                        revealKey: revealKey,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The full-size card, turning over on tap or from its button.
class FlippableIdCard extends StatefulWidget {
  const FlippableIdCard({
    super.key,
    required this.eid,
    required this.revealKey,
    required this.verified,
  });

  final BelgianEid? eid;
  final int revealKey;
  final bool verified;

  @override
  State<FlippableIdCard> createState() => _FlippableIdCardState();
}

// The turn is an animation the controller drives; nothing else is state.
class _FlippableIdCardState extends State<FlippableIdCard>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(FlippableIdCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new read shows the front again, where the fields come in.
    if (oldWidget.revealKey != widget.revealKey) _turn.value = 0;
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  void _flip() {
    if (_turn.isAnimating) return;
    if (_turn.value < 0.5) {
      _turn.forward();
    } else {
      _turn.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: widget.eid == null ? null : _flip,
          child: AnimatedBuilder(
            animation: _turn,
            builder: (context, _) {
              final angle =
                  Curves.easeInOutCubic.transform(_turn.value) * math.pi;
              final showsBack = angle > math.pi / 2;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(angle),
                child: showsBack
                    // Turned once more so the back reads the right way round.
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationY(math.pi),
                        child: IdCard(
                          eid: widget.eid,
                          side: CardSide.back,
                          revealKey: widget.revealKey,
                        ),
                      )
                    : IdCard(
                        eid: widget.eid,
                        revealKey: widget.revealKey,
                        verified: widget.verified,
                      ),
              );
            },
          ),
        ),
        if (widget.eid != null) ...[
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: _turn,
            builder: (context, _) => TextButton.icon(
              onPressed: _flip,
              icon: const Icon(Icons.flip_outlined, size: 18),
              label: Text(
                _turn.value < 0.5 ? 'Turn the card over' : 'Back to the front',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Front extends StatelessWidget {
  const _Front({
    required this.eid,
    required this.photo,
    required this.unit,
    required this.revealKey,
    required this.verified,
  });

  final BelgianEid? eid;
  final Uint8List? photo;
  final double unit;
  final int revealKey;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final identity = eid?.identity;
    var order = 0;
    Widget reveal(Widget child) => _Reveal(
          key: ValueKey('$revealKey-f$order'),
          index: order++,
          child: child,
        );
    Positioned at(double left, double top, Widget child, {double? width}) =>
        Positioned(
          left: unit * left,
          top: unit * top,
          width: width == null ? null : unit * width,
          child: child,
        );

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: unit * 10,
          child: _TitleBand(unit: unit),
        ),
        _BelWatermark(unit: unit, left: 5, top: 22),
        Positioned(
          left: unit * 3.5,
          top: unit * 26,
          width: unit * 29,
          child: _Photo(photo: photo, unit: unit, fade: true, wrap: reveal),
        ),
        if (identity == null) ...[
          at(4, 13, _BlankLines(unit: unit, widths: const [16, 26, 18, 22])),
          at(37, 24, _BlankLines(unit: unit, widths: const [44, 30, 34, 26])),
        ] else ...[
          at(
            4,
            11.5,
            width: 60,
            reveal(
              _Field('Nom', 'Name', identity.lastName, unit, large: true),
            ),
          ),
          at(
            4,
            18.5,
            width: 60,
            reveal(
              _Field('Prénoms', 'Given names', _givenNames(identity), unit,
                  large: true),
            ),
          ),
          at(
              37,
              24,
              width: 11,
              reveal(_Field('Sexe', 'Sex', _sex(identity.sex), unit,
                  stacked: true))),
          at(
              48,
              24,
              width: 17,
              reveal(_Field('Nationalité', 'Nationality',
                  identity.nationality.toUpperCase(), unit,
                  stacked: true))),
          at(
              66,
              24,
              width: 22,
              reveal(_Field(
                  'Date de naissance', 'Date of birth', _birth(identity), unit,
                  stacked: true))),
          at(
              37,
              33.5,
              width: 50,
              reveal(_Field('N° registre national', 'National Register N°',
                  _nationalNumber(identity.nationalNumber), unit))),
          at(
              37,
              41,
              width: 50,
              reveal(_Field('N° de carte', 'Card N°',
                  formatBelgianCardNumber(identity.cardNumber), unit))),
          at(
              37,
              48.5,
              width: 50,
              reveal(_Field('Valable jusqu’au', 'Expires on',
                  _day(identity.validUntil), unit))),
          at(46, 55.5, width: 22, reveal(_Signature(unit: unit))),
        ],
        Positioned(
          right: unit * 3,
          top: unit * 25,
          bottom: unit * 5,
          child: _VerticalStamp(unit: unit),
        ),
        if (identity != null)
          // In the empty space right of the names, where it hides no data.
          Positioned(
            right: unit * 4,
            top: unit * 13,
            child: _Seal(unit: unit, visible: verified),
          ),
      ],
    );
  }
}

class _Back extends StatelessWidget {
  const _Back({
    required this.eid,
    required this.photo,
    required this.unit,
    required this.revealKey,
  });

  final BelgianEid? eid;
  final Uint8List? photo;
  final double unit;
  final int revealKey;

  @override
  Widget build(BuildContext context) {
    final identity = eid?.identity;
    final lines = identity == null ? null : mrzLines(identity);
    return Stack(
      children: [
        _BelWatermark(unit: unit, left: 58, top: 22),
        Positioned(
          left: unit * 7,
          top: unit * 3.5,
          child: _Code(unit: unit, seed: identity?.cardNumber ?? 'blank'),
        ),
        Positioned(
          left: unit * 28,
          top: unit * 3.5,
          right: unit * 14,
          child: identity == null
              ? _BlankLines(unit: unit, widths: const [34, 24])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('Date et lieu de délivrance',
                        'Date and Place of issue', unit),
                    Text(
                      '${_day(identity.validFrom)} '
                      '${identity.issuingMunicipality}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _valueStyle(unit),
                    ),
                  ],
                ),
        ),
        // The arrow on the edge that goes into the reader first.
        Positioned(
          left: unit * 1.2,
          top: unit * 22,
          child: _Arrow(unit: unit),
        ),
        Positioned(
          left: unit * 6,
          top: unit * 20.5,
          child: _Chip(unit: unit),
        ),
        Positioned(
          left: unit * 31.5,
          top: unit * 12.5,
          width: unit * 14,
          child: Opacity(
            opacity: 0.8,
            child: _Photo(photo: photo, unit: unit * 0.5),
          ),
        ),
        Positioned(
          left: unit * 76,
          top: unit * 19.5,
          child: _Contactless(unit: unit),
        ),
        Positioned(
          right: unit * 2.5,
          top: unit * 7,
          height: unit * 25,
          child: _VerticalStamp(unit: unit),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: unit * 36,
          bottom: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: unit * 0.5, color: const Color(0xFF8CCB8F)),
              Expanded(
                child: Container(
                  color: Colors.white.withValues(alpha: 0.6),
                  padding: EdgeInsets.symmetric(horizontal: unit * 5),
                  alignment: Alignment.center,
                  child: lines == null
                      ? _BlankLines(unit: unit, widths: const [88, 88, 88])
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < lines.length; i++)
                              _Reveal(
                                key: ValueKey('$revealKey-m$i'),
                                index: i,
                                child: FittedBox(
                                  child: Text(
                                    lines[i],
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: unit * 5,
                                      letterSpacing: unit * 0.9,
                                      height: 1.3,
                                      color: Palette.cardInk,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The front's top band: country and document in four languages, EU flag.
class _TitleBand extends StatelessWidget {
  const _TitleBand({required this.unit});

  final double unit;

  static const _titles = [
    ('BELGIQUE', "CARTE D'IDENTITE"),
    ('BELGIE', 'IDENTITEITSKAART'),
    ('BELGIEN', 'PERSONALAUSWEIS'),
    ('BELGIUM', 'IDENTITY CARD'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.fromLTRB(unit * 3.5, unit * 1.2, unit * 3, unit * 1.2),
      color: Palette.cardSky.withValues(alpha: 0.55),
      child: Row(
        children: [
          for (final (country, document) in _titles)
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      country,
                      style: TextStyle(
                        fontSize: unit * 3.4,
                        letterSpacing: unit * 0.15,
                        color: Palette.cardInk,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      document,
                      style: TextStyle(
                        fontSize: unit * 1.75,
                        fontWeight: FontWeight.w800,
                        color: Palette.cardInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SizedBox(width: unit * 1.5),
          _EuFlag(unit: unit),
        ],
      ),
    );
  }
}

/// The European flag with the country code in its circle of stars.
class _EuFlag extends StatelessWidget {
  const _EuFlag({required this.unit});

  final double unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: unit * 8.5,
      height: unit * 5.8,
      decoration: BoxDecoration(
        color: Palette.euBlue,
        borderRadius: BorderRadius.circular(unit * 0.4),
      ),
      child: CustomPaint(
        painter: _StarsPainter(unit),
        child: Center(
          child: Text(
            'BE',
            style: TextStyle(
              fontSize: unit * 1.9,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _StarsPainter extends CustomPainter {
  const _StarsPainter(this.unit);

  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFFCC00);
    final center = size.center(Offset.zero);
    final radius = size.height * 0.34;
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        unit * 0.32,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarsPainter oldDelegate) => oldDelegate.unit != unit;
}

/// The holder's photo, in grey as the card prints it.
class _Photo extends StatelessWidget {
  const _Photo({
    required this.photo,
    required this.unit,
    this.fade = false,
    this.wrap,
  });

  final Uint8List? photo;
  final double unit;

  /// Whether the edges melt into the print, as on the front.
  final bool fade;
  final Widget Function(Widget child)? wrap;

  static const _grey = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final image = photo;
    Widget picture = image == null
        ? ColoredBox(color: Palette.cardLine.withValues(alpha: 0.22))
        // Grey, then multiplied into the card's green, as it is printed.
        : ColorFiltered(
            colorFilter:
                const ColorFilter.mode(Palette.cardMint, BlendMode.multiply),
            child: ColorFiltered(
              colorFilter: _grey,
              child: Image.memory(
                image,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          );
    if (fade) {
      // Sides and top fade into the print; the bottom runs to the edge.
      picture = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0, 0.18, 0.82, 1],
        ).createShader(rect),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black],
            stops: [0, 0.2],
          ).createShader(rect),
          child: picture,
        ),
      );
    } else {
      picture = ClipRRect(
        borderRadius: BorderRadius.circular(unit),
        child: picture,
      );
    }
    return AspectRatio(
      aspectRatio: 150 / 195,
      child: image == null ? picture : (wrap ?? (child) => child)(picture),
    );
  }
}

/// A label in the card's language then in English, as `Nom / Name`.
class _Label extends StatelessWidget {
  const _Label(this.local, this.english, this.unit, {this.stacked = false});

  final String local;
  final String english;
  final double unit;

  /// Whether the English goes on its own line, for narrow columns.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: unit * 1.95,
      color: Palette.cardLabel,
      height: 1.15,
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$local /',
              style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            english,
            style: style.copyWith(fontStyle: FontStyle.italic),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: '$local / '),
          TextSpan(
            text: english,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(
    this.local,
    this.english,
    this.value,
    this.unit, {
    this.large = false,
    this.stacked = false,
  });

  final bool stacked;
  final String local;
  final String english;
  final String value;
  final double unit;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(local, english, unit, stacked: stacked),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _valueStyle(unit, large: large),
        ),
      ],
    );
  }
}

TextStyle _valueStyle(double unit, {bool large = false}) => TextStyle(
      fontSize: unit * (large ? 3.6 : 3.0),
      fontWeight: FontWeight.w700,
      letterSpacing: unit * 0.08,
      color: Palette.cardInk,
      height: 1.15,
    );

/// Grey bars where the text goes, on the card before it is read.
class _BlankLines extends StatelessWidget {
  const _BlankLines({required this.unit, required this.widths});

  final double unit;
  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final width in widths)
          Padding(
            padding: EdgeInsets.symmetric(vertical: unit * 1.1),
            child: Container(
              width: unit * width,
              height: unit * 2.8,
              decoration: BoxDecoration(
                color: Palette.cardLine.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(unit),
              ),
            ),
          ),
      ],
    );
  }
}

/// Fades and lifts a field into place, [index] steps after the first.
class _Reveal extends StatelessWidget {
  const _Reveal({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  static const _step = 70;
  static const _length = 420;

  @override
  Widget build(BuildContext context) {
    final start = index * _step;
    final total = start + _length;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      builder: (context, t, child) {
        final local = ((t * total - start) / _length).clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(local);
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(0, (1 - eased) * 8),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// A signature, drawn: a made-up flourish, as on a specimen.
class _Signature extends StatelessWidget {
  const _Signature({required this.unit});

  final double unit;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(unit * 22, unit * 6),
      painter: const _SignaturePainter(),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.04, h * 0.7)
      ..cubicTo(w * 0.02, h * 0.1, w * 0.16, h * 0.05, w * 0.14, h * 0.45)
      ..cubicTo(w * 0.12, h * 0.85, w * 0.05, h * 0.95, w * 0.1, h * 0.75)
      ..cubicTo(w * 0.2, h * 0.4, w * 0.26, h * 0.9, w * 0.32, h * 0.6)
      ..cubicTo(w * 0.36, h * 0.35, w * 0.4, h * 0.85, w * 0.46, h * 0.55)
      ..cubicTo(w * 0.5, h * 0.3, w * 0.54, h * 0.9, w * 0.6, h * 0.55)
      ..cubicTo(w * 0.64, h * 0.3, w * 0.7, h * 0.85, w * 0.76, h * 0.6)
      ..cubicTo(w * 0.82, h * 0.4, w * 0.88, h * 0.75, w * 0.97, h * 0.5);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.06
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF151A22),
    );
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => false;
}

/// The gold contact chip, which this package reads.
class _Chip extends StatelessWidget {
  const _Chip({required this.unit});

  final double unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: unit * 14,
      height: unit * 11,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(unit * 2.2),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4DA94), Color(0xFFD0A24A), Color(0xFFEFCB78)],
        ),
        border: Border.all(color: const Color(0xFFB58A35), width: unit * 0.25),
      ),
      child: CustomPaint(painter: _ChipContacts(unit)),
    );
  }
}

class _ChipContacts extends CustomPainter {
  const _ChipContacts(this.unit);

  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8E6A26)
      ..strokeWidth = unit * 0.3
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    final middle = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: w * 0.32,
        height: h * 0.5,
      ),
      Radius.circular(unit * 1.2),
    );
    canvas
      ..drawRRect(middle, paint)
      ..drawLine(Offset(0, h * 0.34), Offset(w * 0.34, h * 0.34), paint)
      ..drawLine(Offset(0, h * 0.66), Offset(w * 0.34, h * 0.66), paint)
      ..drawLine(Offset(w * 0.66, h * 0.34), Offset(w, h * 0.34), paint)
      ..drawLine(Offset(w * 0.66, h * 0.66), Offset(w, h * 0.66), paint)
      ..drawLine(Offset(w * 0.5, 0), Offset(w * 0.5, h * 0.25), paint)
      ..drawLine(Offset(w * 0.5, h * 0.75), Offset(w * 0.5, h), paint);
  }

  @override
  bool shouldRepaint(_ChipContacts oldDelegate) => oldDelegate.unit != unit;
}

/// The green arrow printed by the chip: this edge goes into the reader.
class _Arrow extends StatelessWidget {
  const _Arrow({required this.unit});

  final double unit;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(unit * 3.2, unit * 7),
      painter: const _ArrowPainter(),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height / 2)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF7CC48A));
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) => false;
}

/// The copper mark of the contactless antenna.
class _Contactless extends StatelessWidget {
  const _Contactless({required this.unit});

  final double unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: unit * 11,
      height: unit * 5,
      decoration: BoxDecoration(
        color: const Color(0xFFC58363),
        borderRadius: BorderRadius.circular(unit * 0.4),
      ),
      alignment: Alignment.center,
      child: Container(
        width: unit * 3.2,
        height: unit * 3.2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Palette.cardPale, width: unit * 0.55),
        ),
      ),
    );
  }
}

/// The large BEL letters printed faintly into the background.
class _BelWatermark extends StatelessWidget {
  const _BelWatermark({
    required this.unit,
    required this.left,
    required this.top,
  });

  final double unit;
  final double left;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: unit * left,
      top: unit * top,
      child: Text(
        'BEL',
        style: TextStyle(
          fontSize: unit * 11,
          fontWeight: FontWeight.w900,
          letterSpacing: unit,
          foreground: _outline(unit),
        ),
      ),
    );
  }

  // TextStyle compares paints by identity: a new one each build would lay
  // the text out again. A few card sizes show at once, so one per size.
  static final _outlines = <double, Paint>{};

  static Paint _outline(double unit) {
    if (_outlines.length >= 8 && !_outlines.containsKey(unit)) {
      _outlines.clear();
    }
    return _outlines.putIfAbsent(
      unit,
      () => Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.25
        ..color = Palette.cardLine.withValues(alpha: 0.45),
    );
  }
}

/// Decorative dots standing for the printed code, drawn from [seed].
class _Code extends StatelessWidget {
  const _Code({required this.unit, required this.seed});

  final double unit;
  final String seed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(unit * 0.8),
      color: Colors.white.withValues(alpha: 0.7),
      child: CustomPaint(
        size: Size.square(unit * 13),
        painter: _CodePainter(seed),
      ),
    );
  }
}

class _CodePainter extends CustomPainter {
  const _CodePainter(this.seed);

  final String seed;

  static const _cells = 21;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _cells;
    final paint = Paint()..color = const Color(0xFF151A22);
    final random =
        math.Random(seed.codeUnits.fold<int>(7, (a, b) => a * 31 + b));
    for (var y = 0; y < _cells; y++) {
      for (var x = 0; x < _cells; x++) {
        final finder = _finder(x, y);
        final on = finder ?? random.nextInt(5) < 2;
        if (on) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
        }
      }
    }
  }

  // The three corner squares a 2D code is recognised by; null elsewhere.
  static bool? _finder(int x, int y) {
    for (final (ox, oy) in const [(0, 0), (_cells - 7, 0), (0, _cells - 7)]) {
      final dx = x - ox;
      final dy = y - oy;
      if (dx >= -1 && dx <= 7 && dy >= -1 && dy <= 7) {
        if (dx < 0 || dy < 0 || dx > 6 || dy > 6) return false;
        final ring = math.min(math.min(dx, dy), math.min(6 - dx, 6 - dy));
        return ring != 1;
      }
    }
    return null;
  }

  @override
  bool shouldRepaint(_CodePainter oldDelegate) => oldDelegate.seed != seed;
}

class _VerticalStamp extends StatelessWidget {
  const _VerticalStamp({required this.unit});

  final double unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: unit, horizontal: unit * 0.3),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF151A22), width: unit * 0.3),
      ),
      child: RotatedBox(
        quarterTurns: 3,
        child: FittedBox(
          child: Text(
            'SPECIMEN',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: unit * 3.8,
              letterSpacing: unit * 0.4,
              color: const Color(0xFF151A22),
            ),
          ),
        ),
      ),
    );
  }
}

/// The stamp a checked PIN puts on the card.
class _Seal extends StatelessWidget {
  const _Seal({required this.unit, required this.visible});

  final double unit;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1 : 1.6,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 260),
        child: Transform.rotate(
          angle: -0.12,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: unit * 2,
              vertical: unit,
            ),
            decoration: BoxDecoration(
              color: Palette.cardPale.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(unit * 1.4),
              border: Border.all(color: Palette.success, width: unit * 0.45),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, size: unit * 3.8, color: Palette.success),
                SizedBox(width: unit * 0.8),
                Text(
                  'HOLDER VERIFIED',
                  style: TextStyle(
                    fontSize: unit * 2.4,
                    fontWeight: FontWeight.w800,
                    letterSpacing: unit * 0.2,
                    color: Palette.success,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mint background and its guilloche waves.
class _SecurityPrint extends CustomPainter {
  const _SecurityPrint(this.side);

  final CardSide side;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Palette.cardMint, Palette.cardPale, Palette.cardMint],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );

    final wave = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width / 1000
      ..color = Palette.cardLine.withValues(alpha: 0.35);
    final phase = side == CardSide.front ? 0.0 : 1.3;
    for (var line = 0; line < 34; line++) {
      final path = Path();
      final base = size.height * (line + 0.5) / 34;
      for (var x = 0.0; x <= size.width; x += size.width / 140) {
        final y = base +
            math.sin(x / size.width * math.pi * 7 + line * 0.45 + phase) *
                size.height *
                0.02;
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, wave);
    }
  }

  @override
  bool shouldRepaint(_SecurityPrint oldDelegate) => oldDelegate.side != side;
}

String _givenNames(BelgianIdentity identity) {
  final third = identity.thirdGivenNameInitial;
  return third == null ? identity.firstNames : '${identity.firstNames} $third.';
}

// The card prints the sex in its language then in English: F/F, V/F, W/F.
String _sex(Sex sex) => switch (sex) {
      Sex.male => 'M/M',
      Sex.female => 'F/F',
      Sex.unspecified => 'X/X',
    };

String _two(int value) => value.toString().padLeft(2, '0');

String _day(DateTime date) =>
    '${_two(date.day)} ${_two(date.month)} ${date.year}';

String _birth(BelgianIdentity identity) {
  final date = identity.birthDate;
  if (date == null) return identity.birthDateText;
  final day = date.day == null ? '  ' : _two(date.day!);
  final month = date.month == null ? '  ' : _two(date.month!);
  return '$day $month ${date.year}';
}

/// The national number as printed, or `not read`.
String _nationalNumber(String? number) =>
    number == null ? 'not read' : formatBelgianNationalNumber(number);
