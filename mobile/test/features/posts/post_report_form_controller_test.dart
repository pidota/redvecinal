import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/post_report_form_controller.dart';
import 'package:red_vecinal/features/posts/data/post_report_outcome_store.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';

ProviderContainer reportFormContainer() {
  return ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(testAppConfig),
      authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
      authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
      postReportOutcomeStoreProvider.overrideWithValue(
        InMemoryPostReportOutcomeStore(),
      ),
    ],
  );
}

void main() {
  test('resetForSession limpia motivo y detalles', () {
    final container = reportFormContainer();
    addTearDown(container.dispose);

    final notifier = container.read(
      postReportFormControllerProvider(1).notifier,
    );
    notifier.selectReason('spam');
    notifier.setDetails('Texto privado');
    notifier.resetForSession();

    final state = container.read(postReportFormControllerProvider(1));
    expect(state.selectedReasonCode, isNull);
    expect(state.details, isEmpty);
  });

  test('cambio de sesión limpia selección', () {
    final container = reportFormContainer();
    addTearDown(container.dispose);

    final notifier = container.read(
      postReportFormControllerProvider(5).notifier,
    );
    notifier.selectReason('inappropriate');
    notifier.resetForSession();
    final state = container.read(postReportFormControllerProvider(5));
    expect(state.selectedReasonCode, isNull);
  });

  test('validación details superior a 2000', () {
    final container = reportFormContainer();
    addTearDown(container.dispose);

    final notifier = container.read(
      postReportFormControllerProvider(1).notifier,
    );
    notifier.selectReason('spam');
    notifier.setDetails('d' * 2001);
    expect(notifier.validateFields(), isFalse);
    final state = container.read(postReportFormControllerProvider(1));
    expect(state.detailsError, isNotNull);
  });

  test('validateFields sin motivo falla', () {
    final container = reportFormContainer();
    addTearDown(container.dispose);

    final notifier = container.read(
      postReportFormControllerProvider(1).notifier,
    );
    expect(notifier.validateFields(), isFalse);
    final state = container.read(postReportFormControllerProvider(1));
    expect(state.reasonError, isNotNull);
  });
}
