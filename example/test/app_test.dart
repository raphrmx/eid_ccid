import 'package:eid_ccid_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const EidDemoApp(useHardware: false));
    await tester.pumpAndSettle();
  }

  // Unmounts the app, which stops the watcher and its polling.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.text(label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    // Long enough for the watcher to notice a card going in or out.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  Future<void> toggle(WidgetTester tester, String option) async {
    final tile = find.text(option);
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text(digit)),
      );
      await tester.pump();
    }
    await tester.tap(find.byTooltip('Check the PIN'));
    await tester.pumpAndSettle();
  }

  testWidgets('reads the simulated card as it goes in, and checks its PIN',
      (tester) async {
    await open(tester, const Size(1440, 1000));
    expect(find.text('INSERT A CARD'), findsOneWidget);

    await tapButton(tester, 'Insert card');
    expect(find.text('CARD READ'), findsOneWidget);
    expect(find.text('Specimen'), findsOneWidget);
    expect(find.text('Rue de la Loi 16'), findsOneWidget);
    expect(find.text('Photo matches the signed hash'), findsOneWidget);

    await tapButton(tester, 'Check PIN');
    await typePin(tester, '0000');
    expect(find.text('Wrong PIN, 2 tries left'), findsOneWidget);
    await typePin(tester, '1234');
    expect(find.text('PIN accepted'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('PIN checked by the card'), findsOneWidget);

    // The PIN never reaches the log, and neither do the presence checks.
    expect(find.textContaining('(PIN not logged)'), findsNWidgets(2));
    expect(find.textContaining('241234'), findsNothing);
    expect(find.text('00CA000001'), findsNothing);

    await tapButton(tester, 'Remove card');
    expect(find.text('INSERT A CARD'), findsOneWidget);
    expect(find.text('Specimen'), findsNothing);

    await close(tester);
  });

  testWidgets('waits for the button when autoRead is off', (tester) async {
    await open(tester, const Size(1440, 1000));
    await toggle(tester, 'Read on insertion');

    await tapButton(tester, 'Insert card');
    expect(find.text('CARD READY'), findsOneWidget);
    expect(find.text('Specimen'), findsNothing);

    await tapButton(tester, 'Read card');
    expect(find.text('Specimen'), findsOneWidget);

    await close(tester);
  });

  testWidgets('reads in a narrow window', (tester) async {
    await open(tester, const Size(420, 900));
    await tapButton(tester, 'Insert card');
    expect(find.text('Specimen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('asks for the PIN before reading when pinPrompt is on',
      (tester) async {
    await open(tester, const Size(1440, 1000));
    await toggle(tester, 'Ask for the PIN first');

    await tapButton(tester, 'Insert card');
    expect(find.text('ENTER PIN'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Specimen'), findsNothing);

    await typePin(tester, '9999');
    expect(find.text('Wrong PIN, 2 tries left'), findsOneWidget);
    await typePin(tester, '1234');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('CARD READ'), findsOneWidget);
    expect(find.text('Specimen'), findsOneWidget);
    expect(find.text('PIN checked by the card'), findsOneWidget);

    await close(tester);
  });

  testWidgets('reads nothing when the holder gives up the PIN', (tester) async {
    await open(tester, const Size(1440, 1000));
    await toggle(tester, 'Ask for the PIN first');
    await tapButton(tester, 'Insert card');
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('CARD READY'), findsOneWidget);

    await close(tester);
  });

  testWidgets('turns down an expired card, and leaves parts out',
      (tester) async {
    await open(tester, const Size(1440, 1000));
    await toggle(tester, 'Read the national number');
    await toggle(tester, 'Read the address');

    await tapButton(tester, 'Expired');
    await tapButton(tester, 'Insert card');
    expect(
      find.text('CARD EXPIRED ON 13.03.2024'),
      findsOneWidget,
    );
    // A warning rather than a failure: amber, not red.
    final message = tester.widget<Text>(
      find.text('CARD EXPIRED ON 13.03.2024'),
    );
    expect(message.style?.color, const Color(0xFFFFA53A));

    await tapButton(tester, 'Remove card');
    await tapButton(tester, 'Valid');
    await tapButton(tester, 'Insert card');
    expect(find.text('Specimen'), findsOneWidget);
    expect(find.text('not read'), findsOneWidget);
    expect(find.text('National number not read'), findsOneWidget);
    expect(find.text('Rue de la Loi 16'), findsNothing);
    expect(find.text('Card valid until 13.03.2034'), findsOneWidget);
    expect(find.text('Holder is 18 or older'), findsOneWidget);

    await close(tester);
  });

  testWidgets('takes the photo of a card read again from the cache',
      (tester) async {
    await open(tester, const Size(1440, 1000));

    await tapButton(tester, 'Insert card');
    expect(find.text('Specimen'), findsOneWidget);
    expect(find.text('Photo from cache'), findsNothing);

    await tapButton(tester, 'Remove card');
    await tapButton(tester, 'Insert card');
    expect(find.text('Photo from cache'), findsOneWidget);

    // Turned off, the cache is emptied: the photo comes from the card again.
    await toggle(tester, 'Remember photos');
    await tapButton(tester, 'Remove card');
    await tapButton(tester, 'Insert card');
    expect(find.text('Specimen'), findsOneWidget);
    expect(find.text('Photo from cache'), findsNothing);

    await close(tester);
  });

  testWidgets('checks the signatures, and turns down a tampered card',
      (tester) async {
    await open(tester, const Size(1440, 1000));

    await tapButton(tester, 'Insert card');
    expect(find.text('Signed by the national register'), findsOneWidget);

    await tapButton(tester, 'Remove card');
    await tapButton(tester, 'Tampered');
    await tapButton(tester, 'Insert card');
    expect(
      find.text(
        "THE CARD'S DATA IS NOT SIGNED BY THE NATIONAL REGISTER",
      ),
      findsOneWidget,
    );

    await close(tester);
  });

  testWidgets('has the chip prove itself, and turns down a clone',
      (tester) async {
    await open(tester, const Size(1440, 1000));

    await tapButton(tester, 'Insert card');
    expect(find.text('Genuine chip: it proved its basic key'), findsOneWidget);
    expect(find.text('PIN: 3 tries left'), findsOneWidget);
    expect(find.text('Identity card'), findsOneWidget);

    await tapButton(tester, 'Remove card');
    await tapButton(tester, 'Cloned');
    await tapButton(tester, 'Insert card');
    expect(
      find.text('THE CHIP COULD NOT PROVE IT IS GENUINE'),
      findsOneWidget,
    );

    await close(tester);
  });

  testWidgets('changes the PIN', (tester) async {
    await open(tester, const Size(1440, 1000));
    await tapButton(tester, 'Insert card');
    await tapButton(tester, 'Change PIN');

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '1234');
    await tester.enterText(fields.at(1), '5678');
    await tester.enterText(fields.at(2), '5678');
    await tester.tap(find.text('Change'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('PIN changed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    // The old PIN is refused now, the new one accepted.
    await tapButton(tester, 'Check PIN');
    await typePin(tester, '1234');
    expect(find.text('Wrong PIN, 2 tries left'), findsOneWidget);
    await typePin(tester, '5678');
    expect(find.text('PIN accepted'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await close(tester);
  });

  testWidgets('reads the certificates and chains them up', (tester) async {
    await open(tester, const Size(1440, 1000));
    await tapButton(tester, 'Insert card');
    await tapButton(tester, 'Certificates');
    await tapButton(tester, 'Read the certificates');

    expect(
        find.text('5 on this card, all from a trusted root'), findsOneWidget);
    expect(
      find.text('Alice Marie Specimen (Authentication)'),
      findsOneWidget,
    );
    expect(find.text('Chains up to a trusted root'), findsNWidgets(4));

    await close(tester);
  });
}
