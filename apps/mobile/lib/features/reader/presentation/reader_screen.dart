import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../library/data/library_providers.dart';
import 'reader_settings_controller.dart';
import 'reader_settings_sheet.dart';

/// Strict typographic frame: a comfortable measure (about 60-70 characters) and fixed side margins.
const double _readingMeasure = 640;
const double _sideMargin = 28;
const double _baseFontSize = 18;

const _samplePassage = <String>[
  'ভোরের আলো তখনও ভালো করে ফোটেনি। নদীর ওপর পাতলা কুয়াশা ভেসে ছিল, আর দূরে কোথাও একটা নৌকার দাঁড়ের শব্দ '
      'ধীরে ধীরে কাছে আসছিল। ঘাটের সিঁড়িতে বসে সে অনেকক্ষণ ধরে সেই শব্দ শুনছিল।',
  'শহরের কোলাহল এখানে পৌঁছায় না। এখানে সময় যেন একটু আস্তে চলে। মানুষ কথা বলে কম, শোনে বেশি। সেই '
      'নীরবতার ভেতরেই ছোট ছোট ঘটনাগুলো বড় হয়ে ওঠে, আর ছোট ছোট কথারা জমে ওঠে গল্পের মতো।',
  'সে জানত, আজ কিছু একটা বদলাবে। কীভাবে, কেন, কিছুই জানত না; শুধু একটা অস্পষ্ট অনুভূতি বুকের ভেতর '
      'নড়েচড়ে বেড়াচ্ছিল। হয়তো এটাই বড় হয়ে ওঠা: না-জানা কিছুর দিকে এগিয়ে যাওয়ার সাহস।',
  'ঘাট থেকে ফেরার পথে সে দেখল, পুরোনো বটগাছের নিচে কয়েকজন বৃদ্ধ বসে আছেন। তাঁদের মুখে বয়সের রেখা, '
      'কিন্তু চোখে এক ধরনের শান্ত কৌতুক। কেউ একজন হেসে বলল, "আজ এত সকালে?"',
  'সে উত্তর দিল না, শুধু হাসল। কারণ উত্তরটা সে নিজেও জানত না। তাদের সামনে দিয়ে হেঁটে যেতে যেতে মনে '
      'হলো, এই পথটা সে হাজারবার হেঁটেছে, অথচ আজ প্রথমবারের মতো চারপাশটা এত স্পষ্ট দেখছে।',
  'বাড়ির উঠোনে পা দিতেই মায়ের গলা শোনা গেল। রান্নাঘর থেকে ধোঁয়া উঠছে, আর বাতাসে ভাজা মশলার গন্ধ। '
      'ছোট একটা মুহূর্ত, কিন্তু তার ভেতরে যেন পুরো ছেলেবেলাটাই লুকিয়ে ছিল।',
  'সেদিন দুপুরে সে প্রথমবার নিজের জন্য একটা সিদ্ধান্ত নিল। খুব বড় কিছু নয়, তবু সেটাই ছিল তার '
      'নিজের। আর সেই সিদ্ধান্তের হাত ধরেই শুরু হলো পরের অধ্যায়।',
];

/// Distraction-free reading canvas. Tap the page to show or hide the controls; the settings panel
/// changes text size, theme and alignment live. Sample text until the Phase 4 reader streams books.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({required this.bookId, super.key});

  final String bookId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _scroll = ScrollController();
  final _progress = ValueNotifier<double>(0);
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _progress.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    _progress.value = max <= 0 ? 0 : (_scroll.offset / max).clamp(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final settings = ref.watch(readerSettingsProvider);
    final palette = paletteFor(settings.theme);
    final book = ref.watch(libraryItemProvider(widget.bookId));
    final chromeDuration = AppMotion.of(context, AppMotion.short4);
    final chromeShown = _chromeVisible || MediaQuery.accessibleNavigationOf(context);
    final overlay = palette.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

    final textStyle = TextStyle(
      fontSize: _baseFontSize * settings.fontScale,
      height: settings.lineHeight,
      color: palette.text,
      letterSpacing: 0.1,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay.copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: palette.background),
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.medium2),
        curve: AppMotion.standard,
        color: palette.background,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Semantics(
                onTapHint: l10n.readerToggleControls,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                  child: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: _readingMeasure + _sideMargin * 2),
                        child: ListView(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(_sideMargin, 88, _sideMargin, 72),
                          children: [
                            if (book != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                                child: Semantics(
                                  header: true,
                                  child: Text(
                                    book.title,
                                    style: textStyle.copyWith(
                                      fontSize: textStyle.fontSize! * 1.5,
                                      fontWeight: FontWeight.w700,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ),
                            for (final paragraph in _samplePassage)
                              Padding(
                                padding: EdgeInsets.only(bottom: textStyle.fontSize! * 0.9),
                                child: Text(
                                  paragraph,
                                  style: textStyle,
                                  textAlign: settings.justify ? TextAlign.justify : TextAlign.start,
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpacing.xl),
                              child: Text(
                                l10n.readerPreviewNotice,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !chromeShown,
                  // Hidden controls stay reachable for screen-reader users, who cannot tap the page to reveal them.
                  child: AnimatedOpacity(
                    duration: chromeDuration,
                    opacity: chromeShown ? 1 : 0,
                    alwaysIncludeSemantics: true,
                    child: _TopBar(
                      palette: palette,
                      title: book?.title ?? '',
                      onClose: () => context.canPop() ? context.pop() : context.go('/library'),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ValueListenableBuilder<double>(
                  valueListenable: _progress,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    semanticsLabel: l10n.readerProgress,
                    minHeight: 3,
                    color: palette.accent,
                    backgroundColor: palette.muted.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.palette, required this.title, required this.onClose});

  final ReaderPalette palette;
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.background, palette.background.withValues(alpha: 0)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.readerClose,
                color: palette.text,
                onPressed: onClose,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: palette.muted),
                ),
              ),
              IconButton(
                tooltip: l10n.readerSettings,
                color: palette.text,
                onPressed: () => showReaderSettings(context),
                icon: const Icon(Icons.text_fields),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
