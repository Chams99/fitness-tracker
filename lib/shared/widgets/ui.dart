import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageRoute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../domain/training.dart';

String shortDay(CalendarDay day) => DateFormat('d MMM').format(day.utc);
String fullDay(CalendarDay day) => DateFormat('d MMM yyyy').format(day.utc);
String weekday(CalendarDay day) => DateFormat('EEEE, d MMMM').format(day.utc);
String monthName(DateTime month) => DateFormat('MMMM yyyy').format(month);

String describeError(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) => switch (error) {
  TrackerException(:final message) => message,
  FormatException(:final message) => message,
  _ => fallback,
};

void announce(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.of(context);
  // Publish after the current frame. A successful save can pop its route
  // before the messenger lays out the notice on the destination screen.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!messenger.mounted) return;
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      snackBarAnimationStyle: AnimationStyle.noAnimation,
    );
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}

class AsyncPanel<T> extends StatelessWidget {
  const AsyncPanel(
    this.value, {
    required this.builder,
    this.retry,
    required this.loading,
    this.loadingLabel = 'Loading records',
    this.fadeContent = true,
    super.key,
  });
  final AsyncValue<T> value;
  final Widget Function(T) builder;
  final VoidCallback? retry;
  final Widget loading;
  final String loadingLabel;
  final bool fadeContent;

  @override
  Widget build(BuildContext context) {
    if (!value.hasValue && value.hasError) {
      return EmptyBlock(
        title: 'Couldn’t load this view',
        message: describeError(
          value.error!,
          fallback: 'Try reading your local records again.',
        ),
        action: retry == null ? null : 'Try again',
        onAction: retry,
      );
    }
    return SkeletonCrossfade(
      placeholder: loading,
      loadingLabel: loadingLabel,
      fadeContent: fadeContent,
      child: value.hasValue ? builder(value.requireValue) : null,
    );
  }
}

/// Shows [placeholder] until [child] becomes available.
class SkeletonCrossfade extends StatefulWidget {
  const SkeletonCrossfade({
    required this.placeholder,
    required this.child,
    this.loadingLabel,
    this.fadeContent = true,
    super.key,
  });

  final Widget placeholder;
  final Widget? child;
  final String? loadingLabel;

  /// When false, only [Skeleton] and [SkeletonDivider] paint with fading color.
  final bool fadeContent;

  @override
  State<SkeletonCrossfade> createState() => _SkeletonCrossfadeState();
}

class _SkeletonCrossfadeState extends State<SkeletonCrossfade> {
  Widget? _outgoingPlaceholder;

  @override
  void didUpdateWidget(SkeletonCrossfade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.child == null) {
      _outgoingPlaceholder = null;
    } else if (oldWidget.child == null) {
      _outgoingPlaceholder = oldWidget.placeholder;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.child == null) {
      return Semantics(
        label: widget.loadingLabel,
        excludeSemantics: true,
        child: widget.placeholder,
      );
    }
    final outgoing = _outgoingPlaceholder;
    final animate =
        outgoing != null && !MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => TweenAnimationBuilder<double>(
        tween: Tween(begin: animate ? 0 : 1, end: 1),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        builder: (_, animation, child) {
          final progress = animate ? animation : 1.0;
          return Stack(
            children: [
              // Keep the skeleton within the original slot's constraints.
              // Only the new content determines the size of the stack.
              if (outgoing != null && progress < 1)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  child: ConstrainedBox(
                    constraints: constraints,
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: widget.fadeContent
                            ? Opacity(opacity: 1 - progress, child: outgoing)
                            : _SkeletonFade(
                                opacity: 1 - progress,
                                child: outgoing,
                              ),
                      ),
                    ),
                  ),
                ),
              if (widget.fadeContent)
                Opacity(
                  // Keep real content visible from the first resolved frame.
                  opacity: .25 + .75 * progress,
                  alwaysIncludeSemantics: true,
                  child: child,
                )
              else
                child!,
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _SkeletonFade extends InheritedWidget {
  const _SkeletonFade({required this.opacity, required super.child});

  final double opacity;

  static Color colorOf(BuildContext context) {
    final color = context.colors.border;
    final fade = context.dependOnInheritedWidgetOfExactType<_SkeletonFade>();
    return fade == null
        ? color
        : color.withValues(alpha: color.a * fade.opacity);
  }

  @override
  bool updateShouldNotify(_SkeletonFade oldWidget) =>
      opacity != oldWidget.opacity;
}

class EmptyStateIllustration extends StatelessWidget {
  const EmptyStateIllustration(
    this.asset, {
    required this.maxWidth,
    required this.aspectRatio,
    super.key,
  });

  final String asset;
  final double maxWidth, aspectRatio;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: AspectRatio(
      aspectRatio: aspectRatio,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        frameBuilder: (_, child, frame, _) => SkeletonCrossfade(
          fadeContent: false,
          placeholder: AspectRatio(
            aspectRatio: aspectRatio,
            child: const Skeleton(height: double.infinity),
          ),
          child: frame == null ? null : child,
        ),
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    ),
  );
}

class Skeleton extends StatelessWidget {
  const Skeleton({
    this.width,
    required this.height,
    this.circular = false,
    super.key,
  });

  final double? width;
  final double height;
  final bool circular;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: _SkeletonFade.colorOf(context),
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(4),
      ),
    ),
  );
}

class SkeletonDivider extends StatelessWidget {
  const SkeletonDivider({this.height, super.key});

  final double? height;

  @override
  Widget build(BuildContext context) =>
      Divider(height: height, color: _SkeletonFade.colorOf(context));
}

/// Uses a real line of text to reserve the correct height at any text size.
class SkeletonText extends StatelessWidget {
  const SkeletonText({required this.width, this.style, super.key});

  final double width;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [
        Opacity(opacity: 0, child: Text(' ', style: style, maxLines: 1)),
        Positioned.fill(
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            heightFactor: .58,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: LayoutBuilder(
                builder: (_, constraints) =>
                    Skeleton(width: width, height: constraints.maxHeight),
              ),
            ),
          ),
        ),
        SizedBox(width: width),
      ],
    ),
  );
}

class SkeletonRows extends StatelessWidget {
  const SkeletonRows({this.count = 3, this.rowHeight = 64, super.key});

  final int count;
  final double rowHeight;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < count; index++) ...[
        SizedBox(
          height: rowHeight,
          child: Row(
            children: [
              const Skeleton(width: 26, height: 26, circular: true),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(width: index.isEven ? 124 : 94, height: 12),
                    const SizedBox(height: 7),
                    const Skeleton(width: 74, height: 8),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              const Skeleton(width: 44, height: 12),
            ],
          ),
        ),
        const SkeletonDivider(height: 1),
      ],
    ],
  );
}

class EmptyBlock extends StatelessWidget {
  const EmptyBlock({
    required this.title,
    required this.message,
    this.action,
    this.onAction,
    this.icon,
    this.secondary,
    super.key,
  });
  final String title, message;
  final String? action;
  final VoidCallback? onAction;
  final IconData? icon;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.input,
                borderRadius: BorderRadius.circular(Space.radius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(icon, size: 24, color: context.colors.green),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
        ],
        Text(title, style: context.type.titleLarge),
        const SizedBox(height: Space.sm),
        Text(
          message,
          style: context.type.bodyLarge?.copyWith(color: context.colors.muted),
        ),
        if (action != null) ...[
          const SizedBox(height: Space.md),
          FilledButton(onPressed: onAction, child: Text(action!)),
        ],
        ?secondary,
      ],
    ),
  );
}

class ScreenScroll extends StatelessWidget {
  const ScreenScroll({
    required this.children,
    this.primary = false,
    this.width = Space.formWidth,
    this.controller,
    this.scrollKey,
    super.key,
  });

  final List<Widget> children;
  final bool primary;
  final double width;
  final ScrollController? controller;
  final Key? scrollKey;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: primary,
    bottom: false,
    child: LayoutBuilder(
      builder: (context, limits) {
        final side = Space.pageInset(limits.maxWidth);
        return CustomScrollView(
          key: scrollKey,
          controller: controller,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            for (final child in children)
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: side),
                      child: SizedBox(width: double.infinity, child: child),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: primary
                    ? 110 + MediaQuery.paddingOf(context).bottom
                    : 28 + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        );
      },
    ),
  );
}

class ResponsiveSplit extends StatelessWidget {
  const ResponsiveSplit({
    required this.main,
    required this.side,
    this.gap = Space.xxl,
    this.stackGap = Space.lg,
    super.key,
  });
  final Widget main, side;
  final double gap, stackGap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= Space.split
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: main),
              SizedBox(width: gap),
              Expanded(flex: 5, child: side),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              main,
              SizedBox(height: stackGap),
              side,
            ],
          ),
  );
}

class ScreenHeading extends StatelessWidget {
  const ScreenHeading(
    this.title, {
    this.subtitle,
    this.subtitleLoading = false,
    this.fadeSubtitle = true,
    this.action,
    this.leading,
    this.top = Space.md,
    this.bottom = Space.md,
    super.key,
  });
  final String title;
  final String? subtitle;
  final bool subtitleLoading;
  final bool fadeSubtitle;
  final Widget? action, leading;
  final double top, bottom;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: bottom),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: Space.sm)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: context.type.headlineLarge),
              ),
              if (subtitle != null || subtitleLoading) ...[
                const SizedBox(height: Space.xs),
                SizedBox(
                  width: double.infinity,
                  child: SkeletonCrossfade(
                    fadeContent: fadeSubtitle,
                    placeholder: SkeletonText(
                      width: 140,
                      style: context.type.bodyMedium,
                    ),
                    child: subtitle == null
                        ? null
                        : Text(
                            subtitle!,
                            style: context.type.bodyMedium?.copyWith(
                              color: context.colors.muted,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: Space.sm), action!],
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {this.action, super.key});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, limits) => Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: context.type.titleLarge),
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: Space.sm),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: limits.maxWidth * .42),
            child: action!,
          ),
        ],
      ],
    ),
  );
}

class QuietButton extends StatelessWidget {
  const QuietButton(
    this.label,
    this.onPressed, {
    this.icon,
    this.danger = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: danger ? context.colors.danger : context.colors.green,
      alignment: AlignmentDirectional.centerStart,
    ),
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
        Flexible(child: Text(label)),
      ],
    ),
  );
}

class FilterButton extends StatelessWidget {
  const FilterButton(
    this.label,
    this.onPressed, {
    this.prominent = false,
    this.leading,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool prominent;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      alignment: AlignmentDirectional.centerStart,
      padding: EdgeInsets.zero,
      foregroundColor: context.colors.ink,
    ),
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: Space.sm)],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: prominent
                ? context.type.titleLarge
                : context.type.labelLarge,
          ),
        ),
        const SizedBox(width: Space.sm),
        const Icon(LucideIcons.chevronDown, size: 16),
      ],
    ),
  );
}

class RoundControl extends StatelessWidget {
  const RoundControl(this.icon, this.label, this.onPressed, {super.key});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    icon: Icon(icon, size: 21),
  );
}

Route<T> platformPageRoute<T>(BuildContext context, WidgetBuilder builder) =>
    Theme.of(context).platform == TargetPlatform.iOS
    ? CupertinoPageRoute<T>(builder: builder)
    : MaterialPageRoute<T>(builder: builder);

PreferredSizeWidget secondaryBar(
  BuildContext context, {
  String? title,
  List<Widget>? actions,
}) => AppBar(
  automaticallyImplyLeading: false,
  centerTitle: title != null,
  title: title == null
      ? null
      : Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
  titleTextStyle: context.type.titleMedium,
  leading: BackButton(onPressed: () => Navigator.maybePop(context)),
  leadingWidth: 56,
  actions: actions,
);

class ActionFooter extends StatelessWidget {
  const ActionFooter({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel = 'Saving…',
    this.secondary,
    this.width = Space.formWidth,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final String busyLabel;
  final Widget? secondary;
  final double width;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.only(bottom: 10),
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: LayoutBuilder(
          builder: (context, limits) {
            final side = Space.pageInset(limits.maxWidth);
            return Padding(
              padding: EdgeInsets.fromLTRB(side, Space.sm, side, 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: busy ? null : onPressed,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Visibility(
                          visible: !busy,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: Text(label, textAlign: TextAlign.center),
                        ),
                        if (busy)
                          Semantics(
                            liveRegion: true,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const ExcludeSemantics(child: ActionProgress()),
                                const SizedBox(width: Space.sm),
                                Flexible(
                                  child: Text(
                                    busyLabel,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (secondary != null) Center(child: secondary!),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

class ActionProgress extends StatelessWidget {
  const ActionProgress({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: MediaQuery.disableAnimationsOf(context)
        ? const Icon(LucideIcons.hourglass, size: 16)
        : CircularProgressIndicator(
            strokeWidth: 2,
            color: context.colors.muted,
          ),
  );
}

class ActionProgressLine extends StatelessWidget {
  const ActionProgressLine({
    required this.busy,
    required this.label,
    super.key,
  });

  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 2,
    child: busy
        ? Semantics(
            label: label,
            liveRegion: true,
            child: MediaQuery.disableAnimationsOf(context)
                ? ColoredBox(color: context.colors.green)
                : const LinearProgressIndicator(minHeight: 2),
          )
        : null,
  );
}

class FormLayout extends StatelessWidget {
  const FormLayout({
    required this.title,
    required this.children,
    this.footer,
    this.width = Space.formWidth,
    super.key,
  });
  final String title;
  final List<Widget> children;
  final Widget? footer;
  final double width;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: secondaryBar(context, title: title),
    body: ScreenScroll(width: width, children: children),
    bottomNavigationBar: footer == null ? null : KeyboardFooter(child: footer!),
  );
}

/// Place the footer above the keyboard and let Scaffold place notices above it.
class KeyboardFooter extends StatelessWidget {
  const KeyboardFooter({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: child,
  );
}

class RowLink extends StatelessWidget {
  const RowLink({
    required this.title,
    this.subtitle,
    this.detail,
    this.detailStyle,
    this.icon,
    this.onTap,
    this.leading,
    this.separator = true,
    this.showChevron = true,
    super.key,
  });
  final String title;
  final String? subtitle, detail;
  final TextStyle? detailStyle;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool separator, showChevron;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Space.target),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: context.type.titleSmall),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: context.type.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  if (detail != null)
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.only(left: Space.sm),
                        child: Text(
                          detail!,
                          style: detailStyle ?? context.type.bodySmall,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ),
                  if (icon != null || (onTap != null && showChevron)) ...[
                    const SizedBox(width: Space.sm),
                    Icon(
                      icon ?? LucideIcons.chevronRight,
                      size: 18,
                      color: context.colors.muted,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      if (separator) const Divider(),
    ],
  );
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.trailing,
    title: Text(title, style: context.type.titleSmall),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: context.type.bodySmall),
    value: value,
    onChanged: onChanged,
  );
}

class FormProblem extends StatelessWidget {
  const FormProblem(this.message, {super.key});
  final String? message;
  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Semantics(
            liveRegion: true,
            child: Text(
              message!,
              style: context.type.bodyMedium?.copyWith(
                color: context.colors.danger,
              ),
            ),
          ),
        );
}

class LargeNumberField extends StatelessWidget {
  const LargeNumberField({
    required this.label,
    required this.controller,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
    this.decimal = false,
    this.hint = '0',
    this.fontSize = 56,
    this.next = false,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    super.key,
  });

  final String label, hint;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled, autofocus, decimal, next;
  final double fontSize;
  final ValueChanged<String>? onChanged, onSubmitted;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final style = context.type.headlineLarge!.copyWith(fontSize: fontSize);
    return Semantics(
      label: label,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: autofocus,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        validator: validator,
        style: style,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        textInputAction: next ? TextInputAction.next : TextInputAction.done,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: style.copyWith(color: context.colors.muted),
          contentPadding: const EdgeInsets.symmetric(vertical: Space.xs),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          errorMaxLines: 3,
        ),
      ),
    );
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String label,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: destructive
                  ? context.colors.danger
                  : context.colors.green,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    ) ??
    false;

Future<CalendarDay?> pickDay(
  BuildContext context,
  CalendarDay current, {
  required CalendarDay latest,
  CalendarDay first = CalendarDay.earliest,
  String? title,
}) async {
  final date = await showDatePicker(
    context: context,
    initialDate:
        (current.isBefore(first)
                ? first
                : current.isAfter(latest)
                ? latest
                : current)
            .local,
    firstDate: first.local,
    lastDate: latest.local,
    helpText: title,
  );
  return date == null ? null : CalendarDay.fromDate(date);
}

class ChartSelection extends StatelessWidget {
  const ChartSelection({
    required this.label,
    required this.date,
    required this.value,
    super.key,
  });

  final String label, date, value;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: '$label: $date, $value',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.type.bodySmall),
          Text(
            value,
            style: context.type.headlineSmall?.copyWith(
              color: context.colors.green,
              fontFeatures: numeric,
            ),
          ),
          Text(date, style: context.type.bodySmall),
        ],
      ),
    ),
  );
}

Future<T?> chooseOption<T extends Object>(
  BuildContext context,
  String title,
  List<({T value, String label, String? subtitle})> options, {
  T? selected,
  String? description,
  Widget? Function(T value, String label)? leading,
  String? footerText,
  String? footerActionLabel,
  VoidCallback? onFooterAction,
}) => showModalBottomSheet<T>(
  useRootNavigator: true,
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: BoxConstraints(
    maxWidth: 540,
    maxHeight: MediaQuery.sizeOf(context).height * .78,
  ),
  builder: (context) => SafeArea(
    top: false,
    child: CustomScrollView(
      shrinkWrap: true,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.type.titleLarge),
                      if (description != null) ...[
                        const SizedBox(height: Space.xs),
                        Text(description, style: context.type.bodySmall),
                      ],
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = option.value == selected;
                  return Semantics(
                    selected: isSelected,
                    child: RowLink(
                      title: option.label,
                      subtitle: option.subtitle,
                      leading: leading?.call(option.value, option.label),
                      icon: isSelected
                          ? LucideIcons.check
                          : LucideIcons.chevronRight,
                      onTap: () => Navigator.pop(context, option.value),
                    ),
                  );
                },
              ),
              if (footerText != null ||
                  (footerActionLabel != null && onFooterAction != null))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (footerText != null)
                          Text(footerText, style: context.type.bodySmall),
                        if (footerActionLabel != null &&
                            onFooterAction != null) ...[
                          const SizedBox(height: Space.sm),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onFooterAction();
                              },
                              icon: const Icon(LucideIcons.plus),
                              label: Text(footerActionLabel),
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
      ],
    ),
  ),
);

InputDecoration lineInput(
  BuildContext context, {
  required String label,
  String? error,
  String? suffix,
}) {
  final line = UnderlineInputBorder(
    borderSide: BorderSide(color: context.colors.border),
  );
  final errorLine = UnderlineInputBorder(
    borderSide: BorderSide(color: context.colors.danger),
  );
  return InputDecoration(
    filled: false,
    labelText: label,
    labelStyle: context.type.bodyMedium?.copyWith(color: context.colors.muted),
    floatingLabelBehavior: FloatingLabelBehavior.never,
    errorText: error,
    suffixText: suffix,
    contentPadding: const EdgeInsets.symmetric(vertical: Space.sm),
    border: line,
    enabledBorder: line,
    focusedBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: context.colors.green, width: 1.5),
    ),
    errorBorder: errorLine,
    focusedErrorBorder: errorLine,
  );
}

class SearchInput extends StatelessWidget {
  const SearchInput({
    required this.hint,
    this.onChanged,
    this.autofocus = false,
    this.controller,
    super.key,
  });
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: Icon(
        LucideIcons.search,
        size: 18,
        color: context.colors.muted,
      ),
    ),
  );
}

class ProtectDraft<T> extends StatefulWidget {
  const ProtectDraft({
    required this.dirty,
    required this.busy,
    required this.child,
    super.key,
  });
  final bool dirty, busy;
  final Widget child;

  @override
  State<ProtectDraft<T>> createState() => _ProtectDraftState<T>();
}

class _ProtectDraftState<T> extends State<ProtectDraft<T>> {
  bool _asking = false;

  @override
  Widget build(BuildContext context) => PopScope<T>(
    canPop: !widget.dirty && !widget.busy,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || widget.busy || !widget.dirty || _asking) return;
      _asking = true;
      final discard = await confirmAction(
        context,
        title: 'Discard changes?',
        message: 'Your unsaved changes will be lost.',
        label: 'Discard',
        destructive: true,
      );
      _asking = false;
      if (context.mounted && discard) Navigator.pop(context);
    },
    child: widget.child,
  );
}
