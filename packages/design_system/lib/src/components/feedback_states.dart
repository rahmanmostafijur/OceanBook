import 'package:flutter/material.dart';

import '../tokens/app_motion.dart';
import '../tokens/app_shapes.dart';
import '../tokens/app_spacing.dart';

/// Empty collection: icon, clear explanation and the relevant next action. Never a blank screen.
class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.title, this.message, this.action, super.key});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.maxFormWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(icon, size: AppSizes.iconHero, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[const SizedBox(height: AppSpacing.xl), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A designed error: what happened, in the user's language, and a way forward.
class ErrorState extends StatelessWidget {
  const ErrorState({required this.title, required this.message, this.onRetry, this.retryLabel, super.key});

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(retryLabel ?? 'Retry'),
            ),
    );
  }
}

/// Content-shaped placeholder while loading. Pulses unless the user prefers reduced motion.
class Skeleton extends StatefulWidget {
  const Skeleton({this.width, this.height = 16, this.radius = AppShapes.extraSmall, super.key});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Loading',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(scheme.surfaceContainerHigh, scheme.surfaceContainerHighest, _controller.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}
