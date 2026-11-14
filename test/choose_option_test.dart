import 'package:fitness_tracker/app/theme.dart';
import 'package:fitness_tracker/shared/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('single-option picker has a useful height on a short screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var footerActionTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [TrackerColors.light]),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  await chooseOption<String>(
                    context,
                    'Choose exercise',
                    const [
                      (
                        value: 'push-ups',
                        label: 'Push-ups',
                        subtitle: 'Repetitions',
                      ),
                    ],
                    selected: 'push-ups',
                    footerText:
                        'This is your only exercise with recorded results.',
                    footerActionLabel: 'Log another exercise',
                    onFooterAction: () => footerActionTapped = true,
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    final picker = find.byType(ListView).last;
    final height = tester.getSize(picker).height;
    expect(height, greaterThan(200));
    expect(height, lessThan(640 * .78));
    expect(find.text('Push-ups'), findsOneWidget);
    expect(
      find.text('This is your only exercise with recorded results.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Log another exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Choose exercise'), findsNothing);
    expect(footerActionTapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long option lists scroll to later choices', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [TrackerColors.light]),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  selected = await chooseOption<String>(
                    context,
                    'Choose exercise',
                    [
                      for (var i = 1; i <= 8; i++)
                        (
                          value: '$i',
                          label: 'Exercise $i',
                          subtitle: 'Repetitions',
                        ),
                    ],
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    expect(find.text('Exercise 1'), findsOneWidget);
    expect(
      find.text('This is your only exercise with recorded results.'),
      findsNothing,
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Exercise 8'), findsOneWidget);
    await tester.tap(find.text('Exercise 8'));
    await tester.pumpAndSettle();
    expect(selected, '8');
    expect(tester.takeException(), isNull);
  });
}
