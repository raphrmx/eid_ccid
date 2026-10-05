import 'package:eid_belgium/eid_belgium.dart';

/// Whether this platform can reach USB readers.
const hasHardwareReaders = false;

/// No reader can be reached from a browser.
Future<List<CardTerminal>> listHardwareTerminals() async => const [];

/// No reader can be reached from a browser.
CardTerminal anyHardwareTerminal() =>
    throw UnsupportedError('No card reader from a browser');
