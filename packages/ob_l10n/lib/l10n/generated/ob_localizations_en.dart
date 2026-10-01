// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'ob_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class ObLocalizationsEn extends ObLocalizations {
  ObLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'OceanBook';

  @override
  String get adminTitle => 'OceanBook Admin';

  @override
  String get navHome => 'Home';

  @override
  String get navExplore => 'Explore';

  @override
  String get navStudy => 'Study';

  @override
  String get navLibrary => 'Library';

  @override
  String get navProfile => 'Profile';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionSignIn => 'Sign in';

  @override
  String get actionSignOut => 'Sign out';

  @override
  String get actionCreateAccount => 'Create account';

  @override
  String get actionSeeAll => 'See all';

  @override
  String get actionReadPreview => 'Read preview';

  @override
  String get actionReadNow => 'Read now';

  @override
  String get readingComingSoon => 'Reading opens soon. You can browse book details and previews now.';

  @override
  String get authWelcome => 'Welcome to OceanBook';

  @override
  String get authSubtitle => 'Read, study and practise for SSC and HSC.';

  @override
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Password';

  @override
  String get authDisplayName => 'Your name';

  @override
  String get authPhone => 'Mobile number';

  @override
  String get authPhoneHint => '01XXXXXXXXX';

  @override
  String get authOtpCode => '6-digit code';

  @override
  String get authSendCode => 'Send code';

  @override
  String authResendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get authContinueWithGoogle => 'Continue with Google';

  @override
  String get authContinueWithApple => 'Continue with Apple';

  @override
  String get authUsePhone => 'Use mobile number';

  @override
  String get authUseEmail => 'Use email';

  @override
  String get authNoAccount => 'New here?';

  @override
  String get authMfaTitle => 'Two-step verification';

  @override
  String get authMfaPrompt => 'Enter the 6-digit code from your authenticator app.';

  @override
  String get authMfaUseRecovery => 'Use a recovery code instead';

  @override
  String get authRecoveryCode => 'Recovery code';

  @override
  String get authGuestBrowse => 'Browse without an account';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get languageBangla => 'বাংলা';

  @override
  String get languageEnglish => 'English';

  @override
  String get homeGreetingMorning => 'Good morning';

  @override
  String get homeGreetingAfternoon => 'Good afternoon';

  @override
  String get homeGreetingEvening => 'Good evening';

  @override
  String get homeContinueReading => 'Continue reading';

  @override
  String get homeStudyProgress => 'Your study progress';

  @override
  String get homePopularBooks => 'Popular books';

  @override
  String get homeFreeBooks => 'Free books';

  @override
  String get homeSscPrep => 'SSC preparation';

  @override
  String get homeHscPrep => 'HSC preparation';

  @override
  String get booksTitle => 'Books';

  @override
  String get bookFree => 'Free';

  @override
  String get bookPremium => 'Premium';

  @override
  String get bookPreviewAvailable => 'Preview available';

  @override
  String get bookContents => 'Contents';

  @override
  String get bookAbout => 'About this book';

  @override
  String get bookDetails => 'Book details';

  @override
  String get bookIsbn => 'ISBN';

  @override
  String get bookLanguage => 'Language';

  @override
  String get bookPages => 'Pages';

  @override
  String get bookPublished => 'Published';

  @override
  String get bookEdition => 'Edition';

  @override
  String bookBy(String authors) {
    return 'by $authors';
  }

  @override
  String get authorsTitle => 'Authors';

  @override
  String get publishersTitle => 'Publishers';

  @override
  String get categoriesTitle => 'Categories';

  @override
  String get searchHint => 'Search books, authors, questions';

  @override
  String get studyTitle => 'Study';

  @override
  String get studySsc => 'SSC';

  @override
  String get studyHsc => 'HSC';

  @override
  String get studySubjects => 'Subjects';

  @override
  String get studyQuestionBank => 'Question bank';

  @override
  String get studyPreviousPapers => 'Previous papers';

  @override
  String get questionShowAnswer => 'Show answer';

  @override
  String get questionHideAnswer => 'Hide answer';

  @override
  String get questionExplanation => 'Explanation';

  @override
  String get questionCorrectAnswer => 'Correct answer';

  @override
  String get questionStimulus => 'Read the passage';

  @override
  String questionMarks(num marks) {
    String _temp0 = intl.Intl.pluralLogic(
      marks,
      locale: localeName,
      other: '$marks marks',
      one: '1 mark',
    );
    return '$_temp0';
  }

  @override
  String questionAppearedIn(String papers) {
    return 'Appeared in $papers';
  }

  @override
  String get filterBoard => 'Board';

  @override
  String get filterYear => 'Year';

  @override
  String get filterChapter => 'Chapter';

  @override
  String get filterType => 'Type';

  @override
  String get filterDifficulty => 'Difficulty';

  @override
  String get filterClear => 'Clear filters';

  @override
  String get libraryTitle => 'Library';

  @override
  String get profileTitle => 'Profile';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get emptyBooks => 'No books found';

  @override
  String get emptyBooksHint => 'Try another category or clear your filters.';

  @override
  String get emptyQuestions => 'No questions match these filters';

  @override
  String get emptyQuestionsHint => 'Remove a filter to see more questions.';

  @override
  String get emptyLibrary => 'Your library is empty';

  @override
  String get emptyLibraryHint => 'Books you read and save will appear here.';

  @override
  String get emptyNotifications => 'You\'re all caught up';

  @override
  String get errorTitle => 'Something went wrong';

  @override
  String get errorNetwork => 'You\'re offline. Check your connection and try again.';

  @override
  String get errorServer => 'We\'re having trouble right now. Please try again shortly.';

  @override
  String get errorSessionExpired => 'Your session has ended. Please sign in again.';

  @override
  String get errorInvalidCredentials => 'Email or password is incorrect.';

  @override
  String get errorRateLimited => 'Too many attempts. Please wait a moment and try again.';

  @override
  String get errorForbidden => 'You don\'t have access to this.';

  @override
  String get errorNotFound => 'We couldn\'t find that.';

  @override
  String get errorValidation => 'Please check the highlighted fields.';

  @override
  String get errorEmailTaken => 'An account with this email already exists.';

  @override
  String get errorOtpInvalid => 'That code is not correct.';

  @override
  String get errorOtpExpired => 'This code has expired. Request a new one.';

  @override
  String get errorOtpCooldown => 'Please wait before requesting another code.';

  @override
  String get errorPhoneNotSupported => 'Phone sign-in isn\'t available for this number.';

  @override
  String get errorAccountLinkRequired =>
      'This email already has an account. Sign in to it, then link this sign-in method from Profile.';

  @override
  String get errorProviderUnavailable => 'This sign-in option isn\'t available yet.';

  @override
  String get errorMfaInvalid => 'That code is not valid.';

  @override
  String get errorMfaRequired => 'Two-step verification is required for this action.';

  @override
  String get errorReauthRequired => 'Please confirm it\'s you to continue.';

  @override
  String get errorAccountSuspended => 'This account is not active.';

  @override
  String get errorDeviceLimit => 'Too many signed-in devices. Sign out of one first.';

  @override
  String get adminNavDashboard => 'Dashboard';

  @override
  String get adminNavPeople => 'People';

  @override
  String get adminNavUsers => 'Users';

  @override
  String get adminNavRoles => 'Roles';

  @override
  String get adminNavCatalog => 'Catalog';

  @override
  String get adminNavBooks => 'Books';

  @override
  String get adminNavAuthors => 'Authors';

  @override
  String get adminNavPublishers => 'Publishers';

  @override
  String get adminNavCategories => 'Categories';

  @override
  String get adminNavRights => 'Content & rights';

  @override
  String get adminNavContentSources => 'Content sources';

  @override
  String get adminNavRightsVerification => 'Rights verification';

  @override
  String get adminNavQuestionBank => 'Question bank';

  @override
  String get adminNavQuestions => 'Questions';

  @override
  String get adminNavSubjects => 'Subjects';

  @override
  String get adminNavChapters => 'Chapters';

  @override
  String get adminNavTopics => 'Topics';

  @override
  String get adminNavQuestionPapers => 'Question papers';

  @override
  String get adminNavAssessment => 'Assessment';

  @override
  String get adminNavQuizzes => 'Quizzes';

  @override
  String get adminNavExams => 'Exam management';

  @override
  String get adminNavCommerce => 'Commerce';

  @override
  String get adminNavSubscriptions => 'Subscriptions';

  @override
  String get adminNavEntitlements => 'Entitlements';

  @override
  String get adminNavPayments => 'Payments';

  @override
  String get adminNavOperations => 'Operations';

  @override
  String get adminNavAnalytics => 'Analytics';

  @override
  String get adminNavNotifications => 'Notifications';

  @override
  String get adminNavAuditLogs => 'Audit logs';

  @override
  String get adminNavSystemHealth => 'System health';

  @override
  String adminComingInPhase(int phase) {
    return 'Available in phase $phase';
  }

  @override
  String get adminStaffOnly => 'This console is for OceanBook staff.';

  @override
  String get adminSignInTitle => 'Staff sign-in';

  @override
  String get catalogAll => 'All';

  @override
  String get catalogSortNewest => 'Newest';

  @override
  String get catalogSortPopular => 'Popular';

  @override
  String get catalogSortRating => 'Top rated';

  @override
  String get catalogSortLabel => 'Sort books';

  @override
  String get bookRegistered => 'Free with account';

  @override
  String get bookSignInToRead => 'Sign in to read this book.';

  @override
  String get bookPremiumRequired => 'Included with Premium.';

  @override
  String get bookRightsRestricted => 'Online reading isn\'t available for this edition.';

  @override
  String get bookNotAvailable => 'This book isn\'t available to read yet.';

  @override
  String bookShownInLanguage(String language) {
    return 'Shown in $language: no translation in your language yet.';
  }

  @override
  String get bookPublisher => 'Publisher';

  @override
  String get bookPreviewBadge => 'Preview';

  @override
  String get bookCredits => 'Credits';

  @override
  String get bookRoleEditor => 'Editor';

  @override
  String get bookRoleTranslator => 'Translator';

  @override
  String get bookRoleIllustrator => 'Illustrator';

  @override
  String get bookRoleContributor => 'Contributor';

  @override
  String bookChapterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chapters',
      one: '1 chapter',
    );
    return '$_temp0';
  }

  @override
  String get authorBooks => 'Books';

  @override
  String bookCardLabel(String title, String authors) {
    return '$title, $authors';
  }
}
