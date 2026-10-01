import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:ob_l10n/ob_l10n.dart';

enum StudyLevel { ssc, hsc }

/// Study: SSC/HSC question bank entry (filled by the question-bank milestones).
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  StudyLevel _level = StudyLevel.ssc;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.studyTitle)),
      body: ConstrainedContent(
        maxWidth: AppSizes.maxReadableWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<StudyLevel>(
              segments: [
                ButtonSegment(value: StudyLevel.ssc, label: Text(l10n.studySsc)),
                ButtonSegment(value: StudyLevel.hsc, label: Text(l10n.studyHsc)),
              ],
              selected: {_level},
              onSelectionChanged: (s) => setState(() => _level = s.first),
            ),
            Expanded(
              child: EmptyState(
                icon: Icons.quiz_outlined,
                title: l10n.emptyQuestions,
                message: l10n.emptyQuestionsHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
