import 'package:flutter/material.dart';
import 'package:ob_l10n/ob_l10n.dart';

/// One admin destination. [phase] is the roadmap phase that delivers it (12-phase0-revisions §2);
/// destinations from later phases are visible but show what is coming instead of a fake screen.
@immutable
class AdminNavItem {
  const AdminNavItem({required this.path, required this.icon, required this.label, required this.phase});

  final String path;
  final IconData icon;
  final String Function(ObLocalizations) label;
  final int phase;
}

@immutable
class AdminNavSection {
  const AdminNavSection({required this.label, required this.items});

  final String Function(ObLocalizations) label;
  final List<AdminNavItem> items;
}

/// The admin information architecture (owner list, Phase 2 instruction B).
final List<AdminNavSection> adminNavigation = [
  AdminNavSection(
    label: (l) => l.adminNavDashboard,
    items: [AdminNavItem(path: '/', icon: Icons.space_dashboard_outlined, label: (l) => l.adminNavDashboard, phase: 2)],
  ),
  AdminNavSection(
    label: (l) => l.adminNavPeople,
    items: [
      AdminNavItem(path: '/users', icon: Icons.group_outlined, label: (l) => l.adminNavUsers, phase: 1),
      AdminNavItem(path: '/roles', icon: Icons.admin_panel_settings_outlined, label: (l) => l.adminNavRoles, phase: 1),
    ],
  ),
  AdminNavSection(
    label: (l) => l.adminNavCatalog,
    items: [
      AdminNavItem(path: '/books', icon: Icons.menu_book_outlined, label: (l) => l.adminNavBooks, phase: 2),
      AdminNavItem(path: '/authors', icon: Icons.history_edu_outlined, label: (l) => l.adminNavAuthors, phase: 2),
      AdminNavItem(path: '/publishers', icon: Icons.business_outlined, label: (l) => l.adminNavPublishers, phase: 2),
      AdminNavItem(path: '/categories', icon: Icons.category_outlined, label: (l) => l.adminNavCategories, phase: 2),
    ],
  ),
  AdminNavSection(
    label: (l) => l.adminNavRights,
    items: [
      AdminNavItem(
        path: '/content-sources',
        icon: Icons.source_outlined,
        label: (l) => l.adminNavContentSources,
        phase: 2,
      ),
      AdminNavItem(
        path: '/rights',
        icon: Icons.verified_outlined,
        label: (l) => l.adminNavRightsVerification,
        phase: 2,
      ),
    ],
  ),
  AdminNavSection(
    label: (l) => l.adminNavQuestionBank,
    items: [
      AdminNavItem(path: '/questions', icon: Icons.quiz_outlined, label: (l) => l.adminNavQuestions, phase: 2),
      AdminNavItem(path: '/subjects', icon: Icons.library_books_outlined, label: (l) => l.adminNavSubjects, phase: 2),
      AdminNavItem(path: '/chapters', icon: Icons.format_list_numbered, label: (l) => l.adminNavChapters, phase: 2),
      AdminNavItem(path: '/topics', icon: Icons.label_outline, label: (l) => l.adminNavTopics, phase: 2),
      AdminNavItem(
        path: '/question-papers',
        icon: Icons.description_outlined,
        label: (l) => l.adminNavQuestionPapers,
        phase: 2,
      ),
    ],
  ),
  AdminNavSection(
    label: (l) => l.adminNavAssessment,
    items: [
      AdminNavItem(path: '/quizzes', icon: Icons.checklist_outlined, label: (l) => l.adminNavQuizzes, phase: 3),
      AdminNavItem(path: '/exams', icon: Icons.timer_outlined, label: (l) => l.adminNavExams, phase: 3),
    ],
  ),
  AdminNavSection(
    label: (l) => l.adminNavCommerce,
    items: [
      AdminNavItem(path: '/subscriptions', icon: Icons.autorenew, label: (l) => l.adminNavSubscriptions, phase: 5),
      AdminNavItem(path: '/entitlements', icon: Icons.key_outlined, label: (l) => l.adminNavEntitlements, phase: 2),
      AdminNavItem(path: '/payments', icon: Icons.payments_outlined, label: (l) => l.adminNavPayments, phase: 5),
    ],
  ),
  AdminNavSection(
    label: (l) => l.adminNavOperations,
    items: [
      AdminNavItem(path: '/analytics', icon: Icons.insights_outlined, label: (l) => l.adminNavAnalytics, phase: 3),
      AdminNavItem(
        path: '/notifications',
        icon: Icons.notifications_outlined,
        label: (l) => l.adminNavNotifications,
        phase: 3,
      ),
      AdminNavItem(path: '/audit-logs', icon: Icons.receipt_long_outlined, label: (l) => l.adminNavAuditLogs, phase: 1),
      AdminNavItem(
        path: '/system-health',
        icon: Icons.monitor_heart_outlined,
        label: (l) => l.adminNavSystemHealth,
        phase: 2,
      ),
    ],
  ),
];

List<AdminNavItem> get allAdminItems => [for (final s in adminNavigation) ...s.items];
