import 'package:eid_ccid_example/src/eid_session.dart';
import 'package:eid_ccid_example/src/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks for the current PIN and a new one twice, then changes it.
Future<void> showChangePinDialog(BuildContext context, EidSession session) =>
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x661D1712),
      builder: (context) => ChangePinDialog(session: session),
    );

class ChangePinDialog extends StatefulWidget {
  const ChangePinDialog({super.key, required this.session});

  final EidSession session;

  @override
  State<ChangePinDialog> createState() => _ChangePinDialogState();
}

// No setState: the fields and the message notifier hold the state.
class _ChangePinDialogState extends State<ChangePinDialog> {
  final _current = TextEditingController();
  final _replacement = TextEditingController();
  final _confirmation = TextEditingController();
  final _message = ValueNotifier<(String, bool)?>(null);
  final _checking = ValueNotifier(false);

  static final _digits = RegExp(r'^\d{4,12}$');

  @override
  void dispose() {
    _current.dispose();
    _replacement.dispose();
    _confirmation.dispose();
    _message.dispose();
    _checking.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_digits.hasMatch(_current.text) ||
        !_digits.hasMatch(_replacement.text)) {
      _message.value = ('A PIN is 4 to 12 digits', false);
      return;
    }
    if (_replacement.text != _confirmation.text) {
      _message.value = ('The new PINs differ', false);
      return;
    }
    _checking.value = true;
    final outcome = await widget.session.changePin(
      _current.text,
      _replacement.text,
    );
    if (!mounted) return;
    _checking.value = false;
    final tries = widget.session.pinTriesLeft;
    _message.value = switch (outcome) {
      PinOutcome.accepted => ('PIN changed', true),
      PinOutcome.wrong => (
          'Wrong current PIN, $tries ${tries == 1 ? 'try' : 'tries'} left',
          false
        ),
      PinOutcome.blocked => (
          'PIN blocked: only the municipality can unblock it',
          false
        ),
      PinOutcome.failed => (
          widget.session.error ?? 'The card did not answer',
          false
        ),
    };
    if (outcome == PinOutcome.accepted) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop();
    }
  }

  Widget _field(TextEditingController controller, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Palette.white,
      surfaceTintColor: Colors.transparent,
      title: const Text('Change the PIN'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.session.isSimulated
                  ? "The simulated card's PIN is 1234"
                  : 'A wrong current PIN costs a try',
              style: const TextStyle(color: Palette.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _field(_current, 'Current PIN'),
            _field(_replacement, 'New PIN'),
            _field(_confirmation, 'New PIN again'),
            ValueListenableBuilder(
              valueListenable: _message,
              builder: (context, message, _) => message == null
                  ? const SizedBox.shrink()
                  : Text(
                      message.$1,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: message.$2 ? Palette.success : Palette.danger,
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder(
          valueListenable: _checking,
          builder: (context, checking, _) => FilledButton(
            onPressed: checking ? null : _submit,
            child: const Text('Change'),
          ),
        ),
      ],
    );
  }
}
