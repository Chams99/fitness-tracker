import 'package:fitness_tracker/app/theme.dart';
import 'package:fitness_tracker/features/progress/performance_chart.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final firstDay = CalendarDay.parse('2026-11-10');
final lastDay = CalendarDay.parse('2026-11-12');

Future<void> pumpChart(
  WidgetTester tester, {
  required Measurement measurement,
  required List<DailyResult> days,
  ChartMetric metric = ChartMetric.latest,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: trackerTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              PerformanceChart(
                days: days,
                metric: metric,
                measurement: measurement,
                durationStyle: DurationStyle.clock,
              ),
              const SizedBox(height: 800),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final plot = find
    .descendant(
      of: find.byType(PerformanceChart),
      matching: find.byType(CustomPaint),
    )
    .first;

void main() {
  testWidgets('selected points show the full date and repetition value', (
    tester,
  ) async {
    await pumpChart(
      tester,
      measurement: Measurement.repetitions,
      days: [
        (
          day: firstDay,
          first: 10,
          latest: 12,
          best: 15,
          total: 22,
          count: 2,
          latestReps: null,
          bestReps: null,
          totalReps: null,
        ),
        (
          day: lastDay,
          first: 16,
          latest: 18,
          best: 20,
          total: 34,
          count: 2,
          latestReps: null,
          bestReps: null,
          totalReps: null,
        ),
      ],
    );

    expect(find.text('12 Nov 2026'), findsOneWidget);
    expect(find.text('18 reps'), findsOneWidget);
    final plotRect = tester.getRect(plot);
    await tester.tapAt(Offset(plotRect.left + 2, plotRect.center.dy));
    await tester.pumpAndSettle();

    expect(find.text('10 Nov 2026'), findsOneWidget);
    expect(find.text('12 reps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final metric in [ChartMetric.latest, ChartMetric.volume]) {
    testWidgets(
      '${metric.label} snaps during drag and permits vertical scrolling',
      (tester) async {
        await pumpChart(
          tester,
          measurement: Measurement.repetitions,
          metric: metric,
          days: [
            for (final (offset, latest, total) in [
              (0, 10, 19),
              (2, 9, 17),
              (10, 14, 26),
            ])
              (
                day: firstDay.plusDays(offset),
                first: total - latest,
                latest: latest,
                best: latest > total - latest ? latest : total - latest,
                total: total,
                count: 2,
                latestReps: null,
                bestReps: null,
                totalReps: null,
              ),
          ],
        );
        final bounds = tester.getRect(plot);
        final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
        Offset position(double fraction) =>
            Offset(bounds.left + bounds.width * fraction, bounds.center.dy);

        final drag = await tester.startGesture(position(.95));
        await drag.moveTo(position(.35));
        await tester.pump();
        expect(find.text('12 Nov 2026'), findsOneWidget);
        expect(
          find.text(metric == ChartMetric.latest ? '9 reps' : '17 reps'),
          findsOneWidget,
        );

        await drag.moveTo(position(.02));
        await tester.pump();
        expect(find.text('10 Nov 2026'), findsOneWidget);
        expect(
          find.text(metric == ChartMetric.latest ? '10 reps' : '19 reps'),
          findsOneWidget,
        );
        await drag.up();
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, 0);
        expect(find.text('10 Nov 2026'), findsOneWidget);

        await tester.dragFrom(position(.8), const Offset(0, -80));
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, greaterThan(0));
        expect(find.text('10 Nov 2026'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('selected duration points spell out minutes and seconds', (
    tester,
  ) async {
    await pumpChart(
      tester,
      measurement: Measurement.duration,
      days: [
        (
          day: firstDay,
          first: 60,
          latest: 65,
          best: 65,
          total: 125,
          count: 2,
          latestReps: null,
          bestReps: null,
          totalReps: null,
        ),
      ],
    );

    expect(find.text('10 Nov 2026'), findsOneWidget);
    expect(find.text('1 minute, 5 seconds'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected weighted points retain the associated reps', (
    tester,
  ) async {
    await pumpChart(
      tester,
      measurement: Measurement.weightAndReps,
      metric: ChartMetric.best,
      days: [
        (
          day: firstDay,
          first: 60000,
          latest: 65000,
          best: 65000,
          total: 125000,
          count: 2,
          latestReps: 8,
          bestReps: 11,
          totalReps: 25,
        ),
      ],
    );

    expect(find.text('65 kg × 11 reps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
