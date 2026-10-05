import 'dart:async';

import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_belgium/testing.dart';
import 'package:eid_ccid_example/src/apdu_log.dart';
import 'package:eid_ccid_example/src/hardware/hardware.dart';
import 'package:flutter/foundation.dart';

/// What the reader is doing.
enum ReaderActivity { idle, reading, awaitingPin, verifying }

/// The light on the reader.
enum ReaderLight { waiting, working, success, warning, failure }

/// The kinds of simulated card the demo offers.
enum SimulatedKind { valid, expired, tampered, cloned }

/// How a PIN check ended.
enum PinOutcome { accepted, wrong, blocked, failed }

/// The screen's state and actions, around a [BelgianEidWatcher].
class EidSession extends ChangeNotifier {
  /// Lists USB readers next to the simulated card when [useHardware].
  EidSession({this.useHardware = true}) {
    _watch(simulatedCard);
  }

  final bool useHardware;

  /// The simulated card; it keeps its PIN tries and place across reads.
  SimulatedBelgianCard simulatedCard = _newSimulatedCard();

  List<CardTerminal> _terminals = const [];
  late CardTerminal _terminal;
  BelgianEidWatcher? _watcher;
  StreamSubscription<BelgianEidEvent>? _subscription;
  bool _disposed = false;

  bool _autoRead = true;
  bool _askPin = false;
  Set<BelgianEidPart> _parts = {...BelgianEidPart.all};
  bool _acceptExpired = false;
  bool _verifySignatures = true;
  bool _verifyCard = true;

  /// Whether a card is read as soon as it goes in: `autoRead`.
  bool get autoRead => _autoRead;

  set autoRead(bool value) => _configure(() => _autoRead = value);

  /// Whether the PIN is asked for before the card is read: `pinPrompt`.
  bool get askPin => _askPin;

  set askPin(bool value) => _configure(() => _askPin = value);

  /// Whether reads include [part]: `parts`.
  bool reads(BelgianEidPart part) => _parts.contains(part);

  void setReads(BelgianEidPart part, {required bool value}) => _configure(
        () => _parts = value ? {..._parts, part} : _parts.difference({part}),
      );

  /// Whether a card past its last valid day is read: `acceptExpired`.
  bool get acceptExpired => _acceptExpired;

  set acceptExpired(bool value) => _configure(() => _acceptExpired = value);

  /// Whether a card read again takes its photo from the watcher's cache:
  /// `rememberPhotos`.
  bool get rememberPhotos => _rememberPhotos;

  set rememberPhotos(bool value) => _configure(() => _rememberPhotos = value);

  bool _rememberPhotos = true;

  /// Whether signatures are checked: `verifySignatures`.
  bool get verifySignatures => _verifySignatures;

  set verifySignatures(bool value) =>
      _configure(() => _verifySignatures = value);

  /// Whether the chip is asked to prove it is genuine: `verifyCard`.
  bool get verifyCard => _verifyCard;

  set verifyCard(bool value) => _configure(() => _verifyCard = value);

  void _configure(void Function() change) {
    change();
    final watcher = _watcher;
    if (watcher != null) _applyOptions(watcher);
    notifyListeners();
  }

  void _applyOptions(BelgianEidWatcher watcher) {
    watcher
      ..autoRead = _autoRead
      ..pinPrompt = _askPin ? _promptPin : null
      ..parts = _parts
      ..acceptExpired = _acceptExpired
      ..rememberPhotos = _rememberPhotos
      ..verifySignatures = _verifySignatures
      ..verifyCard = _verifyCard
      ..onProgress = _onProgress
      ..onApdu = _record;
  }

  /// Every USB reader at once, where there are USB readers.
  late final CardTerminal? _anyReader =
      useHardware && hasHardwareReaders ? anyHardwareTerminal() : null;

  /// The simulated reader, every reader at once, then each reader.
  List<String> get readers => [
        simulatedCard.name,
        if (_anyReader case final any?) any.name,
        for (final terminal in _terminals) terminal.name,
      ];

  /// The name of the reader watched.
  String get reader => _terminal.name;

  bool get isSimulated => identical(_terminal, simulatedCard);

  /// The kind of simulated card in use.
  SimulatedKind simulatedKind = SimulatedKind.valid;

  ReaderActivity activity = ReaderActivity.idle;

  bool get busy => activity != ReaderActivity.idle;

  /// Whether a card is in; the simulated one says so before the watcher.
  bool get cardPresent =>
      isSimulated ? simulatedCard.isInserted : _watcher?.hasCard ?? false;

  /// What went wrong last, shown until the next action.
  String? get error => _error;

  set error(String? value) {
    _error = value;
    _warning = false;
  }

  String? _error;

  /// Whether [error] is a warning rather than a failure: an expired card.
  bool get errorIsWarning => _warning && error != null;
  bool _warning = false;

  /// What was read from the card in the reader.
  BelgianEid? get eid => _watcher?.eid;

  /// Whether the photo read matches its signed hash, hashed once per read.
  bool get photoMatches {
    final eid = this.eid;
    if (eid == null) return false;
    if (!identical(eid, _hashedEid)) {
      _hashedEid = eid;
      _photoMatches = eid.photoMatches;
    }
    return _photoMatches;
  }

  BelgianEid? _hashedEid;
  bool _photoMatches = false;

  BelgianCardInfo? cardInfo;

  /// Reads that succeeded; a new one replays the card's animations.
  int readCount = 0;

  /// How long the last read took.
  Duration? readTime;

  /// Whether the card in the reader accepted the holder's PIN.
  bool get holderVerified => _watcher?.pinVerified ?? false;

  /// The PIN tries left, once a wrong PIN has said so.
  int? pinTriesLeft;

  /// Whether the watcher waits for the PIN, for the PIN pad to show.
  bool pinRequested = false;

  Completer<String?>? _pinEntry;
  Completer<PinOutcome>? _pinAnswer;

  /// The certificates once read; each is null when the card holds none.
  BelgianCertificates? certificates;

  /// The certificates that do not chain up to a trusted root, and why.
  Map<BelgianCertificate, BelgianSignatureException> certificateFailures =
      const {};

  /// Every command and answer, for the console alone.
  final apduLog = ApduLog();

  /// How far the current action got, for the reader's display alone.
  final progress = ReadProgress();

  /// Whether the last photo came from the card, not the cache.
  bool photoFromCard = false;

  // Whether the read under way selected the photo file.
  bool _photoSelected = false;

  final _readWatch = Stopwatch();

  ReaderLight get light {
    // Steady while the holder types: the card is not working.
    if (activity == ReaderActivity.awaitingPin) return ReaderLight.waiting;
    if (busy) return ReaderLight.working;
    if (error != null) {
      return errorIsWarning ? ReaderLight.warning : ReaderLight.failure;
    }
    if (!cardPresent) return ReaderLight.waiting;
    if (eid != null) return ReaderLight.success;
    return ReaderLight.waiting;
  }

  /// The photo on the card: the simulated one's, or a real card's once read.
  Uint8List? get printedPhoto => isSimulated ? specimenPhoto : eid?.photo;

  Future<void> refreshReaders() async {
    if (!useHardware) return;
    try {
      _terminals = await listHardwareTerminals();
    } on CardTransportException catch (e) {
      _terminals = const [];
      // Only the USB readers are concerned, not the simulated one.
      if (!isSimulated) error = e.message;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> selectReader(String? name) async {
    if (name == null || name == reader || busy) return;
    final any = _anyReader;
    final terminal = name == simulatedCard.name
        ? simulatedCard
        : any != null && name == any.name
            ? any
            : _terminals.firstWhere((t) => t.name == name);
    await _watch(terminal);
  }

  /// Inserts or removes the simulated card; the watcher polls for it.
  void toggleSimulatedCard() {
    if (busy && !pinRequested) return;
    if (simulatedCard.isInserted) {
      simulatedCard.remove();
    } else {
      simulatedCard.insert();
    }
    error = null;
    notifyListeners();
  }

  /// A fresh simulated card of [kind], PIN tries restored.
  Future<void> newSimulatedCard(
      [SimulatedKind kind = SimulatedKind.valid]) async {
    if (busy) return;
    simulatedCard = _newSimulatedCard(
      expired: kind == SimulatedKind.expired,
      tampered: kind == SimulatedKind.tampered,
      cloned: kind == SimulatedKind.cloned,
    );
    simulatedKind = kind;
    await _watch(simulatedCard);
  }

  // A real card's pace, command by command.
  static SimulatedBelgianCard _newSimulatedCard({
    bool expired = false,
    bool tampered = false,
    bool cloned = false,
  }) =>
      SimulatedBelgianCard(
        validFrom: expired ? DateTime.utc(2014, 3, 14) : null,
        validUntil: expired ? DateTime.utc(2024, 3, 13) : null,
        tamperedLastName: tampered ? 'Mallory' : null,
        cloned: cloned,
        latency: const Duration(milliseconds: 22),
      )..remove();

  /// Reads the card again, or for the first time when [autoRead] is off.
  Future<void> readCard() async {
    final watcher = _watcher;
    if (watcher == null || busy) return;
    _startReading();
    try {
      await watcher.read();
    } on Exception {
      // The watcher reports the failure as an event, handled below.
    }
  }

  Future<void> readCertificates() => _run(ReaderActivity.reading, () async {
        final read = await _currentReader().readCertificates();
        certificateFailures = await read.verify(
          BelgianSignatureVerifier(
            trustedRoots:
                isSimulated ? [SimulatedBelgianCard.rootCertificate] : null,
          ),
        );
        certificates = read;
      });

  /// Checks [pin], which the PIN pad only lets through as 4 to 12 digits.
  Future<PinOutcome> verifyPin(String pin) async {
    var outcome = PinOutcome.failed;
    await _run(ReaderActivity.verifying, () async {
      final watcher = _watcher ??
          (throw const CardTransportException('No card in the reader'));
      try {
        await watcher.verifyPin(pin);
        pinTriesLeft = null;
        outcome = PinOutcome.accepted;
      } on PinException catch (e) {
        pinTriesLeft = e.triesLeft;
        outcome = e.isBlocked ? PinOutcome.blocked : PinOutcome.wrong;
      }
    });
    return outcome;
  }

  /// Replaces PIN [current] with [replacement], both 4 to 12 digits.
  Future<PinOutcome> changePin(String current, String replacement) async {
    var outcome = PinOutcome.failed;
    await _run(ReaderActivity.verifying, () async {
      try {
        await _currentReader().changePin(current, replacement);
        pinTriesLeft = 3;
        outcome = PinOutcome.accepted;
      } on PinException catch (e) {
        pinTriesLeft = e.triesLeft;
        outcome = e.isBlocked ? PinOutcome.blocked : PinOutcome.wrong;
      }
    });
    return outcome;
  }

  /// Hands [pin] to the waiting watcher and tells how the card took it.
  Future<PinOutcome> answerPin(String pin) {
    final entry = _pinEntry;
    if (entry == null) return Future.value(PinOutcome.failed);
    _pinEntry = null;
    final answer = _pinAnswer = Completer<PinOutcome>();
    activity = ReaderActivity.verifying;
    notifyListeners();
    entry.complete(pin);
    return answer.future;
  }

  /// Tells the watcher waiting for the PIN that the holder gave up.
  void cancelPin() {
    final entry = _pinEntry;
    _pinEntry = null;
    if (!pinRequested) return;
    pinRequested = false;
    entry?.complete(null);
    if (!_disposed) notifyListeners();
  }

  // pinPrompt: opens the PIN pad; a second call means the PIN was wrong.
  Future<String?> _promptPin(int? triesLeft) {
    if (triesLeft != null) {
      pinTriesLeft = triesLeft;
      _answerPad(PinOutcome.wrong);
    }
    final entry = _pinEntry = Completer<String?>();
    pinRequested = true;
    activity = ReaderActivity.awaitingPin;
    if (!_disposed) notifyListeners();
    return entry.future;
  }

  void _answerPad(PinOutcome outcome) {
    final answer = _pinAnswer;
    _pinAnswer = null;
    answer?.complete(outcome);
  }

  Future<void> _watch(CardTerminal terminal) async {
    final previous = _watcher;
    _terminal = terminal;
    _watcher = null;
    cancelPin();
    // Nothing to wait for: see BelgianEidWatcher.dispose.
    unawaited(_subscription?.cancel());
    if (previous != null) await previous.dispose();
    if (_disposed) return;

    _forgetCard();
    error = null;
    activity = ReaderActivity.idle;
    final watcher = _watcher = BelgianEidWatcher(terminal);
    _applyOptions(watcher);
    _subscription = watcher.events.listen(
      _onEvent,
      onError: (Object e) {
        error = '$e';
        notifyListeners();
      },
    );
    watcher.start();
    notifyListeners();
  }

  Future<void> _onEvent(BelgianEidEvent event) async {
    switch (event) {
      case BelgianCardInserted():
        _forgetCard();
        error = null;
        if (_autoRead) _startReading();
      case BelgianPinVerified():
        pinTriesLeft = null;
        // Asked for before a read, which goes on now.
        if (pinRequested) {
          pinRequested = false;
          _answerPad(PinOutcome.accepted);
          _startReading();
        }
      case BelgianCardRead(:final reader):
        photoFromCard = _photoSelected;
        readTime = _readWatch.elapsed;
        readCount++;
        try {
          cardInfo = await reader.readCardInfo();
          // Read without spending a try.
          pinTriesLeft = await reader.pinTriesLeft();
        } on Exception {
          cardInfo = null;
        }
        activity = ReaderActivity.idle;
      case BelgianCardReadFailed(:final error):
        if (pinRequested || _pinAnswer != null) {
          pinRequested = false;
          _pinEntry = null;
          _answerPad(
            error is PinException ? PinOutcome.blocked : PinOutcome.failed,
          );
        }
        this.error = _describe(error);
        _warning = error is BelgianCardRejectedException &&
            error.reason == BelgianCardRejection.expired;
        activity = ReaderActivity.idle;
      case BelgianCardRemoved():
        error = null;
        cancelPin();
        _answerPad(PinOutcome.failed);
        _forgetCard();
        activity = ReaderActivity.idle;
    }
    if (!_disposed) notifyListeners();
  }

  // The watcher's onProgress: many times a read, so only the display hears.
  void _onProgress(double fraction) {
    if (!_disposed) progress._advance(fraction);
  }

  void _startReading() {
    activity = ReaderActivity.reading;
    progress._restart(fraction: 0);
    _photoSelected = false;
    error = null;
    _readWatch
      ..reset()
      ..start();
    if (!_disposed) notifyListeners();
  }

  BelgianEidReader _currentReader() =>
      _watcher?.reader ??
      (throw const CardTransportException('No card in the reader'));

  // The watcher's onApdu: once a command, so the session itself stays quiet.
  // photoFromCard is shown once the read ends, which notifies.
  void _record(ApduExchange exchange) {
    if (_disposed) return;
    apduLog.add(exchange);
    progress._add(exchange.responseDataLength);
    if (_isPhotoSelect(exchange)) _photoSelected = true;
  }

  static bool _isPhotoSelect(ApduExchange exchange) {
    final command = exchange.command;
    return command.length == 7 &&
        command[1] == 0xA4 &&
        command[5] == 0x40 &&
        command[6] == 0x35;
  }

  void _forgetCard() {
    cardInfo = null;
    certificates = null;
    certificateFailures = const {};
    pinTriesLeft = null;
    readTime = null;
  }

  Future<void> _run(
    ReaderActivity activity,
    Future<void> Function() action,
  ) async {
    if (busy) return;
    this.activity = activity;
    error = null;
    progress._restart(fraction: null);
    notifyListeners();
    try {
      await action();
    } on Exception catch (e) {
      error = _describe(e);
      _warning = false;
    } finally {
      this.activity = ReaderActivity.idle;
      if (!_disposed) notifyListeners();
    }
  }

  // Null for a PIN the holder chose not to give: nothing went wrong.
  static String? _describe(Exception error) => switch (error) {
        PinCancelledException() => null,
        // The package's own wording, as an application would show it.
        BelgianCardRejectedException() ||
        PinException() =>
          belgianErrorMessage(error, BelgianLanguage.en),
        CardTransportException(:final message, :final cause) =>
          cause == null ? message : '$message ($cause)',
        CardException() => '$error'.replaceFirst('CardException: ', ''),
        FormatException(:final message) =>
          'The card holds something unexpected: $message',
        _ => '$error',
      };

  @override
  void dispose() {
    _disposed = true;
    final entry = _pinEntry;
    _pinEntry = null;
    entry?.complete(null);
    _subscription?.cancel();
    _watcher?.dispose();
    apduLog.dispose();
    progress.dispose();
    super.dispose();
  }
}

/// What the current action has read so far, apart from the session: it
/// changes with every command and progress tick.
class ReadProgress extends ChangeNotifier {
  /// The bytes of data the card returned during the current action.
  int get bytesRead => _bytesRead;
  int _bytesRead = 0;

  /// Progress of the current read, 0 to 1, from `onProgress`.
  double? get fraction => _fraction;
  double? _fraction;

  void _restart({required double? fraction}) {
    _bytesRead = 0;
    _fraction = fraction;
    notifyListeners();
  }

  void _add(int bytes) {
    _bytesRead += bytes;
    notifyListeners();
  }

  void _advance(double fraction) {
    _fraction = fraction;
    notifyListeners();
  }
}
