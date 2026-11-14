import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/presentation/widgets/post_feed_card.dart';

import 'post_test_support.dart';

void main() {
  testWidgets('muestra datos clave de la tarjeta', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PostFeedCard(post: sampleCommunityPost())),
      ),
    );

    expect(find.text('Aviso de reunión'), findsOneWidget);
    expect(find.text('María Vecina'), findsOneWidget);
    expect(find.text('Junta Centro'), findsOneWidget);
    expect(find.text('Aviso comunitario'), findsOneWidget);
    expect(find.textContaining('Se invita a la reunión'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.byIcon(Icons.attach_file), findsOneWidget);
  });

  testWidgets('onOpen dispara al pulsar', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostFeedCard(
            post: sampleCommunityPost(),
            onOpen: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Aviso de reunión'));
    expect(tapped, isTrue);
  });

  testWidgets('municipal sin junta muestra municipio', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PostFeedCard(post: sampleMunicipalPost())),
      ),
    );

    expect(find.text('Chépica'), findsOneWidget);
    expect(find.text('Comunicado municipal'), findsOneWidget);
  });
}
