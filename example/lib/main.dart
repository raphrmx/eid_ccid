import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_belgium/testing.dart';
import 'package:eid_ccid_example/src/eid_session.dart';
import 'package:eid_ccid_example/src/palette.dart';
import 'package:eid_ccid_example/src/widgets/apdu_console.dart';
import 'package:eid_ccid_example/src/widgets/change_pin_dialog.dart';
import 'package:eid_ccid_example/src/widgets/id_card.dart';
import 'package:eid_ccid_example/src/widgets/pin_pad.dart';
import 'package:eid_ccid_example/src/widgets/reader_stage.dart';
import 'package:eid_ccid_example/src/widgets/result_panels.dart';
import 'package:flutter/material.dart';

void main() => runApp(const EidDemoApp());

class EidDemoApp extends StatelessWidget {
  const EidDemoApp({super.key, this.useHardware = true});

  /// Whether to look for USB readers, next to the simulated card.
  final bool useHardware;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eid_belgium demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Palette.accent,
        scaffoldBackgroundColor: Palette.paper,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Palette.accent,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Palette.ink,
            minimumSize: const Size(0, 48),
            side: const BorderSide(color: Palette.line, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      home: HomePage(useHardware: useHardware),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.useHardware = true});

  final bool useHardware;

  @override
  State<HomePage> createState() => _HomePageState();
}

// Rebuilds come from the session's listeners, not setState.
class _HomePageState extends State<HomePage> {
  late final _session = EidSession(useHardware: widget.useHardware);
  bool _pinPadOpen = false;

  @override
  void initState() {
    super.initState();
    _session
      ..addListener(_openPinPad)
      ..refreshReaders();
  }

  // The watcher asks for the PIN before reading, when pinPrompt is set.
  void _openPinPad() {
    if (!_session.pinRequested || _pinPadOpen || !mounted) return;
    _pinPadOpen = true;
    showPinPad(context, _session, prompt: true).then((_) {
      _pinPadOpen = false;
      _session.cancelPin();
    });
  }

  @override
  void dispose() {
    _session
      ..removeListener(_openPinPad)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _session,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1000;
            final gutter = constraints.maxWidth < 600 ? 16.0 : 32.0;
            final header = _Header(session: _session);
            final reader = _ReaderPanel(session: _session);
            final options = _OptionsPanel(session: _session);
            final console = ApduConsole(
              session: _session,
              height: wide ? 300 : 220,
            );
            final result = _Result(session: _session, wide: wide);

            return SingleChildScrollView(
              padding: EdgeInsets.all(gutter),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 1320 : 640),
                  child: wide
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            header,
                            const SizedBox(height: 28),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 400,
                                  child: Column(
                                    children: [
                                      reader,
                                      const SizedBox(height: 20),
                                      options,
                                      const SizedBox(height: 20),
                                      console,
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 28),
                                Expanded(child: result),
                              ],
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            header,
                            const SizedBox(height: 20),
                            reader,
                            const SizedBox(height: 20),
                            options,
                            const SizedBox(height: 20),
                            result,
                            const SizedBox(height: 20),
                            console,
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.session});

  final EidSession session;

  @override
  Widget build(BuildContext context) {
    const title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'eid_belgium',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: Palette.ink,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'Read a Belgian identity card from Flutter',
          style: TextStyle(fontSize: 15, color: Palette.muted),
        ),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 12,
      spacing: 16,
      children: [
        title,
        // The web build lists the simulated card alone: no picker then.
        if (session.readers.length > 1) _ReaderPicker(session: session),
      ],
    );
  }
}

class _ReaderPicker extends StatelessWidget {
  const _ReaderPicker({required this.session});

  final EidSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: Palette.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: Palette.softShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.usb, size: 18, color: Palette.muted),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: session.reader,
                isExpanded: true,
                items: [
                  for (final name in session.readers)
                    DropdownMenuItem(
                      value: name,
                      child: Text(name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: session.busy ? null : session.selectReader,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Look for readers again',
            onPressed: session.busy ? null : session.refreshReaders,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
    );
  }
}

class _ReaderPanel extends StatelessWidget {
  const _ReaderPanel({required this.session});

  final EidSession session;

  @override
  Widget build(BuildContext context) {
    final idle = !session.busy;
    final canRead = idle && session.cardPresent;
    return Panel(
      padding: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session.isSimulated) ...[
            _CardPicker(session: session),
            const SizedBox(height: 8),
          ],
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: ReaderStage(session: session),
            ),
          ),
          const SizedBox(height: 20),
          if (session.isSimulated) ...[
            OutlinedButton.icon(
              onPressed: idle ? session.toggleSimulatedCard : null,
              icon: Icon(
                session.cardPresent ? Icons.eject_outlined : Icons.login,
              ),
              label: Text(session.cardPresent ? 'Remove card' : 'Insert card'),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton.icon(
            onPressed: canRead ? session.readCard : null,
            icon: const Icon(Icons.badge_outlined),
            label: const Text('Read card'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: canRead && session.eid != null
                ? () => showPinPad(context, session)
                : null,
            icon: const Icon(Icons.dialpad),
            label: const Text('Check PIN'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed:
                canRead ? () => showChangePinDialog(context, session) : null,
            icon: const Icon(Icons.password),
            label: const Text('Change PIN'),
          ),
        ],
      ),
    );
  }
}

/// The simulated cards to try, the one in use highlighted. Choosing one
/// puts a fresh card of that kind next to the reader.
class _CardPicker extends StatelessWidget {
  const _CardPicker({required this.session});

  final EidSession session;

  static const _choices = [
    (
      SimulatedKind.valid,
      'Valid',
      Icons.verified_outlined,
      Palette.success,
      'A new valid card, PIN 1234'
    ),
    (
      SimulatedKind.expired,
      'Expired',
      Icons.event_busy_outlined,
      Palette.warning,
      'A card past its last valid day'
    ),
    (
      SimulatedKind.tampered,
      'Tampered',
      Icons.edit_note,
      Palette.danger,
      'A card whose name was rewritten after the register signed it'
    ),
    (
      SimulatedKind.cloned,
      'Cloned',
      Icons.copy_all_outlined,
      Palette.danger,
      "A copy of a card's files on another chip"
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final idle = !session.busy;
    return Row(
      children: [
        for (final (kind, label, icon, color, tooltip) in _choices) ...[
          if (kind != SimulatedKind.valid) const SizedBox(width: 8),
          Expanded(
            child: _CardChoice(
              label: label,
              icon: icon,
              color: color,
              tooltip: tooltip,
              selected: session.simulatedKind == kind,
              cloned: kind == SimulatedKind.cloned,
              onTap: idle ? () => session.newSimulatedCard(kind) : null,
            ),
          ),
        ],
      ],
    );
  }
}

class _CardChoice extends StatelessWidget {
  const _CardChoice({
    required this.label,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.cloned = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  /// Draws a second card behind the first.
  final bool cloned;

  // One instance for every tile: an identical widget is not rebuilt.
  static final _miniature = ClipRRect(
    borderRadius: const BorderRadius.all(Radius.circular(5)),
    child: IgnorePointer(child: IdCard(printedPhoto: specimenPhoto)),
  );

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: Column(
            children: [
              AnimatedScale(
                scale: selected ? 1 : 0.9,
                duration: const Duration(milliseconds: 200),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (cloned)
                      Positioned.fill(
                        child: Transform.translate(
                          offset: const Offset(5, -5),
                          child: Opacity(opacity: 0.55, child: _miniature),
                        ),
                      ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: selected ? color : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: selected ? Palette.softShadow : null,
                      ),
                      child: _miniature,
                    ),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Palette.white, width: 2),
                        ),
                        child: Icon(icon, size: 11, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? color : Palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The watcher's options, applied from the next read.
class _OptionsPanel extends StatelessWidget {
  const _OptionsPanel({required this.session});

  final EidSession session;

  @override
  Widget build(BuildContext context) {
    Widget part(BelgianEidPart part, String title) => _Option(
          title: title,
          code: 'parts: ${part.name}',
          value: session.reads(part),
          onChanged: (value) => session.setReads(part, value: value),
        );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Options',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Palette.ink,
            ),
          ),
          const SizedBox(height: 4),
          _Option(
            title: 'Read on insertion',
            code: 'autoRead',
            value: session.autoRead,
            onChanged: (value) => session.autoRead = value,
          ),
          _Option(
            title: 'Ask for the PIN first',
            code: 'pinPrompt',
            value: session.askPin,
            onChanged: (value) => session.askPin = value,
          ),
          _Option(
            title: 'Check the signatures',
            code: 'verifySignatures',
            value: session.verifySignatures,
            onChanged: (value) => session.verifySignatures = value,
          ),
          _Option(
            title: 'Check the chip is genuine',
            code: 'verifyCard',
            value: session.verifyCard,
            onChanged: (value) => session.verifyCard = value,
          ),
          _Option(
            title: 'Turn down expired cards',
            code: 'acceptExpired: false',
            value: !session.acceptExpired,
            onChanged: (value) => session.acceptExpired = !value,
          ),
          const Divider(height: 20),
          part(BelgianEidPart.photo, 'Read the photo'),
          part(BelgianEidPart.address, 'Read the address'),
          part(BelgianEidPart.nationalNumber, 'Read the national number'),
          const Divider(height: 20),
          _Option(
            title: 'Remember photos',
            code: 'rememberPhotos',
            value: session.rememberPhotos,
            onChanged: (value) => session.rememberPhotos = value,
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.code,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String code;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Palette.ink,
        ),
      ),
      subtitle: Text(
        code,
        style: const TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          color: Palette.muted,
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.session, required this.wide});

  final EidSession session;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final eid = session.eid;
    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: FlippableIdCard(
        eid: eid,
        revealKey: session.readCount,
        verified: session.holderVerified,
      ),
    );

    if (eid == null) {
      return Column(
        children: [
          Opacity(opacity: 0.55, child: card),
          const SizedBox(height: 24),
          const Text(
            'Insert the card, then read it.\nNo PIN is needed to read it.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Palette.muted, height: 1.5),
          ),
        ],
      );
    }

    final address = AddressPanel(eid: eid);
    final checks = ChecksPanel(session: session);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: card),
        const SizedBox(height: 24),
        if (wide)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: address),
                const SizedBox(width: 20),
                Expanded(child: checks),
              ],
            ),
          )
        else ...[
          address,
          const SizedBox(height: 20),
          checks,
        ],
        const SizedBox(height: 20),
        DetailsPanel(session: session),
      ],
    );
  }
}
