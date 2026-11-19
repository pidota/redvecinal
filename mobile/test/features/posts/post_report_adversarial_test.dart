import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:red_vecinal/features/posts/presentation/post_report_screen.dart';
import 'package:red_vecinal/features/posts/presentation/posts_screen.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_report_submit_controller_test.dart';
import 'post_test_support.dart';

ProviderContainer adversarialContainer({
  required FakePostGateway gateway,
  required InMemoryPostReportOutcomeStore store,
}) {
  return submitContainer(gateway: gateway, store: store);
}

void main() {
  test('1. fallo al persistir inFlight no envía POST', () async {
    final store = InMemoryPostReportOutcomeStore()..failWrites = true;
    final gateway = FakePostGateway();
    final c = adversarialContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');

    final result = await confirmAndSubmit(c, 1);
    expect(result, isA<PostReportSubmitBlocked>());
    expect(gateway.reportPostCallCount, 0);
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    expect(
      c.read(postReportCoordinatorProvider).recordFor(userId, 1)?.status,
      PostReportOutcomeStatus.persistBlocked,
    );
  });

  test('2. fallo al persistir confirmed no muestra éxito ni libera', () async {
    final store = InMemoryPostReportOutcomeStore()..failOnSaveNumber = 2;
    final gateway = FakePostGateway();
    final c = adversarialContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');

    final result = await confirmAndSubmit(c, 1);
    expect(result, isA<PostReportSubmitUncertain>());
    expect(gateway.reportPostCallCount, 1);
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    expect(
      c.read(postReportCoordinatorProvider).recordFor(userId, 1)?.status,
      isNot(PostReportOutcomeStatus.confirmed),
    );
    expect(
      c.read(postReportCoordinatorProvider).recordFor(userId, 1),
      isNotNull,
    );
  });

  test('3. fallo al persistir uncertain mantiene bloqueo', () async {
    final store = InMemoryPostReportOutcomeStore()..failOnSaveNumber = 2;
    final gateway = FakePostGateway(
      reportFailureByPostId: {4: const ApiTimeoutFailure()},
    );
    final c = adversarialContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(4).notifier).selectReason('spam');

    final result = await confirmAndSubmit(c, 4);
    expect(result, isA<PostReportSubmitUncertain>());
    expect(gateway.reportPostCallCount, 1);
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    expect(
      c.read(postReportCoordinatorProvider).recordFor(userId, 4),
      isNotNull,
    );
    final blocked = await confirmAndSubmit(c, 4);
    expect(blocked, isA<PostReportSubmitBlocked>());
    expect(gateway.reportPostCallCount, 1);
  });

  test('4. dos controladores simultáneos: un POST', () async {
    final store = InMemoryPostReportOutcomeStore();
    final gateway = FakePostGateway(reportDelayMs: 80);
    final c = adversarialContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(1).notifier).selectReason('spam');
    final first = confirmAndSubmit(c, 1);
    final second = confirmAndSubmit(c, 1);
    await Future.wait([first, second]);
    expect(gateway.reportPostCallCount, 1);
  });

  test('5. dos confirmaciones simultáneas', () async {
    final store = InMemoryPostReportOutcomeStore();
    final gateway = FakePostGateway();
    final c = adversarialContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    await c.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    final userId =
        (c.read(authControllerProvider) as AuthAuthenticated).user.id;
    final coordinator = c.read(postReportCoordinatorProvider.notifier);
    expect(coordinator.tryBeginConfirming(userId: userId, postId: 3), isTrue);
    expect(coordinator.tryBeginConfirming(userId: userId, postId: 3), isFalse);
  });

  test('6. logout antes de iniciar POST', () async {
    final store =
        InMemoryPostReportOutcomeStore()
          ..writeDelay = const Duration(milliseconds: 80);
    final gateway = FakePostGateway();
    final c = adversarialContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    c.read(postReportFormControllerProvider(2).notifier).selectReason('spam');
    final future = confirmAndSubmit(c, 2);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    c.read(authControllerProvider.notifier).state = const AuthUnauthenticated();
    final result = await future;
    expect(result, isA<PostReportSubmitDiscarded>());
    expect(gateway.reportPostCallCount, 0);
  });

  test('7. logout durante POST conserva marcador original', () async {
    final store = InMemoryPostReportOutcomeStore();
    final gateway = FakePostGateway(reportDelayMs: 80);
    final c = adversarialContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    c.read(postReportFormControllerProvider(2).notifier).selectReason('spam');
    final future = confirmAndSubmit(c, 2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    c.read(authControllerProvider.notifier).state = const AuthUnauthenticated();
    await future;
    expect(gateway.reportPostCallCount, 1);
    expect(
      c.read(postReportCoordinatorProvider).recordFor(1, 2)?.status,
      PostReportOutcomeStatus.confirmed,
    );
  });

  test('8. respuesta tardía tras cambio de usuario', () async {
    final store = InMemoryPostReportOutcomeStore();
    final gateway = FakePostGateway(reportDelayMs: 80);
    final c = adversarialContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    c.read(postReportFormControllerProvider(8).notifier).selectReason('spam');
    final future = confirmAndSubmit(c, 8);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 77, email: 'otro@test.com'),
    );
    final result = await future;
    expect(result, isA<PostReportSubmitDiscarded>());
    expect(c.read(postReportCoordinatorProvider).recordFor(77, 8), isNull);
    expect(
      c.read(postReportCoordinatorProvider).recordFor(1, 8)?.status,
      PostReportOutcomeStatus.confirmed,
    );
  });

  test('9. reinicio con inFlight persistido', () async {
    final store = InMemoryPostReportOutcomeStore(
      seed: [
        PostReportOutcomeRecord(
          userId: 1,
          postId: 9,
          status: PostReportOutcomeStatus.inFlight,
          generation: 4,
          recordedAtMillis: 1,
        ),
      ],
    );
    final gateway = FakePostGateway();
    final c = adversarialContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    await c.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    expect(
      c.read(postReportCoordinatorProvider).recordFor(1, 9)?.status,
      PostReportOutcomeStatus.uncertain,
    );
    c.read(postReportFormControllerProvider(9).notifier).selectReason('spam');
    final result = await confirmAndSubmit(c, 9);
    expect(result, isA<PostReportSubmitBlocked>());
    expect(gateway.reportPostCallCount, 0);
  });

  test('10. reinicio con uncertain persistido', () async {
    final store = InMemoryPostReportOutcomeStore(
      seed: [
        PostReportOutcomeRecord(
          userId: 1,
          postId: 10,
          status: PostReportOutcomeStatus.uncertain,
          generation: 2,
          recordedAtMillis: 1,
        ),
      ],
    );
    final gateway = FakePostGateway();
    final c = adversarialContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(10).notifier).selectReason('spam');
    final result = await confirmAndSubmit(c, 10);
    expect(result, isA<PostReportSubmitBlocked>());
    expect(gateway.reportPostCallCount, 0);
  });

  test('11. HTTP 500 no reintenta', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {11: const ApiServerFailure()},
    );
    final c = adversarialContainer(
      gateway: gateway,
      store: InMemoryPostReportOutcomeStore(),
    );
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(11).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 11), isA<PostReportSubmitUncertain>());
    expect(await confirmAndSubmit(c, 11), isA<PostReportSubmitBlocked>());
    expect(gateway.reportPostCallCount, 1);
  });

  test('12. HTTP 502 no reintenta', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {12: const ApiServerFailure()},
    );
    final c = adversarialContainer(
      gateway: gateway,
      store: InMemoryPostReportOutcomeStore(),
    );
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(12).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 12), isA<PostReportSubmitUncertain>());
    expect(gateway.reportPostCallCount, 1);
  });

  test('13. HTTP 503 no reintenta', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {13: const ApiServerFailure()},
    );
    final c = adversarialContainer(
      gateway: gateway,
      store: InMemoryPostReportOutcomeStore(),
    );
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(13).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 13), isA<PostReportSubmitUncertain>());
    expect(gateway.reportPostCallCount, 1);
  });

  test('14. HTTP 201 malformado no reintenta', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {14: const ApiUnexpectedFailure()},
    );
    final c = adversarialContainer(
      gateway: gateway,
      store: InMemoryPostReportOutcomeStore(),
    );
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(14).notifier).selectReason('spam');
    expect(await confirmAndSubmit(c, 14), isA<PostReportSubmitUncertain>());
    expect(await confirmAndSubmit(c, 14), isA<PostReportSubmitBlocked>());
    expect(gateway.reportPostCallCount, 1);
  });

  testWidgets('15. acceso directo a ruta', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openMainShellAuthenticated(tester, postGateway: gateway);
    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(PostsScreen))).go('/posts/1/report');
    await tester.pumpAndSettle();
    expect(find.byType(PostReportScreen), findsOneWidget);
    expect(gateway.reportPostCallCount, 0);
  });

  testWidgets('16. dos instancias de pantalla', (tester) async {
    final gateway = FakePostGateway(reportDelayMs: 80);
    final store = InMemoryPostReportOutcomeStore();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, state) => const Column(
                children: [
                  Expanded(child: PostReportScreen(postId: 1)),
                  Expanded(child: PostReportScreen(postId: 1)),
                ],
              ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig),
          authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
          authControllerProvider.overrideWith(
            AuthenticatedBootAuthController.new,
          ),
          postRepositoryProvider.overrideWithValue(gateway),
          postReportOutcomeStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PostReportScreen), findsNWidgets(2));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PostReportScreen).first),
    );
    container
        .read(postReportFormControllerProvider(1).notifier)
        .selectReason('spam');
    final first = confirmAndSubmit(container, 1);
    final second = confirmAndSubmit(container, 1);
    await tester.pump(const Duration(milliseconds: 120));
    await Future.wait([first, second]);
    expect(gateway.reportPostCallCount, 1);
  });

  testWidgets('17. cancelación del diálogo', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openMainShellAuthenticated(tester, postGateway: gateway);
    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(PostsScreen))).go('/posts/1/report');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam o publicidad no deseada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar').last);
    await tester.pumpAndSettle();
    expect(gateway.reportPostCallCount, 0);
    expect(find.text('Confirmar envío'), findsNothing);
  });

  test('18. sin reintentos automáticos tras red', () async {
    final gateway = FakePostGateway(
      reportFailureByPostId: {18: const ApiNetworkFailure()},
    );
    final c = adversarialContainer(
      gateway: gateway,
      store: InMemoryPostReportOutcomeStore(),
    );
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(18).notifier).selectReason('spam');
    await confirmAndSubmit(c, 18);
    expect(gateway.reportPostCallCount, 1);
  });

  test('19. sin fuga de detalles a almacenamiento', () async {
    final store = InMemoryPostReportOutcomeStore();
    final gateway = FakePostGateway();
    final c = adversarialContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(19).notifier).selectReason('spam');
    c
        .read(postReportFormControllerProvider(19).notifier)
        .setDetails('texto privado del vecino');
    await confirmAndSubmit(c, 19);
    expect(store.lastSaved, isNotEmpty);
    for (final record in store.lastSaved) {
      final json = record.toJson();
      expect(json.containsKey('details'), isFalse);
      expect(json.containsKey('reason'), isFalse);
      expect(json.containsKey('reason_code'), isFalse);
      expect(json.containsKey('token'), isFalse);
      expect(
        json.values.whereType<String>(),
        isNot(contains('texto privado del vecino')),
      );
    }
  });

  test('20. sin bloqueo cruzado entre usuarios', () async {
    final store = InMemoryPostReportOutcomeStore();
    final gateway = FakePostGateway();
    final c = adversarialContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(20).notifier).selectReason('spam');
    await confirmAndSubmit(c, 20);
    expect(c.read(postReportCoordinatorProvider).recordFor(1, 20), isNotNull);
    expect(c.read(postReportCoordinatorProvider).recordFor(99, 20), isNull);
  });

  test('lectura corrupta bloquea envío', () async {
    final store = InMemoryPostReportOutcomeStore()..failReads = true;
    final gateway = FakePostGateway();
    final c = adversarialContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(21).notifier).selectReason('spam');
    final result = await confirmAndSubmit(c, 21);
    expect(result, isA<PostReportSubmitBlocked>());
    expect(gateway.reportPostCallCount, 0);
  });

  test('motivo ajeno al catálogo local no se envía', () async {
    final gateway = FakePostGateway();
    final c = adversarialContainer(
      gateway: gateway,
      store: InMemoryPostReportOutcomeStore(),
    );
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(22).notifier).selectReason('other');
    final result = await confirmAndSubmit(c, 22);
    expect(result, isA<PostReportSubmitValidationFailed>());
    expect(gateway.reportPostCallCount, 0);
  });

  const validRecordJson = '''
{"records":[{"userId":1,"postId":2,"status":"confirmed","generation":1,"recordedAt":1}]}
''';

  test('JSON completamente corrupto', () {
    expect(
      () => parsePostReportOutcomePayload('{no json'),
      throwsA(isA<PostReportOutcomeStoreException>()),
    );
  });

  test('JSON válido con un registro individual malformado', () {
    expect(
      () => parsePostReportOutcomePayload(
        '{"records":[{"userId":1,"postId":2,"status":"confirmed","generation":1,"recordedAt":1},"roto"]}',
      ),
      throwsA(isA<PostReportOutcomeStoreException>()),
    );
  });

  test('registro con userId inválido', () {
    expect(
      () => parsePostReportOutcomePayload(
        '{"records":[{"userId":"x","postId":2,"status":"confirmed","generation":1,"recordedAt":1}]}',
      ),
      throwsA(isA<PostReportOutcomeStoreException>()),
    );
  });

  test('registro con postId inválido', () {
    expect(
      () => parsePostReportOutcomePayload(
        '{"records":[{"userId":1,"postId":null,"status":"confirmed","generation":1,"recordedAt":1}]}',
      ),
      throwsA(isA<PostReportOutcomeStoreException>()),
    );
  });

  test('estado desconocido', () {
    expect(
      () => parsePostReportOutcomePayload(
        '{"records":[{"userId":1,"postId":2,"status":"resolved","generation":1,"recordedAt":1}]}',
      ),
      throwsA(isA<PostReportOutcomeStoreException>()),
    );
  });

  test('lista con un registro válido y otro inválido', () {
    expect(
      () => parsePostReportOutcomePayload(
        '{"records":['
        '{"userId":1,"postId":2,"status":"confirmed","generation":1,"recordedAt":1},'
        '{"userId":1,"postId":3,"status":"confirmed","generation":1}'
        ']}',
      ),
      throwsA(isA<PostReportOutcomeStoreException>()),
    );
  });

  test('payload válido se interpreta completo', () {
    final records = parsePostReportOutcomePayload(validRecordJson);
    expect(records, hasLength(1));
    expect(records.single.status, PostReportOutcomeStatus.confirmed);
  });

  test('reinicio tras lectura inválida bloquea POST', () async {
    final store = _JsonOutcomeStore(
      '{"records":[{"userId":1,"postId":2,"status":"confirmed"}]}',
    );
    final gateway = FakePostGateway();
    final first = submitContainer(gateway: gateway, store: store);
    addTearDown(first.dispose);
    await first.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    expect(
      first.read(postReportCoordinatorProvider).persistUnavailable,
      isTrue,
    );

    final gateway2 = FakePostGateway();
    final second = submitContainer(gateway: gateway2, store: store);
    addTearDown(second.dispose);
    second
        .read(postReportFormControllerProvider(2).notifier)
        .selectReason('spam');
    final result = await confirmAndSubmit(second, 2);
    expect(result, isA<PostReportSubmitBlocked>());
    expect(gateway2.reportPostCallCount, 0);
  });

  test('almacenamiento ilegible no ejecuta POST', () async {
    final store = _JsonOutcomeStore('{"records":[1,2,3]}');
    final gateway = FakePostGateway();
    final c = submitContainer(gateway: gateway, store: store);
    addTearDown(c.dispose);
    c.read(postReportFormControllerProvider(30).notifier).selectReason('spam');
    final result = await confirmAndSubmit(c, 30);
    expect(result, isA<PostReportSubmitBlocked>());
    expect(gateway.reportPostCallCount, 0);
  });
}

class _JsonOutcomeStore implements PostReportOutcomeStore {
  _JsonOutcomeStore(this.raw);

  final String raw;

  @override
  Future<List<PostReportOutcomeRecord>> loadAll() {
    return Future<List<PostReportOutcomeRecord>>.value(
      parsePostReportOutcomePayload(raw),
    );
  }

  @override
  Future<void> saveAll(List<PostReportOutcomeRecord> records) async {}
}
