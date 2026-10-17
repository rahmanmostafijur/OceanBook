import 'dart:ui' show ImageFilter;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../domain/library_book.dart';

const int _collapsedSynopsisLines = 4;
const double _coverWidth = 148;
const double _backdropBlur = 28;

/// Opens the details sheet for [book]. The sheet drags between 60 % and 95 % of the screen and
/// pops itself before navigating to the reader.
Future<void> showBookDetailsSheet(BuildContext context, LibraryBook book) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  constraints: const BoxConstraints(maxWidth: AppSizes.maxReadableWidth),
  shape: AppShapes.bottomSheet,
  clipBehavior: Clip.antiAlias,
  builder: (_) => BookDetailsSheet(book: book),
);

class BookDetailsSheet extends StatelessWidget {
  const BookDetailsSheet({required this.book, super.key});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = ObLocalizations.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, controller) => Stack(
        children: [
          Positioned.fill(child: _BlurredBackdrop(book: book)),
          Column(
            children: [
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.xl),
                  children: [
                    Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: AppShapes.cover,
                          boxShadow: [
                            BoxShadow(
                              color: theme.shadowColor.withValues(alpha: 0.3),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: BookCover(title: book.title, imageUrl: book.coverUrl, width: _coverWidth),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Semantics(
                      header: true,
                      child: Text(book.title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      book.author,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Center(child: RatingStars(rating: book.rating)),
                    const SizedBox(height: AppSpacing.xl),
                    SectionHeaderLabel(l10n.bookSynopsis),
                    ExpandableSynopsis(text: book.synopsis),
                  ],
                ),
              ),
              _PinnedAction(book: book),
            ],
          ),
        ],
      ),
    );
  }
}

/// The primary action stays reachable without scrolling the sheet.
class _PinnedAction extends StatelessWidget {
  const _PinnedAction({required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: AppElevation.level1,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/library/read/${book.id}');
            },
            icon: const Icon(Icons.auto_stories_outlined),
            label: Text(book.isStarted ? l10n.bookContinueReading : l10n.bookStartReading),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSizes.minTouchTarget + 8)),
          ),
        ),
      ),
    );
  }
}

/// The cover, scaled up and blurred, behind a scrim that fades into the sheet surface.
class _BlurredBackdrop extends StatelessWidget {
  const _BlurredBackdrop({required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: surface),
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 420,
              width: double.infinity,
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: _backdropBlur, sigmaY: _backdropBlur, tileMode: TileMode.clamp),
                  child: Transform.scale(
                    scale: 2.2,
                    child: BookCover(title: book.title, imageUrl: book.coverUrl),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.35, 0.6],
                  colors: [surface.withValues(alpha: 0.55), surface.withValues(alpha: 0.85), surface],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeaderLabel extends StatelessWidget {
  const SectionHeaderLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Semantics(header: true, child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
  );
}

/// Five stars in half steps. The row is one labelled image for assistive tech.
class RatingStars extends StatelessWidget {
  const RatingStars({required this.rating, this.size = 24, super.key});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final premium = AppSemanticColors.of(context).premium;
    final label = l10n.bookRating(rating.toStringAsFixed(rating % 1 == 0 ? 0 : 1));
    return Semantics(
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 5; i++)
              Icon(
                rating >= i
                    ? Icons.star_rounded
                    : rating >= i - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
                size: size,
                color: rating >= i - 0.5 ? premium : scheme.outline,
              ),
            const SizedBox(width: AppSpacing.xs),
            Text(rating.toStringAsFixed(1), style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

/// Synopsis clamped to a few lines with a "Read more" toggle, which appears only when the text
/// actually overflows.
class ExpandableSynopsis extends StatefulWidget {
  const ExpandableSynopsis({required this.text, super.key});

  final String text;

  @override
  State<ExpandableSynopsis> createState() => _ExpandableSynopsisState();
}

class _ExpandableSynopsisState extends State<ExpandableSynopsis> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(height: 1.6);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _collapsedSynopsisLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: AppMotion.of(context, AppMotion.medium2),
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: Text(
                widget.text,
                style: style,
                maxLines: _expanded ? null : _collapsedSynopsisLines,
                overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            ),
            if (overflows)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? l10n.bookReadLess : l10n.bookReadMore),
                ),
              ),
          ],
        );
      },
    );
  }
}
