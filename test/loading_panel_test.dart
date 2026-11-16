import 'package:fitness_tracker/app/theme.dart';
import 'package:fitness_tracker/shared/widgets/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('an empty result can be narrower than the outgoing rows', (
    tester,
  ) async {
    Future<void> show(AsyncValue<String> value) => tester.pumpWidget(
      MaterialApp(
        theme: trackerTheme(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: AsyncPanel(
              value,
              loading: const SkeletonRows(count: 2, rowHeight: 75),
              builder: Text.new,
            ),
          ),
        ),
      ),
    );

    await show(const AsyncLoading());
    final skeleton = find.byType(SkeletonRows);
    final pendingWidth = tester.getSize(skeleton).width;
    await show(const AsyncData('No entries yet.'));
    expect(tester.getSize(skeleton).width, pendingWidth);
    expect(
      tester.getSize(find.text('No entries yet.')).width,
      lessThan(pendingWidth),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(skeleton, findsNothing);
  });

  for (final reduceMotion in [false, true]) {
    testWidgets('AsyncPanel crossfades loading into data '
        '(Reduce Motion: $reduceMotion)', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduceMotion);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      Future<void> show(AsyncValue<String> value) => tester.pumpWidget(
        MaterialApp(
          theme: trackerTheme(Brightness.light),
          home: Scaffold(
            body: AsyncPanel(
              value,
              loading: const Skeleton(width: 100, height: 160),
              builder: Text.new,
            ),
          ),
        ),
      );

      double opacityOf(Finder child) => tester
          .widget<Opacity>(
            find.ancestor(of: child, matching: find.byType(Opacity)).first,
          )
          .opacity;

      await show(const AsyncData('Cached data'));
      expect(opacityOf(find.text('Cached data')), 1);
      expect(find.byType(Skeleton), findsNothing);

      await show(const AsyncData('Updated data'));
      expect(opacityOf(find.text('Updated data')), 1);

      const ready = 'Ready data';
      final content = find.text(ready);
      final skeleton = find.byType(Skeleton);
      await show(const AsyncLoading());
      expect(find.text('Updated data'), findsNothing);
      expect(find.bySemanticsLabel('Loading records'), findsOneWidget);
      expect(skeleton, findsOneWidget);
      await show(const AsyncData(ready));
      expect(find.bySemanticsLabel('Loading records'), findsNothing);
      expect(find.bySemanticsLabel(ready), findsOneWidget);
      expect(
        tester.getRect(find.byType(AsyncPanel<String>)),
        tester.getRect(content),
      );
      if (reduceMotion) {
        expect(skeleton, findsNothing);
        expect(opacityOf(content), 1);
      } else {
        final firstOpacity = opacityOf(content);
        expect(firstOpacity, inExclusiveRange(0, 1));
        expect(opacityOf(skeleton), 1);
        await tester.pump(const Duration(milliseconds: 90));
        expect(opacityOf(content), inExclusiveRange(firstOpacity, 1));
        expect(opacityOf(skeleton), inExclusiveRange(0, 1));
        await tester.pumpAndSettle();
        expect(skeleton, findsNothing);
        expect(opacityOf(content), 1);
      }

      await show(const AsyncLoading());
      expect(skeleton, findsOneWidget);
      expect(content, findsNothing);
      await show(AsyncError(StateError('Read failed'), StackTrace.empty));
      expect(find.text('Couldn’t load this view'), findsOneWidget);
      expect(skeleton, findsNothing);
    });
  }
}
