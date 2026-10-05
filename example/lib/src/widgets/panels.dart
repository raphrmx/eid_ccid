import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_belgium/testing.dart';
import 'package:eid_ccid_example/src/eid_session.dart';
import 'package:eid_ccid_example/src/palette.dart';
import 'package:eid_ccid_example/src/widgets/change_pin_dialog.dart';
import 'package:eid_ccid_example/src/widgets/id_card.dart';
import 'package:eid_ccid_example/src/widgets/pin_pad.dart';
import 'package:eid_ccid_example/src/widgets/reader_stage.dart';
import 'package:eid_ccid_example/src/widgets/result_panels.dart';
import 'package:flutter/material.dart';

/// The reader, the card to put in it, and what to do with the card.
class ReaderPanel extends StatelessWidget {
  const ReaderPanel({required this.session});

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
            CardPicker(session: session),
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
class CardPicker extends StatelessWidget {
  const CardPicker({required this.session});

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
class OptionsPanel extends StatelessWidget {
  const OptionsPanel({required this.session});

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

/// The card as read, then its address, checks and details.
class ResultView extends StatelessWidget {
  const ResultView({required this.session, required this.wide});

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
