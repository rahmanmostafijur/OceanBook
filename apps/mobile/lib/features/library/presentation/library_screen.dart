import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:ob_l10n/ob_l10n.dart';

/// Library (signed-in only). Reading, downloads and sync arrive in Phase 4.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.libraryTitle)),
      body: EmptyState(icon: Icons.local_library_outlined, title: l10n.emptyLibrary, message: l10n.emptyLibraryHint),
    );
  }
}
