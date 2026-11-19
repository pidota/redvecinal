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
import 'package:red_vecinal/features/posts/data/post_report_validation.dart';
import '../auth/auth_test_support.dart';
import 'post_report_submit_controller_test.dart';
import 'post_report_submit_widget_test.dart';
import 'post_test_support.dart';

void main() {
  test('clasificación 422/429 fail-closed', () {
    expect(
      isPostReportPreCreateRejection(
        const ApiValidationFailure({
          'reason_code': ['inválido'],
        }),
      ),
      isTrue,
    );
    expect(
      isPostReportPreCreateRejection(
        const ApiValidationFailure({
          'details': ['demasiado largo'],
        }),
      ),
      isTrue,
    );
    expect(
      isPostReportPreCreateRejection(
        const ApiValidationFailure({
          kPostReportIdempotencyHeader: ['Clave de idempotencia inválida.'],
        }, 'No se pudo enviar el reporte de forma segura.'),
      ),
      isTrue,
    );
    expect(
      isPostReportPreCreateRejection(
        const ApiValidationFailure(
          {},
          'La cabecera Idempotency-Key debe ser un UUID v4 válido.',
        ),
      ),
      isTrue,
    );
    expect(
      isPostReportPreCreateRejection(const ApiValidationFailure({}, 'Error')),
      isFalse,
    );
    expect(
      isPostReportPreCreateRejection(const ApiValidationFailure({})),
      isFalse,
    );
    expect(
      isPostReportPreCreateRejection(
        const ApiValidationFailure({
          'proxy': ['blocked'],
        }),
      ),
      isFalse,
    );
    expect(
      isPostReportPreCreateRejection(const ApiRateLimitedFailure()),
      isFalse,
    );
    expect(isPostReportOutcomeUncertain(const ApiRateLimitedFailure()), isTrue);
    expect(isPostReportPreCreateRejection(const ApiForbiddenFailure()), isTrue);
  });

  test('1. sesión cambia antes del POST y libera inFlight', () async {
    final store =
        InMemoryPostReportOutcomeStore()
          ..writeDelay = const Duration(milliseconds: 80);
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    final future = confirmAndSubmit(c, 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 9, email: 'otro@test.com'),
    );
    expect(await future, isA<PostReportSubmitDiscarded>());
    expect(gateway.reportPostCallCount, 0);
    expect(c.read(postReportCoordinatorProvider).recordFor(1, 1), isNull);
    expect(c.read(postReportCoordinatorProvider).recordFor(9, 1), isNull);
  });

  test('2. sesión cambia durante el POST y conserva UUID', () async {
    final gateway = FakePostGateway(reportDelayMs: 80);
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    final future = confirmAndSubmit(c, 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(gateway.reportPostCallCount, 1);
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 9, email: 'otro@test.com'),
    );
    expect(await future, isA<PostReportSubmitDiscarded>());
    final original = c.read(postReportCoordinatorProvider).recordFor(1, 1);
    expect(original?.status, PostReportOutcomeStatus.confirmed);
    expect(c.read(postReportCoordinatorProvider).recordFor(9, 1), isNull);
    expect(gateway.reportPayloads, isNotEmpty);
    expect(gateway.reportPayloads.single['idempotencyKey'], isNotNull);
  });

  test('3. sesión cambia después de la respuesta', () async {
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitSuccess>());
    final keyBefore =
        c.read(postReportCoordinatorProvider).recordFor(1, 1)?.idempotencyKey;
    expect(keyBefore, isNull);
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 9, email: 'otro@test.com'),
    );
    expect(
      c.read(postReportCoordinatorProvider).recordFor(1, 1)?.status,
      PostReportOutcomeStatus.confirmed,
    );
    expect(c.read(postReportCoordinatorProvider).recordFor(9, 1), isNull);
  });

  test('4. POST posiblemente despachado conserva UUID', () async {
    final gateway = FakePostGateway(
      reportDelayMs: 40,
      reportFailureByPostId: {1: const ApiTimeoutFailure()},
    );
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    final future = confirmAndSubmit(c, 1);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 9, email: 'otro@test.com'),
    );
    expect(await future, isA<PostReportSubmitUncertain>());
    final record = c.read(postReportCoordinatorProvider).recordFor(1, 1);
    expect(record?.isRecoverableUncertain, isTrue);
    expect(
      record?.idempotencyKey,
      gateway.reportPayloads.single['idempotencyKey'],
    );
    expect(c.read(postReportCoordinatorProvider).recordFor(9, 1), isNull);
  });

  test('5. 422 de reason_code libera', () async {
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
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitFailure>());
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    expect(c.read(postReportCoordinatorProvider).recordFor(userId, 1), isNull);
  });

  test('6. 422 de details libera', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {
        1: const ApiValidationFailure({
          'details': ['demasiado largo'],
        }),
      },
    );
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitFailure>());
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    expect(c.read(postReportCoordinatorProvider).recordFor(userId, 1), isNull);
  });

  test('7. 422 de clave inválida reconocible libera', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {
        1: const ApiValidationFailure(
          {},
          'La cabecera Idempotency-Key debe ser un UUID v4 válido.',
        ),
      },
    );
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitFailure>());
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    expect(c.read(postReportCoordinatorProvider).recordFor(userId, 1), isNull);
  });

  test('8 y 9. 422 genérico o sin cuerpo queda uncertain', () async {
    Future<void> assertUncertain(ApiFailure failure) async {
      final gateway = FakePostGateway(reportFailureByPostId: {1: failure});
      final c = submitContainer(gateway: gateway);
      addTearDown(c.dispose);
      c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
      expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitUncertain>());
      final userId =
          (c.read(authControllerProvider) as AuthAuthenticated).user.id;
      final record = c.read(postReportCoordinatorProvider).recordFor(userId, 1);
      expect(record?.isRecoverableUncertain, isTrue);
      expect(gateway.reportPostCallCount, 1);
    }

    await assertUncertain(const ApiValidationFailure({}, 'Unprocessable'));
    await assertUncertain(const ApiValidationFailure({}));
  });

  test('10. 429 queda uncertain con la misma UUID', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {1: const ApiRateLimitedFailure()},
    );
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitUncertain>());
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    final record = c.read(postReportCoordinatorProvider).recordFor(userId, 1);
    expect(record?.isRecoverableUncertain, isTrue);
    expect(
      record?.idempotencyKey,
      gateway.reportPayloads.single['idempotencyKey'],
    );
  });

  test('11. proxy ambiguo queda uncertain', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {
        1: const ApiValidationFailure({
          'cf-mitigated': ['challenge'],
        }),
      },
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

  test('12. 201 y persistencia confirmed fallida conserva payload', () async {
    final store = InMemoryPostReportOutcomeStore()..failOnSaveNumber = 2;
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    c.read(postReportFormControllerProvider(1).notifier).setDetails('privado');
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitUncertain>());
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    final record = c.read(postReportCoordinatorProvider).recordFor(userId, 1);
    expect(record?.isRecoverableUncertain, isTrue);
    expect(record?.details, 'privado');
    expect(record?.idempotencyKey, isNotNull);
    expect(record?.status, isNot(PostReportOutcomeStatus.confirmed));
  });

  test('13. fallo al limpiar payload no pierde confirmed', () async {
    final store = InMemoryPostReportOutcomeStore()..failOnSaveNumber = 3;
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    c.read(postReportFormControllerProvider(1).notifier).setDetails('privado');
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitSuccess>());
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    final record = c.read(postReportCoordinatorProvider).recordFor(userId, 1);
    expect(record?.status, PostReportOutcomeStatus.confirmed);
    expect(record?.idempotencyKey, isNotNull);
    expect(record?.details, 'privado');
  });

  test('14. escritura tardía no degrada confirmed', () async {
    final store = InMemoryPostReportOutcomeStore();
    final c = submitContainer(gateway: FakePostGateway(), store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitSuccess>());
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    store.failWrites = true;
    await c
        .read(postReportCoordinatorProvider.notifier)
        .markUncertain(userId: userId, postId: 1, generation: 99);
    final record = c.read(postReportCoordinatorProvider).recordFor(userId, 1);
    expect(record?.status, PostReportOutcomeStatus.confirmed);
    expect(record?.reasonCode, isNull);
  });

  test('15 y 16. reinicio tras persistencia fallida y misma UUID', () async {
    final store = InMemoryPostReportOutcomeStore()..failOnSaveNumber = 2;
    final firstGateway = FakePostGateway();
    final first = submitContainer(gateway: firstGateway, store: store);
    addTearDown(first.dispose);
    first
        .read(postReportFormControllerProvider(1).notifier)
        .selectReason('spam');
    await confirmAndSubmit(first, 1);
    final key = firstGateway.reportPayloads.single['idempotencyKey'];

    store.failOnSaveNumber = null;
    store.failWrites = false;
    final secondGateway = FakePostGateway();
    final second = submitContainer(gateway: secondGateway, store: store);
    addTearDown(second.dispose);
    await second.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    expect(secondGateway.reportPostCallCount, 0);
    final recovered =
        await second
            .read(postReportFormControllerProvider(1).notifier)
            .recoverUncertain();
    expect(recovered, isA<PostReportSubmitSuccess>());
    expect(secondGateway.reportPayloads.single['idempotencyKey'], key);
  });

  test('17. uncertain no regenera UUID', () async {
    final gateway =
        FakePostGateway()..reportFailureQueue.add(const ApiTimeoutFailure());
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    await confirmAndSubmit(c, 1);
    final firstKey = gateway.reportPayloads.single['idempotencyKey'];
    await c
        .read(postReportFormControllerProvider(1).notifier)
        .recoverUncertain();
    expect(gateway.reportPayloads.last['idempotencyKey'], firstKey);
    expect(gateway.reportPayloads.last['idempotencyKey'], isNot(isEmpty));
  });

  test('18. registros v1 legacy no se recuperan', () async {
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
  });

  test('19. doble tap y dos controladores un POST', () async {
    final gateway = FakePostGateway(reportDelayMs: 80);
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    final first = confirmAndSubmit(c, 1);
    final second = confirmAndSubmit(c, 1);
    await Future.wait([first, second]);
    expect(gateway.reportPostCallCount, 1);
  });

  testWidgets('20 y 21. widget mensaje corregido a 320 px', (tester) async {
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
    expect(
      find.textContaining('mismo envío de forma segura para evitar duplicados'),
      findsOneWidget,
    );
    expect(find.textContaining('sin generar otra denuncia'), findsNothing);
    expect(find.text('Comprobar envío'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('22. cambio de usuario no filtra datos ajenos', () async {
    final store = InMemoryPostReportOutcomeStore();
    final c = submitContainer(gateway: FakePostGateway(), store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    c.read(postReportFormControllerProvider(1).notifier).setDetails('privado');
    await confirmAndSubmit(c, 1);
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 9, email: 'otro@test.com'),
    );
    expect(c.read(postReportCoordinatorProvider).recordFor(9, 1), isNull);
    expect(
      c.read(postReportCoordinatorProvider).recordFor(1, 1)?.status,
      PostReportOutcomeStatus.confirmed,
    );
    expect(
      encodePostReportOutcomePayload(
        c.read(postReportCoordinatorProvider).recordFor(9, 1) == null
            ? const []
            : [c.read(postReportCoordinatorProvider).recordFor(9, 1)!],
      ),
      isNot(contains('privado')),
    );
  });
}
