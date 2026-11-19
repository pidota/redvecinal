import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/posts/application/post_report_coordinator.dart';
import 'package:red_vecinal/features/posts/application/post_report_form_controller.dart';
import 'package:red_vecinal/features/posts/application/post_report_outcome.dart';
import 'package:red_vecinal/features/posts/data/post_report_outcome_store.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

ProviderContainer submitContainer({
  required FakePostGateway gateway,
  PostReportOutcomeStore? store,
}) {
  return ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(testAppConfig),
      authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      postRepositoryProvider.overrideWithValue(gateway),
      postReportOutcomeStoreProvider.overrideWithValue(
        store ?? InMemoryPostReportOutcomeStore(),
      ),
      authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
    ],
  );
}

Future<PostReportSubmitResult> confirmAndSubmit(
  ProviderContainer container,
  int postId,
) async {
  final userId =
      (container.read(authControllerProvider) as AuthAuthenticated).user.id;
  final coordinator = container.read(postReportCoordinatorProvider.notifier);
  await coordinator.ensureHydrated();
  coordinator.tryBeginConfirming(userId: userId, postId: postId);
  return container
      .read(postReportFormControllerProvider(postId).notifier)
      .submitConfirmed();
}

void main() {
  test('POST único confirmado', () async {
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(7).notifier).selectReason('spam');

    final result = await confirmAndSubmit(c, 7);
    expect(result, isA<PostReportSubmitSuccess>());
    expect(gateway.reportPostCallCount, 1);
    expect(gateway.reportPayloads.single['reason_code'], 'spam');
    expect(gateway.reportPayloads.single.containsKey('reporter_id'), isFalse);
  });

  test('dos confirmaciones: un solo POST', () async {
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(3).notifier).selectReason('spam');
    await confirmAndSubmit(c, 3);
    final second = await confirmAndSubmit(c, 3);
    expect(second, isA<PostReportSubmitBlocked>());
    expect(gateway.reportPostCallCount, 1);
  });

  test('inFlight bloquea segundo intento', () async {
    final gateway = FakePostGateway(reportDelayMs: 80);
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(4).notifier).selectReason('spam');
    final first = confirmAndSubmit(c, 4);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final second = await confirmAndSubmit(c, 4);
    expect(second, isA<PostReportSubmitBlocked>());
    await first;
    expect(gateway.reportPostCallCount, 1);
  });

  test('timeout marca incierto y no reintenta', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {1: const ApiTimeoutFailure()},
    );
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    final result = await confirmAndSubmit(c, 1);
    expect(result, isA<PostReportSubmitUncertain>());
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    expect(
      c.read(postReportCoordinatorProvider).recordFor(userId, 1)?.status,
      PostReportOutcomeStatus.uncertain,
    );
    final blocked = await confirmAndSubmit(c, 1);
    expect(blocked, isA<PostReportSubmitBlocked>());
    expect(gateway.reportPostCallCount, 1);
  });

  test('HTTP 500 incierto', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {2: const ApiServerFailure()},
    );
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(2).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 2), isA<PostReportSubmitUncertain>());
  });

  test('201 malformado incierto', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {8: const ApiUnexpectedFailure()},
    );
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(8).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 8), isA<PostReportSubmitUncertain>());
  });

  test('403 no persiste incierto', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {1: const ApiForbiddenFailure()},
    );
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    final result = await confirmAndSubmit(c, 1);
    expect(result, isA<PostReportSubmitFailure>());
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    expect(c.read(postReportCoordinatorProvider).recordFor(userId, 1), isNull);
  });

  test('404 definitivo', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {1: const ApiNotFoundFailure()},
    );
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitFailure>());
  });

  test('422 validación servidor', () async {
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
    expect(c.read(postReportFormControllerProvider(1)).reasonError, 'inválido');
  });

  test('401 no marca éxito en sesión', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {1: const ApiSessionExpiredFailure()},
    );
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 1), isA<PostReportSubmitFailure>());
  });

  test('persistencia confirmada sobrevive reinicio de providers', () async {
    final store = InMemoryPostReportOutcomeStore();
    final gateway = FakePostGateway();
    final first = submitContainer(gateway: gateway, store: store);
    addTearDown(first.dispose);
    first
        .read(postReportFormControllerProvider(11).notifier)
        .selectReason('inappropriate');
    await confirmAndSubmit(first, 11);

    final second = submitContainer(gateway: gateway, store: store);
    addTearDown(second.dispose);
    await second.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    final userId =
        (second.read(authControllerProvider) as AuthAuthenticated).user.id;
    expect(
      second.read(postReportCoordinatorProvider).recordFor(userId, 11)?.status,
      PostReportOutcomeStatus.confirmed,
    );
  });

  test('persistencia incierta sobrevive hidratación', () async {
    final store = InMemoryPostReportOutcomeStore();
    final gateway = FakePostGateway(
      reportFailureByPostId: {6: const ApiNetworkFailure()},
    );
    final first = submitContainer(gateway: gateway, store: store);
    addTearDown(first.dispose);
    first
        .read(postReportFormControllerProvider(6).notifier)
        .selectReason('spam');
    await confirmAndSubmit(first, 6);

    final second = submitContainer(gateway: FakePostGateway(), store: store);
    addTearDown(second.dispose);
    await second.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    final userId =
        (second.read(authControllerProvider) as AuthAuthenticated).user.id;
    expect(
      second.read(postReportCoordinatorProvider).recordFor(userId, 6)?.status,
      PostReportOutcomeStatus.uncertain,
    );
  });

  test('aislamiento entre usuarios', () async {
    final store = InMemoryPostReportOutcomeStore();
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    await confirmAndSubmit(c, 1);

    expect(c.read(postReportCoordinatorProvider).recordFor(99, 1), isNull);
  });

  test('inFlight persistido se hidrata como incierto', () async {
    final store = InMemoryPostReportOutcomeStore(
      seed: [
        PostReportOutcomeRecord(
          userId: 1,
          postId: 5,
          status: PostReportOutcomeStatus.inFlight,
          generation: 3,
          recordedAtMillis: 1,
        ),
      ],
    );
    final c = submitContainer(gateway: FakePostGateway(), store: store);
    addTearDown(c.dispose);
    await c.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    expect(
      c.read(postReportCoordinatorProvider).recordFor(1, 5)?.status,
      PostReportOutcomeStatus.uncertain,
    );
  });

  test('logout durante POST no aplica éxito a otra sesión', () async {
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
    final result = await future;
    expect(result, isA<PostReportSubmitDiscarded>());
    expect(c.read(postReportCoordinatorProvider).recordFor(9, 2), isNull);
    expect(
      c.read(postReportCoordinatorProvider).recordFor(1, 2)?.status,
      PostReportOutcomeStatus.confirmed,
    );
  });

  test('sin motivo no hay POST', () async {
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway);
    addTearDown(c.dispose);
    final result = await confirmAndSubmit(c, 1);
    expect(result, isA<PostReportSubmitValidationFailed>());
    expect(gateway.reportPostCallCount, 0);
  });
}
