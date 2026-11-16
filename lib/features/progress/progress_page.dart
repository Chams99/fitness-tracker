import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/database/tracker_repository.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/exercise_icon.dart';
import '../../shared/widgets/ui.dart';
import '../logging/log_page.dart';
import 'date_range_page.dart';
import 'performance_chart.dart';

class ProgressPage extends ConsumerStatefulWidget {
  const ProgressPage({super.key});

  @override
  ConsumerState<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends ConsumerState<ProgressPage> {
  RangeSelection _range = allTime;
  bool _hasShownPerformance = false;

  Future<void> _pickExercise(List<CatalogItem> list, String current) async {
    final id = await chooseOption<String>(
      context,
      'Choose exercise',
      [
        for (final row in list)
          (
            value: row.exercise.id,
            label: row.exercise.name,
            subtitle: row.exercise.measurement.label,
          ),
      ],
      selected: current,
      leading: (_, name) => ExerciseIcon(name),
      footerText: list.length == 1
          ? 'This is your only exercise with recorded results.'
          : null,
      footerActionLabel: list.length == 1 ? 'Log another exercise' : null,
      onFooterAction: list.length == 1
          ? () => WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) showLogSheet(context);
            })
          : null,
    );
    if (!mounted || id == null) return;
    if (id != current) ref.read(actionsProvider).select();
    try {
      await ref.read(repositoryProvider).saveProgressExercise(id);
    } catch (error) {
      if (mounted) {
        announce(
          context,
          describeError(error, fallback: 'Couldn’t remember this exercise.'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final choices = ref
        .watch(catalogProvider)
        .whenData(
          (rows) => rows
              .where((row) => !row.exercise.archived && row.count > 0)
              .toList(),
        );
    final selected = ref.watch(progressExerciseProvider);
    final tracked = choices.value;
    final selection = tracked == null || tracked.isEmpty
        ? choices.whenData<Exercise?>((_) => null)
        : selected.whenData<Exercise?>(
            (id) =>
                (tracked.where((row) => row.exercise.id == id).firstOrNull ??
                        tracked.first)
                    .exercise,
          );
    final exercise = selection.value;
    final range = selectionBounds(_range, today);
    final query = exercise == null
        ? null
        : performanceProvider((exercise.id, range));
    final AsyncValue<Performance?> data = query == null
        ? selection.whenData((_) => null)
        : ref.watch(query);
    // Expose both filters with the first chart and keep them available
    // when the next exercise or range needs its own read.
    if (data.hasValue) _hasShownPerformance = data.requireValue != null;
    final showFilters =
        exercise != null && (_hasShownPerformance || data.hasError);
    final pageData = showFilters
        ? AsyncData(exercise)
        : data.whenData<Exercise?>((_) => null);

    void retry() {
      if (choices.hasError) {
        ref.invalidate(catalogProvider);
      } else if (selection.hasError) {
        ref.invalidate(progressExerciseProvider);
      } else if (query != null) {
        ref.invalidate(query);
      }
    }

    return ScreenScroll(
      primary: true,
      width: 1100,
      scrollKey: const PageStorageKey('progress'),
      children: [
        const ScreenHeading('Progress', bottom: Space.xs),
        AsyncPanel(
          pageData,
          loadingLabel: 'Loading progress',
          loading: const _ProgressSkeleton(),
          retry: retry,
          builder: (exercise) {
            if (exercise == null) return const _FirstProgress();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilterButton(
                  exercise.name,
                  () => _pickExercise(tracked!, exercise.id),
                  leading: ExerciseIcon(exercise.name),
                  prominent: true,
                ),
                FilterButton(_range.preset.label, () async {
                  final range = await selectRange(context, _range, today);
                  if (mounted && range != null) {
                    ref.read(actionsProvider).select();
                    setState(() => _range = range);
                  }
                }),
                AsyncPanel(
                  data,
                  loadingLabel: 'Loading performance',
                  loading: const PerformanceSkeleton.progress(),
                  retry: retry,
                  builder: (data) => _PerformanceContent(
                    data: data!,
                    exercise: exercise,
                    range: range,
                    link: true,
                    onResetRange: _range == allTime
                        ? null
                        : () => setState(() => _range = allTime),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FirstProgress extends StatelessWidget {
  const _FirstProgress();

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final height = MediaQuery.sizeOf(context).height - insets.vertical;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final top = (height * .10 / scale).clamp(24.0, 88.0);
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 445),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EmptyStateIllustration(
                'assets/brand/progress-notebook.webp',
                maxWidth: 292,
                aspectRatio: 2,
              ),
              EmptyBlock(
                title: 'See how your sets change',
                message: 'Record a result to see its first, latest, and best values here.',
                action: 'Log your first result',
                onAction: () => showLogSheet(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressSkeleton extends StatelessWidget {
  const _ProgressSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Space.target),
        child: Row(
          children: [
            const Skeleton(width: 24, height: 24, circular: true),
            const SizedBox(width: Space.sm),
            Flexible(
              child: SkeletonText(width: 124, style: context.type.titleLarge),
            ),
          ],
        ),
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Space.target),
        child: Center(
          widthFactor: 1,
          child: SkeletonText(width: 62, style: context.type.labelLarge),
        ),
      ),
      const PerformanceSkeleton.progress(),
    ],
  );
}

class PerformanceSkeleton extends StatelessWidget {
  const PerformanceSkeleton({super.key}) : _progressTab = false;
  const PerformanceSkeleton.progress({super.key}) : _progressTab = true;

  final bool _progressTab;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SkeletonText(width: 142, style: context.type.bodySmall),
      SizedBox(height: _progressTab ? 14 : Space.md),
      SkeletonText(
        width: 108,
        style: _progressTab
            ? context.type.headlineMedium
            : context.type.headlineSmall,
      ),
      if (!_progressTab) const SizedBox(height: Space.sm),
      SkeletonText(width: 116, style: context.type.bodySmall),
      SizedBox(height: _progressTab ? 14 : Space.lg),
      const Divider(),
      SizedBox(height: _progressTab ? 15 : Space.md),
      SkeletonText(width: 138, style: context.type.titleLarge),
      if (_progressTab) ...[
        SizedBox(
          height: Space.target,
          child: Row(
            children: [
              SkeletonText(width: 80, style: context.type.labelLarge),
              const SizedBox(width: 19),
              SkeletonText(width: 64, style: context.type.labelLarge),
            ],
          ),
        ),
        SkeletonText(width: 76, style: context.type.bodySmall),
        SkeletonText(width: 80, style: context.type.headlineSmall),
        SkeletonText(width: 75, style: context.type.bodySmall),
        const SizedBox(height: Space.sm),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(22, 9, 12, 0),
          child: Skeleton(
            width: double.infinity,
            height:
                153 +
                (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(
                  0.0,
                  24.0,
                ),
          ),
        ),
      ] else ...[
        const SizedBox(height: Space.md),
        const Skeleton(width: double.infinity, height: 168),
        const SizedBox(height: Space.sm),
        SkeletonText(width: 108, style: context.type.bodySmall),
      ],
    ],
  );
}

class PerformanceView extends ConsumerWidget {
  const PerformanceView({
    required this.exercise,
    required this.range,
    this.link = false,
    this.rangeAction,
    this.onResetRange,
    super.key,
  });
  final Exercise exercise;
  final DayRange range;
  final bool link;
  final Widget? rangeAction;
  final VoidCallback? onResetRange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = performanceProvider((exercise.id, range));
    final panel = AsyncPanel(
      ref.watch(provider),
      loadingLabel: 'Loading performance',
      loading: const PerformanceSkeleton(),
      retry: () => ref.invalidate(provider),
      builder: (data) => _PerformanceContent(
        data: data,
        exercise: exercise,
        range: range,
        link: link,
        showChartTitle: rangeAction == null,
        onResetRange: onResetRange,
      ),
    );
    if (rangeAction == null) return panel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('Performance', action: rangeAction),
        panel,
      ],
    );
  }
}

class _PerformanceContent extends ConsumerWidget {
  const _PerformanceContent({
    required this.data,
    required this.exercise,
    required this.range,
    required this.link,
    required this.onResetRange,
    this.showChartTitle = true,
  });

  final Performance data;
  final Exercise exercise;
  final DayRange range;
  final bool link, showChartTitle;
  final VoidCallback? onResetRange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(durationProvider);
    if (data.days.isEmpty) {
      return EmptyBlock(
        title: 'No activity in this range',
        message: 'Choose a wider date range or log another result.',
        secondary: onResetRange == null
            ? QuietButton(
                'Log a result',
                () => showLogSheet(
                  context,
                  request: LogRequest(exercise: exercise),
                ),
              )
            : QuietButton('Show all time', onResetRange),
      );
    }
    final summary = PerformanceSummary(
      data: data,
      measurement: exercise.measurement,
      style: style,
    );
    final stats = _StatLine(
      data: data,
      measurement: exercise.measurement,
      style: style,
    );
    final plot = _PerformancePlot(
      data: data,
      measurement: exercise.measurement,
      style: style,
      showTitle: showChartTitle,
      key: ValueKey(exercise.id),
    );
    if (!showChartTitle) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          summary,
          const Divider(),
          const SizedBox(height: Space.md),
          stats,
          const SizedBox(height: Space.md),
          const Divider(),
          const SizedBox(height: Space.sm),
          plot,
        ],
      );
    }
    final first = range.start ?? data.firstDay!;
    final last = range.end ?? data.latestDay!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          first == last
              ? fullDay(first)
              : '${fullDay(first)} to ${fullDay(last)}',
          style: context.type.bodySmall,
        ),
        const SizedBox(height: 14),
        ResponsiveSplit(
          stackGap: Space.md,
          main: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              summary,
              const Divider(),
              const SizedBox(height: 15),
              plot,
            ],
          ),
          side: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              stats,
              if (!exercise.measurement.usesWeight) ...[
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 14),
                SectionTitle(
                  'Total volume',
                  action: Text(
                    measure(data.total, exercise.measurement, style),
                    style: context.type.titleMedium,
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${data.setCount} ${data.setCount == 1 ? 'result' : 'results'} across ${data.days.length} '
                  '${data.days.length == 1 ? 'recorded date' : 'recorded dates'}',
                  style: context.type.bodySmall,
                ),
                PerformanceChart(
                  days: data.days,
                  metric: ChartMetric.volume,
                  measurement: exercise.measurement,
                  durationStyle: style,
                ),
              ],
              if (link)
                QuietButton(
                  'View exercise details',
                  () => context.push('/exercise/${exercise.id}'),
                  icon: LucideIcons.arrowUpRight,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class PerformanceSummary extends StatelessWidget {
  const PerformanceSummary({
    required this.data,
    required this.measurement,
    required this.style,
    super.key,
  });
  final Performance data;
  final Measurement measurement;
  final DurationStyle style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Wrap(
      spacing: 26,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              measure(data.latest!, measurement, style),
              style: context.type.headlineMedium,
            ),
            Text(
              'Latest result · ${shortDay(data.latestDay!)}',
              style: context.type.bodySmall,
            ),
          ],
        ),
        if (data.change case final delta?)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  changeText(delta, measurement, style),
                  if (data.percent case final percent?)
                    '${signed(percent.round())}%',
                ].join(' · '),
                style: context.type.titleMedium?.copyWith(
                  color: delta > 0 ? context.colors.green : context.colors.ink,
                ),
              ),
              Text('vs first result', style: context.type.bodySmall),
            ],
          )
        else
          Text('Not enough history to compare.', style: context.type.bodySmall),
      ],
    ),
  );
}

class _StatLine extends StatelessWidget {
  const _StatLine({
    required this.data,
    required this.measurement,
    required this.style,
  });
  final Performance data;
  final Measurement measurement;
  final DurationStyle style;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 28,
    runSpacing: 12,
    children: [
      for (final (label, value) in [
        ('First', data.first!),
        ('Latest', data.latest!),
        ('Best', data.best!),
      ])
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.type.bodySmall),
            Text(
              measure(value, measurement, style),
              style: context.type.titleMedium,
            ),
          ],
        ),
    ],
  );
}

class _PerformancePlot extends ConsumerStatefulWidget {
  const _PerformancePlot({
    required this.data,
    required this.measurement,
    required this.style,
    required this.showTitle,
    super.key,
  });
  final Performance data;
  final Measurement measurement;
  final DurationStyle style;
  final bool showTitle;

  @override
  ConsumerState<_PerformancePlot> createState() => _PerformancePlotState();
}

class _PerformancePlotState extends ConsumerState<_PerformancePlot> {
  ChartMetric _metric = ChartMetric.latest;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.showTitle) const SectionTitle('Performance'),
      MetricTabs(
        selected: _metric,
        onChanged: (metric) {
          if (_metric == metric) return;
          ref.read(actionsProvider).select();
          setState(() => _metric = metric);
        },
      ),
      PerformanceChart(
        days: widget.data.days,
        metric: _metric,
        measurement: widget.measurement,
        durationStyle: widget.style,
      ),
    ],
  );
}
