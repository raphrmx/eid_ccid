import 'dart:typed_data';

import 'package:ccid/ccid.dart';
import 'package:dart_pcsc/dart_pcsc.dart' as pcsc;
import 'package:eid/eid.dart';

/// A connection to the card in a USB or PC/SC card reader.
///
/// See the `ccid` package for per-platform setup.
final class CcidTransport implements CardConnection {
  /// A transport over a [card] already connected.
  CcidTransport(this.card);

  /// The card, as the `ccid` plugin exposes it.
  final CcidCard card;

  /// The names of the readers plugged in, empty when there is none.
  ///
  /// Throws a [CardTransportException] when they cannot be listed.
  static Future<List<String>> listReaders() async {
    try {
      return await Ccid().listReaders();
    } on pcsc.CardException catch (error) {
      if (_noReader.contains(error.errorCode)) return const [];
      throw CardTransportException('Could not list the readers', cause: error);
    } on Object catch (error) {
      throw CardTransportException('Could not list the readers', cause: error);
    }
  }

  // PC/SC says there is no reader, or Windows has stopped the smart card
  // service because none was ever plugged in.
  static const _noReader = {
    0x8010002E, // SCARD_E_NO_READERS_AVAILABLE
    0x8010001D, // SCARD_E_NO_SERVICE
    0x8010001E, // SCARD_E_SERVICE_STOPPED
  };

  /// Connects to the card in [reader], a name from [listReaders].
  ///
  /// Throws a [CardTransportException] when the reader is empty or gone.
  static Future<CcidTransport> connect(String reader) async {
    try {
      return CcidTransport(await Ccid().connect(reader));
    } on Object catch (error) {
      throw CardTransportException('Could not connect to $reader',
          cause: error);
    }
  }

  /// The name of the reader the card is in.
  String get reader => card.reader;

  @override
  Future<Uint8List> transmit(Uint8List command) async {
    final String? response;
    try {
      response = await card.transceive(hexString(command));
    } on Object catch (error) {
      // The plugin also throws StateError, once the card is disconnected.
      throw CardTransportException('The card did not answer', cause: error);
    }
    final bytes = _decodeHex(response ?? '');
    if (bytes.length < 2) {
      throw const CardTransportException('The reader returned no status word');
    }
    return bytes;
  }

  /// Releases the card. The transport cannot be used afterwards.
  @override
  Future<void> disconnect() async {
    try {
      await card.disconnect();
    } on Object catch (error) {
      throw CardTransportException('Could not release the card', cause: error);
    }
  }
}

/// A USB or PC/SC card reader, to watch with a [CardWatcher].
final class CcidTerminal implements CardTerminal {
  /// The reader [name], a name from [CcidTransport.listReaders].
  const CcidTerminal(this.name);

  /// The readers plugged in.
  static Future<List<CcidTerminal>> list() async => [
        for (final name in await CcidTransport.listReaders())
          CcidTerminal(name),
      ];

  /// Every reader at once, readers plugged in later included.
  static AnyCardTerminal any() => AnyCardTerminal(list, name: 'Any reader');

  @override
  final String name;

  @override
  Future<CardConnection> connect() => CcidTransport.connect(name);

  @override
  bool operator ==(Object other) => other is CcidTerminal && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'CcidTerminal($name)';
}

final _hex = RegExp(r'^(?:[0-9a-fA-F]{2})*$');

Uint8List _decodeHex(String hex) {
  if (!_hex.hasMatch(hex)) {
    throw const CardTransportException('The reader returned malformed data');
  }
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return bytes;
}
