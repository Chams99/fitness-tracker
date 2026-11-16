import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../shared/domain/body_metrics.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.photo,
    required this.preset,
    this.size = 74,
    this.fallback,
    super.key,
  });

  final Uint8List? photo;
  final AvatarPreset preset;
  final double size;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final silhouette =
        fallback ??
        ColoredBox(
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
