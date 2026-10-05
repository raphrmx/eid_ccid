import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_ccid/eid_ccid.dart';

/// Whether this platform can reach USB readers.
const hasHardwareReaders = true;

/// The USB and PC/SC readers plugged in.
Future<List<CardTerminal>> listHardwareTerminals() => CcidTerminal.list();

/// Every reader at once, those plugged in later included.
CardTerminal anyHardwareTerminal() => CcidTerminal.any();
