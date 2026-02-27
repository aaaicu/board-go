import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/client/gamenode/hand_widget.dart';

void main() {
  group('HandWidget', () {
    const testHand = ['A-spades', '7-hearts', 'K-clubs'];

    // -----------------------------------------------------------------------
    // Rendering
    // -----------------------------------------------------------------------

    testWidgets('renders correct number of cards', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandWidget(
              hand: testHand,
              allowedTypes: const {'PLAY_CARD'},
            ),
          ),
        ),
      );

      // Each card is rendered as a Card widget.
      expect(find.byType(Card), findsNWidgets(testHand.length));
    });

    testWidgets('shows card rank text for each card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandWidget(
              hand: testHand,
              allowedTypes: const {'PLAY_CARD'},
            ),
          ),
        ),
      );

      // Check rank labels are present.
      expect(find.text('A'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('K'), findsOneWidget);
    });

    testWidgets('shows empty-hand message when hand is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HandWidget(
              hand: [],
              allowedTypes: {},
            ),
          ),
        ),
      );

      expect(find.text('No cards in hand'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Interaction — onCardTap callback
    // -----------------------------------------------------------------------

    testWidgets('tapping a card calls onCardTap with the correct cardId',
        (tester) async {
      String? tappedCard;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandWidget(
              hand: testHand,
              allowedTypes: const {'PLAY_CARD'},
              onCardTap: (id) => tappedCard = id,
            ),
          ),
        ),
      );

      // Tap the first card ('A-spades').
      await tester.tap(find.text('A').first);
      await tester.pump();

      expect(tappedCard, equals('A-spades'));
    });

    testWidgets('tapping a card does NOT fire when it is not my turn',
        (tester) async {
      var tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandWidget(
              hand: testHand,
              allowedTypes: const {}, // not my turn
              onCardTap: (_) => tapCount++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('A').first);
      await tester.pump();

      expect(tapCount, equals(0));
    });

    // -----------------------------------------------------------------------
    // Opacity — not-my-turn cards should be semi-transparent
    // -----------------------------------------------------------------------

    testWidgets('cards are semi-transparent when it is not my turn',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HandWidget(
              hand: ['A-spades'],
              allowedTypes: {}, // not my turn
            ),
          ),
        ),
      );

      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, lessThan(1.0));
    });

    testWidgets('cards are fully opaque when it IS my turn', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HandWidget(
              hand: ['A-spades'],
              allowedTypes: {'PLAY_CARD'},
            ),
          ),
        ),
      );

      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, equals(1.0));
    });
  });
}
