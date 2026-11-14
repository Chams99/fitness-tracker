import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/exercise_icon.dart';
import '../../shared/widgets/ui.dart';
import '../logging/log_page.dart';

class EntryRow extends ConsumerStatefulWidget {
  const EntryRow({
    required this.entry,
    required this.exercise,
    this.showDate = false,
    this.compact = false,
    super.key,
  });
  final Entry entry;
  final Exercise exercise;
  final bool showDate, compact;

  @override
  ConsumerState<EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends ConsumerState<EntryRow> {
  bool _busy = false;

  Future<void> _action(String action) async {
    final entry = widget.entry;
    if (action == 'edit') {
      await context.push(
        '/log',
        extra: LogRequest(exercise: widget.exercise, entry: entry),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final confirmed = await confirmAction(
        context,
        title: 'Delete this entry?',
        message:
            'This removes all ${entry.sets.length} sets and the note for ${widget.exercise.name} on ${fullDay(entry.day)}.',
        label: 'Delete entry',
        destructive: true,
      );
      if (!mounted || !confirmed) return;
      await ref.read(repositoryProvider).deleteEntry(entry.id);
      if (mounted) announce(context, 'Entry deleted.');
    } catch (error) {
      if (mounted) announce(context, describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDetails() async {
    final entry = widget.entry, exercise = widget.exercise;
    final style = ref.read(durationProvider);
    final showSets = exercise.trackSets || entry.sets.length > 1;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxWidth: 540,
        maxHeight: MediaQuery.sizeOf(context).height * .82,
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ExerciseIcon(exercise.name),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(exercise.name, style: context.type.titleLarge),
                  ),
                  IconButton(
                    tooltip: 'Close activity details',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  Text(fullDay(entry.day), style: context.type.bodySmall),
                  Text(
                    exercise.measurement.label,
                    style: context.type.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              if (showSets) ...[
                const SectionTitle('Recorded sets'),
                for (final set in entry.sets)
                  RowLink(
                    title: 'Set ${set.position + 1}',
                    detail: measure(
                      set.value,
                      exercise.measurement,
                      style,
                      reps: set.reps,
                    ),
                    showChevron: false,
                  ),
              ] else ...[
                const SectionTitle('Recorded result'),
                Text(
                  measure(
                    entry.sets.single.value,
                    exercise.measurement,
                    style,
                    reps: entry.sets.single.reps,
                  ),
                  style: context.type.headlineSmall,
                ),
              ],
              if (entry.notes case final note?) ...[
                const SizedBox(height: Space.sm),
                const SectionTitle('Note'),
                Text(note, style: context.type.bodyMedium),
              ],
              const SizedBox(height: Space.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _action('edit');
                  },
                  icon: const Icon(LucideIcons.pencil),
                  label: const Text('Edit entry'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = ref.watch(durationProvider);
    final entry = widget.entry, exercise = widget.exercise;
    final m = exercise.measurement;
    final showSets = exercise.trackSets || entry.sets.length > 1;
    final summary = showSets
        ? '${entry.sets.length} ${entry.sets.length == 1 ? 'set' : 'sets'}'
              '${m.usesWeight ? '' : ' · ${measure(entry.total, m, style)} total'}'
        : null;
    if (widget.compact) {
      final show = entry.sets
          .take(4)
          .map((s) => measure(s.value, m, style, reps: s.reps))
          .join(' · ');
      return Row(
        children: [
          Expanded(
            child: RowLink(
              title: exercise.name,
              leading: ExerciseIcon(exercise.name),
              subtitle: widget.showDate
                  ? '${shortDay(entry.day)}${summary == null ? '' : ' · $summary'}'
                  : summary,
              detail: '$show${entry.sets.length > 4 ? ' …' : ''}',
              detailStyle: context.type.labelLarge,
              showChevron: false,
              onTap: _showDetails,
            ),
          ),
          IconButton(
            tooltip: 'Edit entry',
            onPressed: () => _action('edit'),
            icon: const Icon(LucideIcons.pencil, size: 18),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ExerciseIcon(exercise.name),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.showDate ? fullDay(entry.day) : exercise.name,
                    style: context.type.titleMedium,
                  ),
                  if (widget.showDate || summary != null)
                    Text(
                      [
                        if (widget.showDate) exercise.name,
                        ?summary,
                      ].join(' · '),
                      style: context.type.bodySmall,
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Options for ${exercise.name} on ${fullDay(entry.day)}',
              enabled: !_busy,
              icon: const Icon(LucideIcons.ellipsis, size: 20),
              onSelected: _action,
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit entry')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Delete entry',
                    style: TextStyle(color: context.colors.danger),
                  ),
                ),
              ],
            ),
          ],
        ),
        Wrap(
          spacing: 18,
          runSpacing: 9,
          children: [
            for (final set in entry.sets)
              Text(
                measure(set.value, m, style, reps: set.reps),
                style: context.type.titleMedium,
                semanticsLabel:
                    '${showSets ? 'Set ${set.position + 1}: ' : ''}'
                    '${measure(set.value, m, style, accessible: true, reps: set.reps)}',
              ),
          ],
        ),
        if (entry.sets.length > 1) ...[
          const SizedBox(height: 7),
          Text(
            'Latest ${measure(entry.latest, m, style, reps: entry.sets.last.reps)} · Best ${measure(entry.best, m, style)}',
            style: context.type.bodySmall,
          ),
        ],
        if (entry.notes case final note?) ...[
          const SizedBox(height: 7),
          Text(note, style: context.type.bodyMedium),
        ],
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 5),
      ],
    );
  }
}
