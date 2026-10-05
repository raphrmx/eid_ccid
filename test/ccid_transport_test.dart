import 'package:ccid/ccid.dart';
import 'package:eid/eid.dart';
import 'package:eid_ccid/eid_ccid.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A card answering each command with the next scripted hex response.
class ScriptedCard extends CcidCard {
  ScriptedCard(this.responses) : super('Test reader 0');

  final List<Object?> responses;
  final List<String> sent = [];

  @override
  Future<String?> transceive(String capdu) async {
    sent.add(capdu);
    final response = responses.removeAt(0);
    if (response is Exception) throw response;
    return response as String?;
  }
}

void main() {
  test('sends the command as hex and returns the response as bytes', () async {
    final card = ScriptedCard(['0102039000']);
    final response = await CcidTransport(card)
        .transmit(Uint8List.fromList([0, 0xB0, 0, 0, 3]));
    expect(card.sent, ['00B0000003']);
    expect(response, [1, 2, 3, 0x90, 0x00]);
  });

  test('accepts lower case hex', () async {
    final response =
        await CcidTransport(ScriptedCard(['6a82'])).transmit(Uint8List(4));
    expect(response, [0x6A, 0x82]);
  });

  test('works under a CardChannel', () async {
    final card = ScriptedCard(['6C02', 'ABCD9000']);
    final channel = CardChannel(CcidTransport(card));
    final data = await channel.readBinary(offset: 0, length: 248);
    expect(data, [0xAB, 0xCD]);
    expect(card.sent, ['00B00000F8', '00B0000002']);
  });

  test('turns a platform failure into a CardTransportException', () async {
    final card = ScriptedCard([PlatformException(code: 'removed')]);
    await expectLater(
      CcidTransport(card).transmit(Uint8List(4)),
      throwsA(
        isA<CardTransportException>()
            .having((e) => e.cause, 'cause', isA<PlatformException>()),
      ),
    );
  });

  test('refuses an empty or malformed response', () async {
    await expectLater(
      CcidTransport(ScriptedCard([null])).transmit(Uint8List(4)),
      throwsA(isA<CardTransportException>()),
    );
    await expectLater(
      CcidTransport(ScriptedCard(['90Z0'])).transmit(Uint8List(4)),
      throwsA(isA<CardTransportException>()),
    );
    await expectLater(
      CcidTransport(ScriptedCard(['900'])).transmit(Uint8List(4)),
      throwsA(isA<CardTransportException>()),
    );
  });

  test('is a connection a watcher can release', () {
    final card = ScriptedCard([]);
    final CardConnection connection = CcidTransport(card);
    expect(connection, isA<CardTransport>());
    expect(const CcidTerminal('Reader 0'), const CcidTerminal('Reader 0'));
  });
}
