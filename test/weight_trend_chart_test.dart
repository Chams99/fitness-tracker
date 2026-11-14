import 'package:fitness_tracker/app/theme.dart';
import 'package:fitness_tracker/features/profile/weight_page.dart';
import 'package:fitness_tracker/shared/domain/body_metrics.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selecting a weight point updates the dated accessible readout', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: trackerTheme(Brightness.light),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: WeightTrendChart(
              unit: WeightUnit.kg,
              records: [
                (day: CalendarDay.parse('2026-11-10'), grams: 72000),
                (day: CalendarDay.parse('2026-11-11'), grams: 71400),
                (day: CalendarDay.parse('2026-11-12'), grams: 72300),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('12 Nov 2026'), findsOneWidget);
    expect(find.text('72.3 kg'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Selected weigh-in: 12 Nov 2026, 72.3 kg'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Weight trend. Use increase or decrease to select a weigh-in.',
      ),
      findsOneWidget,
    );
    tester.semantics.decrease(
      find.semantics.byLabel(
        'Weight trend. Use increase or decrease to select a weigh-in.',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('11 Nov 2026'), findsOneWidget);
    expect(find.text('71.4 kg'), findsOneWidget);

    final chart = tester.getRect(
      find.byKey(const ValueKey('weight-trend-points')),
    );
    await tester.tapAt(Offset(chart.left + 4, chart.center.dy));
    await tester.pumpAndSettle();

    expect(find.text('10 Nov 2026'), findsOneWidget);
    expect(find.text('72 kg'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Selected weigh-in: 10 Nov 2026, 72 kg'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
