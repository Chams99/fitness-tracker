import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/branding.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/body_metrics.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';
import 'appearance_picker.dart';
import 'measurement_input.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const latestFilter = (limit: 1, since: null);
    final profile = ref.watch(profileProvider);
    final weights = weighInsProvider(latestFilter);
    final latest = ref.watch(weights);
    return Scaffold(
      appBar: secondaryBar(context),
      body: ScreenScroll(
        children: [
          const ScreenHeading('Profile', top: 0),
          _ProfileIdentity(profile: profile),
          const SizedBox(height: Space.xl),
          const SectionTitle('Body measurements'),
          const SizedBox(height: Space.sm),
          _Measurements(profile: profile, weighIns: latest),
          if (latest.hasError && !latest.hasValue)
            QuietButton('Retry weigh-ins', () => ref.invalidate(weights)),
          const SizedBox(height: Space.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: () => context.push('/profile/weigh-in'),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('Log weight'),
            ),
          ),
          const SizedBox(height: Space.xl),
          const _Preferences(),
          const SizedBox(height: Space.lg),
          RowLink(
            title: 'Manage exercises',
            leading: const Icon(LucideIcons.dumbbell, size: 20),
            onTap: () => context.push('/exercises'),
          ),
          RowLink(
            title: 'Your data',
            leading: const Icon(LucideIcons.database, size: 20),
            onTap: () => context.push('/profile/data'),
          ),
          const _AboutFooter(),
        ],
      ),
    );
  }
}

class _ProfileIdentity extends ConsumerWidget {
  const _ProfileIdentity({required this.profile});
  final AsyncValue<LocalProfile> profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameStyle = context.type.titleLarge;
    final value = profile.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SkeletonCrossfade(
              placeholder: const Skeleton(
                width: 74,
                height: 74,
                circular: true,
              ),
              child: value == null && !profile.hasError
                  ? null
                  : ProfileAvatar(
                      photo: value?.photo,
                      preset: value?.avatarPreset ?? AvatarPreset.anonymous,
                    ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: AsyncPanel(
                      profile,
                      loadingLabel: 'Loading profile',
                      loading: SkeletonText(width: 100, style: nameStyle),
                      retry: () => ref.invalidate(profileProvider),
                      builder: (value) => Text(
                        value.details.displayName ?? 'You',
                        style: nameStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  QuietButton(
                    'Edit profile',
                    () => context.push('/profile/edit'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Measurements extends StatelessWidget {
  const _Measurements({required this.profile, required this.weighIns});
  final AsyncValue<LocalProfile> profile;
  final AsyncValue<List<WeighIn>> weighIns;

  @override
  Widget build(BuildContext context) {
    final details = profile.value?.details;
    final height = details?.heightMillimeters;
    final latest = weighIns.value?.firstOrNull;
    final heightValue = _Measurement(
      label: 'Height',
      value: switch (details) {
        null => profile.hasError ? 'Unavailable' : null,
        _ =>
          height == null
              ? 'Add height'
              : heightText(context, height, details.heightUnit),
      },
      onTap: () => context.push('/profile/edit'),
    );
    final weightValue = _Measurement(
      label: 'Body weight',
      value: switch (latest) {
        null when weighIns.hasValue => 'No weigh-ins yet',
        null when weighIns.hasError => 'Unavailable',
        null => null,
        _ when details != null => weightText(
          context,
          latest.grams,
          details.weightUnit,
        ),
        _ => profile.hasError ? 'Unavailable' : null,
      },
      date: latest == null ? null : fullDay(latest.day),
      reserveDate: true,
      onTap: () => context.push('/profile/weight'),
    );
    return LayoutBuilder(
      builder: (context, limits) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (limits.maxWidth / scale < 290) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heightValue, const Divider(), weightValue],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heightValue),
            const SizedBox(width: Space.lg),
            Expanded(child: weightValue),
          ],
        );
      },
    );
  }
}

class _Measurement extends StatelessWidget {
  const _Measurement({
    required this.label,
    required this.value,
    required this.onTap,
    this.date,
    this.reserveDate = false,
  });

  final String label;
  final String? value, date;
  final bool reserveDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(child: Text(label, style: context.type.bodyMedium)),
                const SizedBox(width: Space.xs),
                Icon(
                  LucideIcons.chevronRight,
                  size: 15,
                  color: context.colors.muted,
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            SizedBox(
              width: double.infinity,
              child: SkeletonCrossfade(
                loadingLabel: 'Loading $label',
                placeholder: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 82, style: context.type.titleMedium),
                    if (reserveDate) ...[
                      const SizedBox(height: Space.xs),
                      SkeletonText(width: 65, style: context.type.bodySmall),
                    ],
                  ],
                ),
                child: value == null
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(value!, style: context.type.titleMedium),
                          if (reserveDate) ...[
                            const SizedBox(height: Space.xs),
                            Semantics(
                              excludeSemantics: date == null,
                              child: Text(
                                date ?? ' ',
                                style: context.type.bodySmall,
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Preferences extends ConsumerStatefulWidget {
  const _Preferences();

  @override
  ConsumerState<_Preferences> createState() => _PreferencesState();
}

class _PreferencesState extends ConsumerState<_Preferences> {
  bool _saving = false;
  String? _problem;

  String _durationExample(DurationStyle style) =>
      measure(90, Measurement.duration, style);

  Future<void> _save(Preferences preferences) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      await ref.read(repositoryProvider).savePreferences(preferences);
    } catch (error) {
      if (mounted) {
        setState(
          () => _problem = describeError(
            error,
            fallback: 'Couldn’t save this preference.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _appearance(Preferences prefs) async {
    final selected = await pickAppearance(context, prefs.appearance);
    if (mounted && selected != null && selected != prefs.appearance) {
      await _save((
        appearance: selected,
        duration: prefs.duration,
        haptics: prefs.haptics,
      ));
    }
  }

  Future<void> _duration(Preferences prefs) async {
    final selected = await chooseOption<DurationStyle>(
      context,
      'Duration display',
      [
        for (final value in DurationStyle.values)
          (
            value: value,
            label: value == DurationStyle.clock
                ? 'Minutes and seconds'
                : 'Seconds',
            subtitle: _durationExample(value),
          ),
      ],
      selected: prefs.duration,
    );
    if (mounted && selected != null && selected != prefs.duration) {
      await _save((
        appearance: prefs.appearance,
        duration: selected,
        haptics: prefs.haptics,
      ));
    }
  }

  @override
  Widget build(BuildContext context) => AsyncPanel(
    ref.watch(preferencesProvider),
    loading: const SkeletonRows(rowHeight: 50),
    retry: () => ref.invalidate(preferencesProvider),
    builder: (prefs) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Preferences'),
        const SizedBox(height: Space.xs),
        RowLink(
          title: 'Appearance',
          detail: appearanceLabel(prefs.appearance),
          onTap: _saving ? null : () => _appearance(prefs),
        ),
        RowLink(
          title: 'Duration display',
          detail: _durationExample(prefs.duration),
          onTap: _saving ? null : () => _duration(prefs),
        ),
        SwitchRow(
          value: prefs.haptics,
          title: 'Haptics',
          onChanged: _saving
              ? null
              : (value) => _save((
                  appearance: prefs.appearance,
                  duration: prefs.duration,
                  haptics: value,
                )),
        ),
        FormProblem(_problem),
      ],
    ),
  );
}

class _AboutFooter extends ConsumerWidget {
  const _AboutFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadata = ref.watch(appBuildProvider);
    final build = metadata.value;
    final version = build == null || build.version.isEmpty
        ? null
        : build.number.isEmpty
        ? 'Version ${build.version}'
        : 'Version ${build.version} (${build.number})';
    return Padding(
      padding: const EdgeInsets.only(top: Space.xxl),
      child: Column(
        children: [
          Image.asset(
            Branding.mark,
            width: 42,
            height: 42,
            color: context.colors.ink,
            excludeFromSemantics: true,
          ),
          const SizedBox(height: Space.sm),
          Text(Branding.name, style: context.type.titleSmall),
          const SizedBox(height: Space.xs),
          SkeletonCrossfade(
            placeholder: SkeletonText(width: 94, style: context.type.bodySmall),
            child: !metadata.hasValue && !metadata.hasError
                ? null
                : Text(
                    version ?? 'Version unavailable',
                    style: context.type.bodySmall,
                    textAlign: TextAlign.center,
                  ),
          ),
          QuietButton(
            'Licenses',
            () => showLicensePage(
              context: context,
              applicationName: Branding.name,
              applicationVersion: version,
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.photo,
    required this.preset,
    this.size = 74,
    super.key,
  });

  final Uint8List? photo;
  final AvatarPreset preset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final silhouette = ColoredBox(
      color: context.colors.add,
      child: Center(
        child: Icon(
          Icons.person,
          size: size * .82,
          color: TrackerColors.light.ink,
        ),
      ),
    );
    final presetImage = preset == AvatarPreset.anonymous
        ? silhouette
        : _resolvedImage(
            AssetImage('assets/avatars/${preset.name}.webp'),
            silhouette,
          );
    return ExcludeSemantics(
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: photo == null
              ? presetImage
              : _resolvedImage(MemoryImage(photo!), presetImage),
        ),
      ),
    );
  }

  Widget _resolvedImage(ImageProvider image, Widget waiting) => Image(
    image: image,
    fit: BoxFit.cover,
    frameBuilder: (context, child, frame, synchronous) {
      if (synchronous || MediaQuery.disableAnimationsOf(context)) {
        return frame == null ? waiting : child;
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          waiting,
          AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: child,
          ),
        ],
      );
    },
    errorBuilder: (_, _, _) => waiting,
  );
}
