import 'dart:math' as math;

import 'package:eid_ccid_example/src/eid_session.dart';
import 'package:eid_ccid_example/src/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks for the PIN on a keypad and has the card check it.
/// With [prompt], answers the waiting watcher; closes if the card is out.
Future<void> showPinPad(
  BuildContext context,
  EidSession session, {
  bool prompt = false,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x661D1712),
    barrierDismissible: !prompt,
    builder: (context) => PinPad(session: session, prompt: prompt),
  );
}

enum _PadState { typing, checking, accepted, wrong, blocked, failed }

class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.session, this.prompt = false});

  final EidSession session;

  /// Whether the watcher asked for the PIN before a read.
  final bool prompt;

  @override
  State<PinPad> createState() => _PinPadState();
}

// The two notifiers hold the pad's state; this object owns the shake.
class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  final _digits = ValueNotifier('');
  final _state = ValueNotifier(_PadState.typing);
  final _focus = FocusNode();
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  @override
  void initState() {
    super.initState();
    if (widget.prompt) widget.session.addListener(_followPrompt);
  }

  // The watcher stopped waiting mid-typing: the card went out.
  void _followPrompt() {
    final typing =
        _state.value == _PadState.typing || _state.value == _PadState.wrong;
    if (typing &&
        !widget.session.pinRequested &&
        mounted &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_followPrompt);
    _digits.dispose();
    _state.dispose();
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  bool get _locked =>
      _state.value == _PadState.checking ||
      _state.value == _PadState.accepted ||
      _state.value == _PadState.blocked;

  void _type(String digit) {
    if (_locked || _digits.value.length >= 12) return;
    _digits.value += digit;
    if (_state.value != _PadState.checking) _state.value = _PadState.typing;
  }

  void _erase() {
    if (_locked || _digits.value.isEmpty) return;
    _digits.value = _digits.value.substring(0, _digits.value.length - 1);
  }

  Future<void> _submit() async {
    if (_locked || _digits.value.length < 4) return;
    _state.value = _PadState.checking;
    final session = widget.session;
    final outcome = widget.prompt
        ? await session.answerPin(_digits.value)
        : await session.verifyPin(_digits.value);
    if (!mounted) return;
    _digits.value = '';
    _state.value = switch (outcome) {
      PinOutcome.accepted => _PadState.accepted,
      PinOutcome.wrong => _PadState.wrong,
      PinOutcome.blocked => _PadState.blocked,
      PinOutcome.failed => _PadState.failed,
    };
    if (outcome == PinOutcome.accepted) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop();
    } else {
      _shake.forward(from: 0);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final character = event.character;
    if (character != null && RegExp(r'^\d$').hasMatch(character)) {
      _type(character);
    } else if (key == LogicalKeyboardKey.backspace) {
      _erase();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _submit();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Dialog(
        backgroundColor: Palette.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
            child: ListenableBuilder(
              listenable: Listenable.merge([_digits, _state]),
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Header(state: _state.value, prompt: widget.prompt),
                  const SizedBox(height: 22),
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(
                        math.sin(_shake.value * math.pi * 6) *
                            12 *
                            (1 - _shake.value),
                        0,
                      ),
                      child: child,
                    ),
                    child: _Dots(
                      count: _digits.value.length,
                      state: _state.value,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 20,
                    child: Text(
                      _message(_state.value),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _messageColor(_state.value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Keypad(
                    enabled: !_locked,
                    canSubmit: _digits.value.length >= 4,
                    onDigit: _type,
                    onErase: _erase,
                    onSubmit: _submit,
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _state.value == _PadState.checking
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      _state.value == _PadState.blocked ? 'Close' : 'Cancel',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _message(_PadState state) {
    final tries = widget.session.pinTriesLeft;
    return switch (state) {
      _PadState.typing => widget.session.isSimulated
          ? "The simulated card's PIN is 1234"
          : 'Three wrong PINs block the card',
      _PadState.checking => 'The card is checking it…',
      _PadState.accepted => 'PIN accepted',
      _PadState.wrong =>
        'Wrong PIN, $tries ${tries == 1 ? 'try' : 'tries'} left',
      _PadState.blocked => 'PIN blocked: only the municipality can unblock it',
      _PadState.failed => widget.session.error ?? 'The card did not answer',
    };
  }

  static Color _messageColor(_PadState state) => switch (state) {
        _PadState.accepted => Palette.success,
        _PadState.wrong ||
        _PadState.blocked ||
        _PadState.failed =>
          Palette.danger,
        _ => Palette.muted,
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.prompt});

  final _PadState state;
  final bool prompt;

  @override
  Widget build(BuildContext context) {
    final accepted = state == _PadState.accepted;
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Container(
            key: ValueKey(accepted),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (accepted ? Palette.success : Palette.accent)
                  .withValues(alpha: 0.12),
            ),
            child: Icon(
              accepted ? Icons.verified : Icons.lock_outline,
              color: accepted ? Palette.success : Palette.accent,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Enter your PIN',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Palette.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          prompt
              ? 'The card is read once it accepts it'
              : 'The card checks it itself',
          style: const TextStyle(fontSize: 13, color: Palette.muted),
        ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.state});

  final int count;
  final _PadState state;

  @override
  Widget build(BuildContext context) {
    final shown = math.max(4, count);
    final color = switch (state) {
      _PadState.accepted => Palette.success,
      _PadState.wrong || _PadState.blocked => Palette.danger,
      _ => Palette.accent,
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < shown; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.symmetric(horizontal: 7),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < count || state == _PadState.accepted
                  ? color
                  : Colors.transparent,
              border: Border.all(
                color: i < count ? color : Palette.line,
                width: 2,
              ),
            ),
          ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.canSubmit,
    required this.onDigit,
    required this.onErase,
    required this.onSubmit,
  });

  final bool enabled;
  final bool canSubmit;
  final void Function(String digit) onDigit;
  final VoidCallback onErase;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    Widget digit(String value) => _Key(
          onTap: enabled ? () => onDigit(value) : null,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Palette.ink,
            ),
          ),
        );
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [for (final value in row) digit(value)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Key(
              onTap: enabled ? onErase : null,
              tooltip: 'Erase',
              child: const Icon(Icons.backspace_outlined, color: Palette.muted),
            ),
            digit('0'),
            _Key(
              onTap: enabled && canSubmit ? onSubmit : null,
              filled: true,
              tooltip: 'Check the PIN',
              child: const Icon(Icons.arrow_forward, color: Colors.white),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.child,
    required this.onTap,
    this.filled = false,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool filled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final key = Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: filled
            ? (onTap == null ? Palette.line : Palette.accent)
            : Palette.paper,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 64, height: 64, child: Center(child: child)),
        ),
      ),
    );
    return tooltip == null ? key : Tooltip(message: tooltip, child: key);
  }
}
