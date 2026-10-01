import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_shapes.dart';
import '../tokens/app_spacing.dart';

/// Book cover at a fixed 2:3 ratio (no layout shift while loading). Missing or failed images show a
/// tonal placeholder with the title, so the grid never has holes.
class BookCover extends StatelessWidget {
  const BookCover({required this.title, this.imageUrl, this.width, this.semanticLabel, super.key});

  final String title;
  final String? imageUrl;
  final double? width;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Decorative: the cover's own Semantics label already names the book (no double announcement).
    final placeholder = ExcludeSemantics(
      child: ColoredBox(
        color: scheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Center(
            child: Text(
              title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ),
      ),
    );

    final url = imageUrl;
    return Semantics(
      image: true,
      label: semanticLabel ?? title,
      child: SizedBox(
        width: width,
        child: AspectRatio(
          aspectRatio: AppSizes.coverAspectRatio,
          child: ClipRRect(
            borderRadius: AppShapes.cover,
            child: url == null
                ? placeholder
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    frameBuilder: (context, child, frame, _) => frame == null ? placeholder : child,
                    errorBuilder: (_, _, _) => placeholder,
                  ),
          ),
        ),
      ),
    );
  }
}

enum AccessBadge { free, premium, preview }

/// Free / premium status as a restrained chip (never a banner). The state comes from the server's
/// `access` block: the client only displays it.
class AccessChip extends StatelessWidget {
  const AccessChip({required this.badge, required this.label, super.key});

  final AccessBadge badge;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final (Color bg, Color fg, IconData icon) = switch (badge) {
      AccessBadge.free => (semantic.successContainer, semantic.onSuccessContainer, Icons.lock_open_outlined),
      AccessBadge.premium => (semantic.premiumContainer, semantic.onPremiumContainer, Icons.workspace_premium_outlined),
      AccessBadge.preview => (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.visibility_outlined),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppShapes.extraSmall)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSizes.iconSmall - 4, color: fg), // icon + text: status never relies on colour
          const SizedBox(width: AppSpacing.xxs),
          // Narrow tiles (rails at 140 dp, 200 % text) ellipsize rather than overflow.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section title with an optional "See all" action, used for home rails and detail sections.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.actionLabel, this.onAction, super.key});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          ),
          if (actionLabel != null && onAction != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
