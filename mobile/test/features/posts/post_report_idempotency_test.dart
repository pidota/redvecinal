import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/posts/application/post_report_coordinator.dart';
import 'package:red_vecinal/features/posts/application/post_report_form_controller.dart';
import 'package:red_vecinal/features/posts/application/post_report_outcome.dart';
import 'package:red_vecinal/features/posts/data/post_report_idempotency.dart';
import 'package:red_vecinal/features/posts/data/post_report_outcome_store.dart';
import 'package:red_vecinal/features/posts/presentation/post_report_screen.dart';

import '../auth/auth_test_support.dart';
import 'post_report_submit_controller_test.dart';
import 'post_report_submit_widget_test.dart';
import 'post_test_support.dart';

const kFixedUuid = '550e8400-e29b-41d4-a716-446655440000';

void main() {
  test('1. UUID v4 válida y minúsculas', () {
    final generated = generatePostReportUuidV4();
    expect(isPostReportUuidV4(generated), isTrue);
    expect(generated, generated.toLowerCase());
    expect(isPostReportUuidV4('550e8400-e29b-11d4-a716-446655440000'), isFalse);
    expect(isPostReportUuidV4(''), isFalse);
  });

  test('2. UUID distinta entre intentos nuevos', () async {
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    await confirmAndSubmit(c, 1);
    c.read(postReportFormControllerProvider(2).notifier).selectReason('spam');
    await confirmAndSubmit(c, 2);
    expect(gateway.reportPayloads, hasLength(2));
    expect(
      gateway.reportPayloads[0]['idempotencyKey'],
      isNot(gateway.reportPayloads[1]['idempotencyKey']),
    );
    expect(
      isPostReportUuidV4(gateway.reportPayloads[0]['idempotencyKey'] as String),
      isTrue,
    );
  });

  test('3. misma UUID en replay de recuperación', () async {
    final gateway =
        FakePostGateway()..reportFailureQueue.add(const ApiTimeoutFailure());
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    await confirmAndSubmit(c, 1);
    final firstKey = gateway.reportPayloads.single['idempotencyKey'];
    final recovered =
        await c
            .read(postReportFormControllerProvider(1).notifier)
            .recoverUncertain();
    expect(recovered, isA<PostReportSubmitSuccess>());
    expect(gateway.reportPostCallCount, 2);
    expect(gateway.reportPayloads.last['idempotencyKey'], firstKey);
    expect(gateway.reportPayloads.last['reason_code'], 'spam');
  });

  test('4 y 5. persistencia antes del POST y fallo bloquea', () async {
    final store = InMemoryPostReportOutcomeStore()..failWrites = true;
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    final blocked = await confirmAndSubmit(c, 1);
    expect(blocked, isA<PostReportSubmitBlocked>());
    expect(gateway.reportPostCallCount, 0);

    final okStore = InMemoryPostReportOutcomeStore();
    final okGateway = FakePostGateway(reportDelayMs: 40);
    final ok = submitContainer(gateway: okGateway, store: okStore);
    addTearDown(ok.dispose);
    ok.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    final pending = confirmAndSubmit(ok, 1);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(okStore.saveCount, greaterThanOrEqualTo(1));
    expect(okStore.lastSaved.single.status, PostReportOutcomeStatus.inFlight);
    expect(okStore.lastSaved.single.idempotencyKey, isNotNull);
    await pending;
  });

  test('6. payload original conservado', () async {
    final store = InMemoryPostReportOutcomeStore();
    final gateway = FakePostGateway(
      reportFailureByPostId: {1: const ApiTimeoutFailure()},
    );
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    final form = c.read(postReportFormControllerProvider(1).notifier);
    form.selectReason('inappropriate');
    form.setDetails('Vecino de la esquina');
    await confirmAndSubmit(c, 1);
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    final record = c.read(postReportCoordinatorProvider).recordFor(userId, 1);
    expect(record?.reasonCode, 'inappropriate');
    expect(record?.details, 'Vecino de la esquina');
    expect(record?.status, PostReportOutcomeStatus.uncertain);
  });

  test('7 y 8. replay tras timeout y 201 malformado', () async {
    final gateway =
        FakePostGateway()
          ..reportFailureQueue.addAll([
            const ApiTimeoutFailure(),
            const ApiUnexpectedFailure(),
          ]);
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitUncertain>());
    final key = gateway.reportPayloads.first['idempotencyKey'];
    expect(
      await c
          .read(postReportFormControllerProvider(1).notifier)
          .recoverUncertain(),
      isA<PostReportSubmitUncertain>(),
    );
    expect(
      await c
          .read(postReportFormControllerProvider(1).notifier)
          .recoverUncertain(),
      isA<PostReportSubmitSuccess>(),
    );
    expect(gateway.reportPostCallCount, 3);
    expect(
      gateway.reportPayloads.every((p) => p['idempotencyKey'] == key),
      isTrue,
    );
  });

  test(
    '9 y 10. replay tras reinicio simulado y no automático al hidratar',
    () async {
      final store = InMemoryPostReportOutcomeStore();
      final firstGateway = FakePostGateway(
        reportFailureByPostId: {1: const ApiNetworkFailure()},
      );
      final first = submitContainer(gateway: firstGateway, store: store);
      addTearDown(first.dispose);
      first
          .read(postReportFormControllerProvider(1).notifier)
          .selectReason('spam');
      await confirmAndSubmit(first, 1);
      final key = firstGateway.reportPayloads.single['idempotencyKey'];

      final secondGateway = FakePostGateway();
      final second = submitContainer(gateway: secondGateway, store: store);
      addTearDown(second.dispose);
      await second
          .read(postReportCoordinatorProvider.notifier)
          .ensureHydrated();
      expect(secondGateway.reportPostCallCount, 0);
      final recovered =
          await second
              .read(postReportFormControllerProvider(1).notifier)
              .recoverUncertain();
      expect(recovered, isA<PostReportSubmitSuccess>());
      expect(secondGateway.reportPayloads.single['idempotencyKey'], key);
    },
  );

  test('11. 201 confirma y limpia payload', () async {
    final store = InMemoryPostReportOutcomeStore();
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitSuccess>());
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    final record = c.read(postReportCoordinatorProvider).recordFor(userId, 1);
    expect(record?.status, PostReportOutcomeStatus.confirmed);
    expect(record?.reasonCode, isNull);
    expect(record?.details, isNull);
    expect(record?.reportId, 1);
  });

  test('12. 201 malformado queda uncertain recuperable', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {1: const ApiUnexpectedFailure()},
    );
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitUncertain>());
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    expect(
      c
          .read(postReportCoordinatorProvider)
          .recordFor(userId, 1)
          ?.isRecoverableUncertain,
      isTrue,
    );
  });

  test('13. 409 bloquea sin regenerar UUID ni otro POST', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {1: const ApiConflictFailure()},
    );
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitConflict>());
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    expect(
      c.read(postReportCoordinatorProvider).recordFor(userId, 1)?.status,
      PostReportOutcomeStatus.conflict,
    );
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitBlocked>());
    expect(gateway.reportPostCallCount, 1);
  });

  test('14. 422 no es éxito y permite un intento nuevo', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {
        1: const ApiValidationFailure({
          'reason_code': ['inválido'],
        }),
      },
    );
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    final result = await confirmAndSubmit(c, 1);
    expect(result, isA<PostReportSubmitFailure>());
    expect(result, isNot(isA<PostReportSubmitSuccess>()));
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    expect(c.read(postReportCoordinatorProvider).recordFor(userId, 1), isNull);
  });

  test('15. 401 403 404 no confirman', () async {
    Future<void> assertFailure(Object failure) async {
      final gateway = FakePostGateway(reportFailureByPostId: {1: failure});
      final c = submitContainer(gateway: gateway);
      addTearDown(c.dispose);
      c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
      expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitFailure>());
      final userId =
          (c.read(authControllerProvider) as AuthAuthenticated).user.id;
      expect(
        c.read(postReportCoordinatorProvider).recordFor(userId, 1)?.status,
        isNot(PostReportOutcomeStatus.confirmed),
      );
    }

    await assertFailure(const ApiSessionExpiredFailure());
    await assertFailure(const ApiForbiddenFailure());
    await assertFailure(const ApiNotFoundFailure());
  });

  test(
    '16 y 17. cambio de usuario y de sesión no muestran éxito ajeno',
    () async {
      final gateway = FakePostGateway(reportDelayMs: 60);
      final c = submitContainer(gateway: gateway);
      addTearDown(c.dispose);
      c.read(authControllerProvider.notifier).state = AuthAuthenticated(
        sampleAuthUser(),
      );
      c.read(postReportFormControllerProvider(2).notifier).selectReason('spam');
      final future = confirmAndSubmit(c, 2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      c.read(authControllerProvider.notifier).state = AuthAuthenticated(
        sampleAuthUser(id: 9, email: 'otro@test.com'),
      );
      expect(await future, isA<PostReportSubmitDiscarded>());
      expect(c.read(postReportCoordinatorProvider).recordFor(9, 2), isNull);
    },
  );

  test('18 y 19. doble tap y dos controladores un POST', () async {
    final gateway = FakePostGateway(reportDelayMs: 80);
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    final first = confirmAndSubmit(c, 1);
    final second = confirmAndSubmit(c, 1);
    await Future.wait([first, second]);
    expect(gateway.reportPostCallCount, 1);
  });

  test('20. hidratación concurrente no dispara POST', () async {
    final store = InMemoryPostReportOutcomeStore(
      seed: [
        const PostReportOutcomeRecord(
          userId: 1,
          postId: 5,
          status: PostReportOutcomeStatus.uncertain,
          generation: 3,
          recordedAtMillis: 1,
          idempotencyKey: kFixedUuid,
          reasonCode: 'spam',
        ),
      ],
    );
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    final coordinator = c.read(postReportCoordinatorProvider.notifier);
    await Future.wait([
      coordinator.ensureHydrated(),
      coordinator.ensureHydrated(),
    ]);
    expect(gateway.reportPostCallCount, 0);
    expect(
      c
          .read(postReportCoordinatorProvider)
          .recordFor(1, 5)
          ?.isRecoverableUncertain,
      isTrue,
    );
  });

  test(
    '21. legacy uncertain sin UUID no se recupera ni se reconvierte en POST',
    () async {
      final store = InMemoryPostReportOutcomeStore(
        seed: [
          const PostReportOutcomeRecord(
            userId: 1,
            postId: 5,
            status: PostReportOutcomeStatus.uncertain,
            generation: 3,
            recordedAtMillis: 1,
          ),
        ],
      );
      final gateway = FakePostGateway();
      final c = submitContainer(gateway: gateway, store: store);
      addTearDown(c.dispose);
      await c.read(postReportCoordinatorProvider.notifier).ensureHydrated();
      final recovered =
          await c
              .read(postReportFormControllerProvider(5).notifier)
              .recoverUncertain();
      expect(recovered, isA<PostReportSubmitBlocked>());
      expect(gateway.reportPostCallCount, 0);
      expect(
        c
            .read(postReportCoordinatorProvider)
            .recordFor(1, 5)
            ?.isLegacyUncertain,
        isTrue,
      );
    },
  );

  test('22. legacy confirmed sigue bloqueando', () async {
    final store = InMemoryPostReportOutcomeStore(
      seed: [
        const PostReportOutcomeRecord(
          userId: 1,
          postId: 5,
          status: PostReportOutcomeStatus.confirmed,
          generation: 3,
          recordedAtMillis: 1,
        ),
      ],
    );
    final c = submitContainer(gateway: FakePostGateway(), store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(5).notifier).selectReason('spam');
    final result = await confirmAndSubmit(c, 5);
    expect(result, isA<PostReportSubmitBlocked>());
  });

  test('23. datos corruptos bloquean fail-closed', () {
    expect(
      () => parsePostReportOutcomePayload('{no json'),
      throwsA(isA<PostReportOutcomeStoreException>()),
    );
    expect(
      () => parsePostReportOutcomePayload(
        '{"schema":2,"records":[{"bad":true}]}',
      ),
      throwsA(isA<PostReportOutcomeStoreException>()),
    );
  });

  test('24. limpieza de payload tras confirmación en disco', () async {
    final store = InMemoryPostReportOutcomeStore();
    final c = submitContainer(gateway: FakePostGateway(), store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    c.read(postReportFormControllerProvider(1).notifier).setDetails('privado');
    await confirmAndSubmit(c, 1);
    expect(store.lastSaved.single.details, isNull);
    expect(store.lastSaved.single.reasonCode, isNull);
    expect(store.lastSaved.single.idempotencyKey, isNull);
    expect(
      encodePostReportOutcomePayload(store.lastSaved),
      isNot(contains('privado')),
    );
  });

  test('25. web en memoria no comparte instancias', () async {
    final first = InMemoryPostReportOutcomeStore();
    await first.saveAll([
      const PostReportOutcomeRecord(
        userId: 1,
        postId: 1,
        status: PostReportOutcomeStatus.uncertain,
        generation: 1,
        recordedAtMillis: 1,
        idempotencyKey: kFixedUuid,
        reasonCode: 'spam',
      ),
    ]);
    final reloaded = InMemoryPostReportOutcomeStore();
    expect(await reloaded.loadAll(), isEmpty);
  });

  test('migración v1 conserva confirmed y no inventa UUID', () {
    final v1 = parsePostReportOutcomePayload(
      '{"records":[{"userId":1,"postId":2,"status":"confirmed","generation":1,"recordedAt":9}]}',
    );
    expect(v1, hasLength(1));
    expect(v1.single.status, PostReportOutcomeStatus.confirmed);
    expect(v1.single.idempotencyKey, isNull);
    expect(v1.single.hasRecoverableAttempt, isFalse);

    final uncertain = parsePostReportOutcomePayload(
      '{"records":[{"userId":1,"postId":2,"status":"uncertain","generation":1,"recordedAt":9}]}',
    );
    expect(uncertain.single.isLegacyUncertain, isTrue);
  });

  testWidgets('26. UI de recuperación a 320 px', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
      reportFailureByPostId: {1: const ApiTimeoutFailure()},
    );
    await openReportForm(tester, gateway);
    await confirmSend(tester);
    await tester.pumpAndSettle();
    expect(find.byType(PostReportScreen), findsOneWidget);
    expect(find.text('Comprobar envío'), findsOneWidget);
    expect(
      tester
          .getSize(find.widgetWithText(FilledButton, 'Comprobar envío'))
          .width,
      lessThanOrEqualTo(320),
    );
    expect(
      find.textContaining('No pudimos confirmar si tu denuncia fue recibida'),
      findsOneWidget,
    );
    expect(find.textContaining('mismo envío'), findsOneWidget);
    expect(find.textContaining('sin generar otra denuncia'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
