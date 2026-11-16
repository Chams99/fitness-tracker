import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'ui.dart';

class FormLayout extends StatelessWidget {
  const FormLayout({
    required this.title,
    required this.children,
    this.subtitle,
    this.leading,
    this.footer,
    this.width = Space.formWidth,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final String? subtitle;
  final Widget? leading, footer;
  final double width;

  @override
  Widget build(BuildContext context) => CollapsingPage(
    title: title,
    body: (controller, titleKey, _) => ScreenScroll(
      width: width,
      controller: controller,
      children: [
        ScreenHeading(
          title,
          top: 0,
          titleKey: titleKey,
          subtitle: subtitle,
          leading: leading,
        ),
        ...children,
      ],
    ),
    footer: footer == null ? null : KeyboardFooter(child: footer!),
  );
}

/// A secondary page whose compact title follows its scroll position.
class CollapsingPage extends StatefulWidget {
  const CollapsingPage({
    required this.title,
    required this.body,
    this.actions,
    this.avatar,
    this.footer,
    super.key,
  });

  final String? title;
  final Widget Function(
    ScrollController controller,
    Key titleKey,
    Widget avatarSlot,
  )
  body;
  final List<Widget>? actions;

  /// Built once at its expanded size and scaled as it moves into the toolbar.
  final Widget? avatar;
  final Widget? footer;

  @override
  State<CollapsingPage> createState() => _CollapsingPageState();
}

class _CollapsingPageState extends State<CollapsingPage> {
  static const _avatarSize = 74.0;
  static const _toolbarAvatarSize = 32.0;
  static const _titleFadeDistance = 24.0;

  final _controller = ScrollController();
  final _page = GlobalKey();
  final _toolbar = GlobalKey();
  final _title = GlobalKey();
  final _avatarFrom = GlobalKey();
  final _avatarTo = GlobalKey();
  final _geometry =
      ValueNotifier<
        ({
          double titleEnd,
          double toolbarBottom,
          Rect? avatarFrom,
          Rect? avatarTo,
        })?
      >(null);
  late final _motion = Listenable.merge([_controller, _geometry]);
  bool _measurementScheduled = false;

  @override
  void dispose() {
    _controller.dispose();
    _geometry.dispose();
    super.dispose();
  }

  double get _offset => _controller.hasClients ? _controller.offset : 0;

  void _measureAfterLayout() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      final page = _page.currentContext?.findRenderObject();
      if (page is! RenderBox || !page.hasSize) return;

      Rect? bounds(GlobalKey key) {
        final box = key.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize || !box.attached) return null;
        return box.localToGlobal(Offset.zero, ancestor: page) & box.size;
      }

      final title = bounds(_title);
      final toolbar = bounds(_toolbar);
      if (title == null || toolbar == null) return;
      // Store the body anchors as if the scroll were at zero. Scrolling can
      // then update the toolbar and avatar without measuring another frame.
      final unscroll = Offset(0, _offset);
      _geometry.value = (
        titleEnd: title.bottom + unscroll.dy - toolbar.bottom,
        toolbarBottom: toolbar.bottom,
        avatarFrom: bounds(_avatarFrom)?.shift(unscroll),
        avatarTo: bounds(_avatarTo),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _measureAfterLayout();
    return Stack(
      key: _page,
      children: [
        Scaffold(
          appBar: AppBar(
            key: _toolbar,
            automaticallyImplyLeading: false,
            leading: const BackButton(),
            leadingWidth: 56,
            centerTitle: widget.avatar == null,
            titleSpacing: widget.avatar == null ? null : 0,
            titleTextStyle: context.type.titleMedium,
            excludeHeaderSemantics: true,
            actions: widget.actions,
            title: widget.title == null
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.avatar != null) ...[
                        SizedBox.square(
                          key: _avatarTo,
                          dimension: _toolbarAvatarSize,
                        ),
                        const SizedBox(width: Space.sm),
                      ],
                      Flexible(
                        child: ListenableBuilder(
                          listenable: _motion,
                          child: Semantics(
                            container: true,
                            header: true,
                            label: widget.title,
                            excludeSemantics: true,
                            child: Text(
                              widget.title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          builder: (context, child) {
                            final end = _geometry.value?.titleEnd;
                            final reached = end != null && _offset >= end;
                            var progress = 0.0;
                            if (end != null &&
                                _controller.hasClients &&
                                _controller.position.maxScrollExtent >= end) {
                              progress = reduceMotion
                                  ? (reached ? 1.0 : 0.0)
                                  : (1 + (_offset - end) / _titleFadeDistance)
                                        .clamp(0.0, 1.0);
                            }
                            if (progress == 0 && widget.avatar == null) {
                              return const SizedBox.shrink();
                            }
                            // Keep room for the avatar while the title is hidden.
                            return IgnorePointer(
                              ignoring: progress == 0,
                              child: Opacity(
                                opacity: progress,
                                child: ExcludeSemantics(
                                  excluding: !reached,
                                  child: child,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          body: NotificationListener<LayoutChangedNotification>(
            onNotification: (_) {
              _measureAfterLayout();
              return false;
            },
            child: widget.body(
              _controller,
              _title,
              SizeChangedLayoutNotifier(
                child: SizedBox.square(
                  key: _avatarFrom,
                  dimension: _avatarSize,
                  child: widget.avatar == null
                      ? null
                      : ValueListenableBuilder(
                          valueListenable: _geometry,
                          builder: (context, geometry, child) =>
                              geometry?.avatarFrom == null
                              ? child!
                              : const SizedBox.shrink(),
                          child: const Skeleton(
                            width: _avatarSize,
                            height: _avatarSize,
                            circular: true,
                          ),
                        ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: widget.footer,
        ),
        if (widget.avatar case final avatar?)
          Positioned.fill(
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: _motion,
                child: RepaintBoundary(child: avatar),
                builder: (context, child) {
                  final geometry = _geometry.value;
                  final from = geometry?.avatarFrom;
                  final to = geometry?.avatarTo;
                  if (geometry == null ||
                      from == null ||
                      to == null ||
                      !_controller.hasClients) {
                    return const SizedBox();
                  }
                  final distance = from.top - to.top;
                  final available = _controller.position.maxScrollExtent;
                  final travel = distance.clamp(0.0, available);
                  final progress = travel > 0 && available >= geometry.titleEnd
                      ? (_offset / travel).clamp(0.0, 1.0)
                      : 0.0;
                  final blend = reduceMotion
                      ? (progress == 1 ? 1.0 : 0.0)
                      : Curves.easeInOut.transform(progress);
                  // Keep the avatar clear of the name in the profile row.
                  final enter = ((from.top - geometry.toolbarBottom) / distance)
                      .clamp(0.0, 1.0);
                  final drift = reduceMotion
                      ? blend
                      : Interval(
                          enter,
                          1,
                          curve: Curves.easeInOut,
                        ).transform(progress);
                  final left = from.left + (to.left - from.left) * drift;
                  final width = from.width + (to.width - from.width) * blend;
                  // Finish docking at the bottom even if the page has less
                  // scroll available than the avatar's vertical travel.
                  final lift = (distance - travel) * blend;
                  final top = progress == 1
                      ? to.top
                      : from.top - _offset - lift;
                  return ClipRect(
                    clipper: _AvatarClip(
                      reduceMotion && progress < 1 ? geometry.toolbarBottom : 0,
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: left,
                          top: top,
                          child: Transform.scale(
                            alignment: Alignment.topLeft,
                            scale: width / _avatarSize,
                            child: SizedBox.square(
                              dimension: _avatarSize,
                              child: child,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _AvatarClip extends CustomClipper<Rect> {
  const _AvatarClip(this.top);

  final double top;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, size.height);

  @override
  bool shouldReclip(_AvatarClip oldClipper) => oldClipper.top != top;
}
