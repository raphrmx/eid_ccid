import 'package:eid_ccid_example/src/eid_session.dart';
import 'package:eid_ccid_example/src/palette.dart';
import 'package:eid_ccid_example/src/widgets/apdu_console.dart';
import 'package:eid_ccid_example/src/widgets/panels.dart';
import 'package:eid_ccid_example/src/widgets/pin_pad.dart';
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
            final reader = ReaderPanel(session: _session);
            final options = OptionsPanel(session: _session);
            final console = ApduConsole(
              session: _session,
              height: wide ? 300 : 220,
            );
            final result = ResultView(session: _session, wide: wide);

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
