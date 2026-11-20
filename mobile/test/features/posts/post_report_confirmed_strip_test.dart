import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/posts/application/post_report_coordinator.dart';
import 'package:red_vecinal/features/posts/application/post_report_form_controller.dart';
import 'package:red_vecinal/features/posts/application/post_report_outcome.dart';
import 'package:red_vecinal/features/posts/data/post_report_outcome_store.dart';

import '../auth/auth_test_support.dart';
import 'post_report_submit_controller_test.dart';
import 'post_test_support.dart';

const _kUuid = '550e8400-e29b-41d4-a716-446655440000';

PostReportOutcomeRecord _confirmedWithPayload({
  int userId = 1,
  int postId = 1,
  int generation = 4,
  int? reportId = 88,
  String details = 'privado',
}) {
  return PostReportOutcomeRecord(
    userId: userId,
    postId: postId,
    status: PostReportOutcomeStatus.confirmed,
    generation: generation,
    recordedAtMillis: 10,
    idempotencyKey: _kUuid,
    reasonCode: 'spam',
    details: details,
    reportId: reportId,
  );
}

void main() {
  test('1-9. hidratación limpia payload confirmed sin POST ni UUID nueva', () async {
    final store = InMemoryPostReportOutcomeStore()..failOnSaveNumber = 3;
    final firstGateway = FakePostGateway();
    final first = submitContainer(gateway: firstGateway, store: store);
    addTearDown(first.dispose);
    first.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    first.read(postReportFormControllerProvider(1).notifier).setDetails('privado');
    expect(await confirmAndSubmit(first, 1), isA<PostReportSubmitSuccess>());
    final userId =
        (first.read(authControllerProvider) as AuthAuthenticated).user.id;
    final leftover = first
        .read(postReportCoordinatorProvider)
        .recordFor(userId, 1);
    expect(leftover?.status, PostReportOutcomeStatus.confirmed);
    expect(leftover?.details, 'privado');
    expect(leftover?.hasRecoverableAttempt, isTrue);
    final originalKey = leftover?.idempotencyKey;
    final reportId = leftover?.reportId;
    expect(originalKey, isNotNull);

    store.failOnSaveNumber = null;
    store.failWrites = false;
    final secondGateway = FakePostGateway();
    final second = submitContainer(gateway: secondGateway, store: store);
    addTearDown(second.dispose);
    await second.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    final cleaned = second
        .read(postReportCoordinatorProvider)
        .recordFor(userId, 1);
    expect(cleaned?.status, PostReportOutcomeStatus.confirmed);
    expect(cleaned?.reportId, reportId);
    expect(cleaned?.idempotencyKey, isNull);
    expect(cleaned?.reasonCode, isNull);
    expect(cleaned?.details, isNull);
    expect(cleaned?.hasRecoverableAttempt, isFalse);
    expect(secondGateway.reportPostCallCount, 0);
    expect(secondGateway.reportPayloads, isEmpty);
    expect(
      second
          .read(postReportCoordinatorProvider.notifier)
          .tryBeginConfirming(userId: userId, postId: 1),
      isFalse,
    );
    expect(
      await second
          .read(postReportFormControllerProvider(1).notifier)
          .recoverUncertain(),
      isA<PostReportSubmitBlocked>(),
    );
    expect(secondGateway.reportPostCallCount, 0);
    expect(
      encodePostReportOutcomePayload(store.snapshot),
      isNot(contains('privado')),
    );
  });

  test('10-12. fallo reiterado y reintento de hidratación', () async {
    final store = InMemoryPostReportOutcomeStore(
      seed: [_confirmedWithPayload()],
    )..failWrites = true;
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    await c.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    final first = c.read(postReportCoordinatorProvider).recordFor(1, 1);
    expect(first?.status, PostReportOutcomeStatus.confirmed);
    expect(first?.details, 'privado');
    expect(first?.reportId, 88);
    expect(gateway.reportPostCallCount, 0);

    await c.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    expect(
      c.read(postReportCoordinatorProvider).recordFor(1, 1)?.details,
      'privado',
    );

    store.failWrites = false;
    await c.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    final recovered = c.read(postReportCoordinatorProvider).recordFor(1, 1);
    expect(recovered?.status, PostReportOutcomeStatus.confirmed);
    expect(recovered?.details, isNull);
    expect(recovered?.idempotencyKey, isNull);
    expect(recovered?.reportId, 88);
    expect(gateway.reportPostCallCount, 0);
  });

  test('13. cambio de sesión durante hidratación no filtra payload', () async {
    final store = InMemoryPostReportOutcomeStore(
      seed: [_confirmedWithPayload(details: 'secreto-sesion')],
    )..readDelay = const Duration(milliseconds: 80);
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    final hydrate = c
        .read(postReportCoordinatorProvider.notifier)
        .ensureHydrated();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 9, email: 'otro@test.com'),
    );
    await hydrate;
    expect(c.read(postReportCoordinatorProvider).recordFor(9, 1), isNull);
    final original = c.read(postReportCoordinatorProvider).recordFor(1, 1);
    expect(original?.status, PostReportOutcomeStatus.confirmed);
    expect(original?.details, isNull);
    expect(gateway.reportPostCallCount, 0);
    expect(
      encodePostReportOutcomePayload(store.snapshot),
      isNot(contains('secreto-sesion')),
    );
  });

  test('14. dos confirmed con payload se limpian ambos', () async {
    final store = InMemoryPostReportOutcomeStore(
      seed: [
        _confirmedWithPayload(postId: 1, details: 'uno', reportId: 11),
        _confirmedWithPayload(
          postId: 2,
          generation: 5,
          details: 'dos',
          reportId: 22,
        ),
      ],
    );
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    await c.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    for (final postId in [1, 2]) {
      final record = c.read(postReportCoordinatorProvider).recordFor(1, postId);
      expect(record?.status, PostReportOutcomeStatus.confirmed);
      expect(record?.details, isNull);
      expect(record?.idempotencyKey, isNull);
    }
    expect(c.read(postReportCoordinatorProvider).recordFor(1, 1)?.reportId, 11);
    expect(c.read(postReportCoordinatorProvider).recordFor(1, 2)?.reportId, 22);
    expect(gateway.reportPostCallCount, 0);
  });

  test('15. confirmed se limpia y uncertain conserva payload', () async {
    final store = InMemoryPostReportOutcomeStore(
      seed: [
        _confirmedWithPayload(postId: 1, details: 'conf'),
        const PostReportOutcomeRecord(
          userId: 1,
          postId: 2,
          status: PostReportOutcomeStatus.uncertain,
          generation: 6,
          recordedAtMillis: 10,
          idempotencyKey: _kUuid,
          reasonCode: 'spam',
          details: 'incierto',
        ),
      ],
    );
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    await c.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    expect(
      c.read(postReportCoordinatorProvider).recordFor(1, 1)?.details,
      isNull,
    );
    expect(
      c.read(postReportCoordinatorProvider).recordFor(1, 1)?.status,
      PostReportOutcomeStatus.confirmed,
    );
    final uncertain = c.read(postReportCoordinatorProvider).recordFor(1, 2);
    expect(uncertain?.isRecoverableUncertain, isTrue);
    expect(uncertain?.details, 'incierto');
    expect(gateway.reportPostCallCount, 0);
  });

  test('16. v1 confirmed sin UUID sigue bloqueando y no genera POST', () async {
    final store = InMemoryPostReportOutcomeStore(
      seed: [
        const PostReportOutcomeRecord(
          userId: 1,
          postId: 5,
          status: PostReportOutcomeStatus.confirmed,
          generation: 2,
          recordedAtMillis: 1,
          details: 'legado-v1',
        ),
      ],
    );
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    await c.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    final record = c.read(postReportCoordinatorProvider).recordFor(1, 5);
    expect(record?.status, PostReportOutcomeStatus.confirmed);
    expect(record?.details, isNull);
    expect(record?.idempotencyKey, isNull);
    expect(
      c
          .read(postReportCoordinatorProvider.notifier)
          .tryBeginConfirming(userId: 1, postId: 5),
      isFalse,
    );
    expect(gateway.reportPostCallCount, 0);
  });

  test('17. v1 uncertain no se convierte en POST ni recibe UUID', () async {
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
    expect(
      c
          .read(postReportCoordinatorProvider)
          .recordFor(1, 5)
          ?.idempotencyKey,
      isNull,
    );
    expect(gateway.reportPostCallCount, 0);
  });

  test('18. persistencia corrupta fail-closed', () async {
    final store = InMemoryPostReportOutcomeStore(
      seed: [_confirmedWithPayload()],
    )..failReads = true;
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    await c.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    expect(c.read(postReportCoordinatorProvider).persistUnavailable, isTrue);
    expect(c.read(postReportCoordinatorProvider).recordFor(1, 1), isNull);
    expect(
      c
          .read(postReportCoordinatorProvider.notifier)
          .tryBeginConfirming(userId: 1, postId: 1),
      isFalse,
    );
    expect(gateway.reportPostCallCount, 0);
  });

  test('19. doble hidratación concurrente no dispara POST', () async {
    final store = InMemoryPostReportOutcomeStore(
      seed: [_confirmedWithPayload()],
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
    final record = c.read(postReportCoordinatorProvider).recordFor(1, 1);
    expect(record?.status, PostReportOutcomeStatus.confirmed);
    expect(record?.details, isNull);
    expect(record?.idempotencyKey, isNull);
  });

  test('20. details no quedan en el payload persistido', () async {
    final store = InMemoryPostReportOutcomeStore(
      seed: [_confirmedWithPayload(details: 'no-loguear')],
    );
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    await c.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    final encoded = encodePostReportOutcomePayload(store.snapshot);
    expect(encoded, isNot(contains('no-loguear')));
    expect(encoded, isNot(contains('details')));
    expect(encoded, contains('"status":"confirmed"'));
  });
}
