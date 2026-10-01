import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'ob_localizations_bn.dart';
import 'ob_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of ObLocalizations
/// returned by `ObLocalizations.of(context)`.
///
/// Applications need to include `ObLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/ob_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: ObLocalizations.localizationsDelegates,
///   supportedLocales: ObLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the ObLocalizations.supportedLocales
/// property.
abstract class ObLocalizations {
  ObLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static ObLocalizations of(BuildContext context) {
    return Localizations.of<ObLocalizations>(context, ObLocalizations)!;
  }

  static const LocalizationsDelegate<ObLocalizations> delegate = _ObLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('bn'), Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'OceanBook'**
  String get appTitle;

  /// No description provided for @adminTitle.
  ///
  /// In en, this message translates to:
  /// **'OceanBook Admin'**
  String get adminTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navExplore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get navExplore;

  /// No description provided for @navStudy.
  ///
  /// In en, this message translates to:
  /// **'Study'**
  String get navStudy;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @actionSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get actionSignIn;

  /// No description provided for @actionSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get actionSignOut;

  /// No description provided for @actionCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get actionCreateAccount;

  /// No description provided for @actionSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get actionSeeAll;

  /// No description provided for @actionReadPreview.
  ///
  /// In en, this message translates to:
  /// **'Read preview'**
  String get actionReadPreview;

  /// No description provided for @actionReadNow.
  ///
  /// In en, this message translates to:
  /// **'Read now'**
  String get actionReadNow;

  /// No description provided for @readingComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Reading opens soon. You can browse book details and previews now.'**
  String get readingComingSoon;

  /// No description provided for @authWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to OceanBook'**
  String get authWelcome;

  /// No description provided for @authSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read, study and practise for SSC and HSC.'**
  String get authSubtitle;

  /// No description provided for @authEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get authDisplayName;

  /// No description provided for @authPhone.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get authPhone;

  /// No description provided for @authPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'01XXXXXXXXX'**
  String get authPhoneHint;

  /// No description provided for @authOtpCode.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get authOtpCode;

  /// No description provided for @authSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get authSendCode;

  /// No description provided for @authResendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String authResendIn(int seconds);

  /// No description provided for @authContinueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authContinueWithGoogle;

  /// No description provided for @authContinueWithApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get authContinueWithApple;

  /// No description provided for @authUsePhone.
  ///
  /// In en, this message translates to:
  /// **'Use mobile number'**
  String get authUsePhone;

  /// No description provided for @authUseEmail.
  ///
  /// In en, this message translates to:
  /// **'Use email'**
  String get authUseEmail;

  /// No description provided for @authNoAccount.
  ///
  /// In en, this message translates to:
  /// **'New here?'**
  String get authNoAccount;

  /// No description provided for @authMfaTitle.
  ///
  /// In en, this message translates to:
  /// **'Two-step verification'**
  String get authMfaTitle;

  /// No description provided for @authMfaPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code from your authenticator app.'**
  String get authMfaPrompt;

  /// No description provided for @authMfaUseRecovery.
  ///
  /// In en, this message translates to:
  /// **'Use a recovery code instead'**
  String get authMfaUseRecovery;

  /// No description provided for @authRecoveryCode.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get authRecoveryCode;

  /// No description provided for @authGuestBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse without an account'**
  String get authGuestBrowse;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @languageBangla.
  ///
  /// In en, this message translates to:
  /// **'বাংলা'**
  String get languageBangla;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @homeGreetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get homeGreetingMorning;

  /// No description provided for @homeGreetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get homeGreetingAfternoon;

  /// No description provided for @homeGreetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get homeGreetingEvening;

  /// No description provided for @homeContinueReading.
  ///
  /// In en, this message translates to:
  /// **'Continue reading'**
  String get homeContinueReading;

  /// No description provided for @homeStudyProgress.
  ///
  /// In en, this message translates to:
  /// **'Your study progress'**
  String get homeStudyProgress;

  /// No description provided for @homePopularBooks.
  ///
  /// In en, this message translates to:
  /// **'Popular books'**
  String get homePopularBooks;

  /// No description provided for @homeFreeBooks.
  ///
  /// In en, this message translates to:
  /// **'Free books'**
  String get homeFreeBooks;

  /// No description provided for @homeSscPrep.
  ///
  /// In en, this message translates to:
  /// **'SSC preparation'**
  String get homeSscPrep;

  /// No description provided for @homeHscPrep.
  ///
  /// In en, this message translates to:
  /// **'HSC preparation'**
  String get homeHscPrep;

  /// No description provided for @booksTitle.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get booksTitle;

  /// No description provided for @bookFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get bookFree;

  /// No description provided for @bookPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get bookPremium;

  /// No description provided for @bookPreviewAvailable.
  ///
  /// In en, this message translates to:
  /// **'Preview available'**
  String get bookPreviewAvailable;

  /// No description provided for @bookContents.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get bookContents;

  /// No description provided for @bookAbout.
  ///
  /// In en, this message translates to:
  /// **'About this book'**
  String get bookAbout;

  /// No description provided for @bookDetails.
  ///
  /// In en, this message translates to:
  /// **'Book details'**
  String get bookDetails;

  /// No description provided for @bookIsbn.
  ///
  /// In en, this message translates to:
  /// **'ISBN'**
  String get bookIsbn;

  /// No description provided for @bookLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get bookLanguage;

  /// No description provided for @bookPages.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get bookPages;

  /// No description provided for @bookPublished.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get bookPublished;

  /// No description provided for @bookEdition.
  ///
  /// In en, this message translates to:
  /// **'Edition'**
  String get bookEdition;

  /// No description provided for @bookBy.
  ///
  /// In en, this message translates to:
  /// **'by {authors}'**
  String bookBy(String authors);

  /// No description provided for @authorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Authors'**
  String get authorsTitle;

  /// No description provided for @publishersTitle.
  ///
  /// In en, this message translates to:
  /// **'Publishers'**
  String get publishersTitle;

  /// No description provided for @categoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categoriesTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search books, authors, questions'**
  String get searchHint;

  /// No description provided for @studyTitle.
  ///
  /// In en, this message translates to:
  /// **'Study'**
  String get studyTitle;

  /// No description provided for @studySsc.
  ///
  /// In en, this message translates to:
  /// **'SSC'**
  String get studySsc;

  /// No description provided for @studyHsc.
  ///
  /// In en, this message translates to:
  /// **'HSC'**
  String get studyHsc;

  /// No description provided for @studySubjects.
  ///
  /// In en, this message translates to:
  /// **'Subjects'**
  String get studySubjects;

  /// No description provided for @studyQuestionBank.
  ///
  /// In en, this message translates to:
  /// **'Question bank'**
  String get studyQuestionBank;

  /// No description provided for @studyPreviousPapers.
  ///
  /// In en, this message translates to:
  /// **'Previous papers'**
  String get studyPreviousPapers;

  /// No description provided for @questionShowAnswer.
  ///
  /// In en, this message translates to:
  /// **'Show answer'**
  String get questionShowAnswer;

  /// No description provided for @questionHideAnswer.
  ///
  /// In en, this message translates to:
  /// **'Hide answer'**
  String get questionHideAnswer;

  /// No description provided for @questionExplanation.
  ///
  /// In en, this message translates to:
  /// **'Explanation'**
  String get questionExplanation;

  /// No description provided for @questionCorrectAnswer.
  ///
  /// In en, this message translates to:
  /// **'Correct answer'**
  String get questionCorrectAnswer;

  /// No description provided for @questionStimulus.
  ///
  /// In en, this message translates to:
  /// **'Read the passage'**
  String get questionStimulus;

  /// No description provided for @questionMarks.
  ///
  /// In en, this message translates to:
  /// **'{marks, plural, =1{1 mark} other{{marks} marks}}'**
  String questionMarks(num marks);

  /// No description provided for @questionAppearedIn.
  ///
  /// In en, this message translates to:
  /// **'Appeared in {papers}'**
  String questionAppearedIn(String papers);

  /// No description provided for @filterBoard.
  ///
  /// In en, this message translates to:
  /// **'Board'**
  String get filterBoard;

  /// No description provided for @filterYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get filterYear;

  /// No description provided for @filterChapter.
  ///
  /// In en, this message translates to:
  /// **'Chapter'**
  String get filterChapter;

  /// No description provided for @filterType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get filterType;

  /// No description provided for @filterDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Difficulty'**
  String get filterDifficulty;

  /// No description provided for @filterClear.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get filterClear;

  /// No description provided for @libraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTitle;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @emptyBooks.
  ///
  /// In en, this message translates to:
  /// **'No books found'**
  String get emptyBooks;

  /// No description provided for @emptyBooksHint.
  ///
  /// In en, this message translates to:
  /// **'Try another category or clear your filters.'**
  String get emptyBooksHint;

  /// No description provided for @emptyQuestions.
  ///
  /// In en, this message translates to:
  /// **'No questions match these filters'**
  String get emptyQuestions;

  /// No description provided for @emptyQuestionsHint.
  ///
  /// In en, this message translates to:
  /// **'Remove a filter to see more questions.'**
  String get emptyQuestionsHint;

  /// No description provided for @emptyLibrary.
  ///
  /// In en, this message translates to:
  /// **'Your library is empty'**
  String get emptyLibrary;

  /// No description provided for @emptyLibraryHint.
  ///
  /// In en, this message translates to:
  /// **'Books you read and save will appear here.'**
  String get emptyLibraryHint;

  /// No description provided for @emptyNotifications.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up'**
  String get emptyNotifications;

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorTitle;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Check your connection and try again.'**
  String get errorNetwork;

  /// No description provided for @errorServer.
  ///
  /// In en, this message translates to:
  /// **'We\'re having trouble right now. Please try again shortly.'**
  String get errorServer;

  /// No description provided for @errorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has ended. Please sign in again.'**
  String get errorSessionExpired;

  /// No description provided for @errorInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Email or password is incorrect.'**
  String get errorInvalidCredentials;

  /// No description provided for @errorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a moment and try again.'**
  String get errorRateLimited;

  /// No description provided for @errorForbidden.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have access to this.'**
  String get errorForbidden;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find that.'**
  String get errorNotFound;

  /// No description provided for @errorValidation.
  ///
  /// In en, this message translates to:
  /// **'Please check the highlighted fields.'**
  String get errorValidation;

  /// No description provided for @errorEmailTaken.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists.'**
  String get errorEmailTaken;

  /// No description provided for @errorOtpInvalid.
  ///
  /// In en, this message translates to:
  /// **'That code is not correct.'**
  String get errorOtpInvalid;

  /// No description provided for @errorOtpExpired.
  ///
  /// In en, this message translates to:
  /// **'This code has expired. Request a new one.'**
  String get errorOtpExpired;

  /// No description provided for @errorOtpCooldown.
  ///
  /// In en, this message translates to:
  /// **'Please wait before requesting another code.'**
  String get errorOtpCooldown;

  /// No description provided for @errorPhoneNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Phone sign-in isn\'t available for this number.'**
  String get errorPhoneNotSupported;

  /// No description provided for @errorAccountLinkRequired.
  ///
  /// In en, this message translates to:
  /// **'This email already has an account. Sign in to it, then link this sign-in method from Profile.'**
  String get errorAccountLinkRequired;

  /// No description provided for @errorProviderUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This sign-in option isn\'t available yet.'**
  String get errorProviderUnavailable;

  /// No description provided for @errorMfaInvalid.
  ///
  /// In en, this message translates to:
  /// **'That code is not valid.'**
  String get errorMfaInvalid;

  /// No description provided for @errorMfaRequired.
  ///
  /// In en, this message translates to:
  /// **'Two-step verification is required for this action.'**
  String get errorMfaRequired;

  /// No description provided for @errorReauthRequired.
  ///
  /// In en, this message translates to:
  /// **'Please confirm it\'s you to continue.'**
  String get errorReauthRequired;

  /// No description provided for @errorAccountSuspended.
  ///
  /// In en, this message translates to:
  /// **'This account is not active.'**
  String get errorAccountSuspended;

  /// No description provided for @errorDeviceLimit.
  ///
  /// In en, this message translates to:
  /// **'Too many signed-in devices. Sign out of one first.'**
  String get errorDeviceLimit;

  /// No description provided for @adminNavDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get adminNavDashboard;

  /// No description provided for @adminNavPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get adminNavPeople;

  /// No description provided for @adminNavUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get adminNavUsers;

  /// No description provided for @adminNavRoles.
  ///
  /// In en, this message translates to:
  /// **'Roles'**
  String get adminNavRoles;

  /// No description provided for @adminNavCatalog.
  ///
  /// In en, this message translates to:
  /// **'Catalog'**
  String get adminNavCatalog;

  /// No description provided for @adminNavBooks.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get adminNavBooks;

  /// No description provided for @adminNavAuthors.
  ///
  /// In en, this message translates to:
  /// **'Authors'**
  String get adminNavAuthors;

  /// No description provided for @adminNavPublishers.
  ///
  /// In en, this message translates to:
  /// **'Publishers'**
  String get adminNavPublishers;

  /// No description provided for @adminNavCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get adminNavCategories;

  /// No description provided for @adminNavRights.
  ///
  /// In en, this message translates to:
  /// **'Content & rights'**
  String get adminNavRights;

  /// No description provided for @adminNavContentSources.
  ///
  /// In en, this message translates to:
  /// **'Content sources'**
  String get adminNavContentSources;

  /// No description provided for @adminNavRightsVerification.
  ///
  /// In en, this message translates to:
  /// **'Rights verification'**
  String get adminNavRightsVerification;

  /// No description provided for @adminNavQuestionBank.
  ///
  /// In en, this message translates to:
  /// **'Question bank'**
  String get adminNavQuestionBank;

  /// No description provided for @adminNavQuestions.
  ///
  /// In en, this message translates to:
  /// **'Questions'**
  String get adminNavQuestions;

  /// No description provided for @adminNavSubjects.
  ///
  /// In en, this message translates to:
  /// **'Subjects'**
  String get adminNavSubjects;

  /// No description provided for @adminNavChapters.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get adminNavChapters;

  /// No description provided for @adminNavTopics.
  ///
  /// In en, this message translates to:
  /// **'Topics'**
  String get adminNavTopics;

  /// No description provided for @adminNavQuestionPapers.
  ///
  /// In en, this message translates to:
  /// **'Question papers'**
  String get adminNavQuestionPapers;

  /// No description provided for @adminNavAssessment.
  ///
  /// In en, this message translates to:
  /// **'Assessment'**
  String get adminNavAssessment;

  /// No description provided for @adminNavQuizzes.
  ///
  /// In en, this message translates to:
  /// **'Quizzes'**
  String get adminNavQuizzes;

  /// No description provided for @adminNavExams.
  ///
  /// In en, this message translates to:
  /// **'Exam management'**
  String get adminNavExams;

  /// No description provided for @adminNavCommerce.
  ///
  /// In en, this message translates to:
  /// **'Commerce'**
  String get adminNavCommerce;

  /// No description provided for @adminNavSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get adminNavSubscriptions;

  /// No description provided for @adminNavEntitlements.
  ///
  /// In en, this message translates to:
  /// **'Entitlements'**
  String get adminNavEntitlements;

  /// No description provided for @adminNavPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get adminNavPayments;

  /// No description provided for @adminNavOperations.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get adminNavOperations;

  /// No description provided for @adminNavAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get adminNavAnalytics;

  /// No description provided for @adminNavNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get adminNavNotifications;

  /// No description provided for @adminNavAuditLogs.
  ///
  /// In en, this message translates to:
  /// **'Audit logs'**
  String get adminNavAuditLogs;

  /// No description provided for @adminNavSystemHealth.
  ///
  /// In en, this message translates to:
  /// **'System health'**
  String get adminNavSystemHealth;

  /// No description provided for @adminComingInPhase.
  ///
  /// In en, this message translates to:
  /// **'Available in phase {phase}'**
  String adminComingInPhase(int phase);

  /// No description provided for @adminStaffOnly.
  ///
  /// In en, this message translates to:
  /// **'This console is for OceanBook staff.'**
  String get adminStaffOnly;

  /// No description provided for @adminSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Staff sign-in'**
  String get adminSignInTitle;

  /// No description provided for @catalogAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get catalogAll;

  /// No description provided for @catalogSortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get catalogSortNewest;

  /// No description provided for @catalogSortPopular.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get catalogSortPopular;

  /// No description provided for @catalogSortRating.
  ///
  /// In en, this message translates to:
  /// **'Top rated'**
  String get catalogSortRating;

  /// No description provided for @catalogSortLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort books'**
  String get catalogSortLabel;

  /// No description provided for @bookRegistered.
  ///
  /// In en, this message translates to:
  /// **'Free with account'**
  String get bookRegistered;

  /// No description provided for @bookSignInToRead.
  ///
  /// In en, this message translates to:
  /// **'Sign in to read this book.'**
  String get bookSignInToRead;

  /// No description provided for @bookPremiumRequired.
  ///
  /// In en, this message translates to:
  /// **'Included with Premium.'**
  String get bookPremiumRequired;

  /// No description provided for @bookRightsRestricted.
  ///
  /// In en, this message translates to:
  /// **'Online reading isn\'t available for this edition.'**
  String get bookRightsRestricted;

  /// No description provided for @bookNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'This book isn\'t available to read yet.'**
  String get bookNotAvailable;

  /// No description provided for @bookShownInLanguage.
  ///
  /// In en, this message translates to:
  /// **'Shown in {language}: no translation in your language yet.'**
  String bookShownInLanguage(String language);

  /// No description provided for @bookPublisher.
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get bookPublisher;

  /// No description provided for @bookPreviewBadge.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get bookPreviewBadge;

  /// No description provided for @bookCredits.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get bookCredits;

  /// No description provided for @bookRoleEditor.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get bookRoleEditor;

  /// No description provided for @bookRoleTranslator.
  ///
  /// In en, this message translates to:
  /// **'Translator'**
  String get bookRoleTranslator;

  /// No description provided for @bookRoleIllustrator.
  ///
  /// In en, this message translates to:
  /// **'Illustrator'**
  String get bookRoleIllustrator;

  /// No description provided for @bookRoleContributor.
  ///
  /// In en, this message translates to:
  /// **'Contributor'**
  String get bookRoleContributor;

  /// No description provided for @bookChapterCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 chapter} other{{count} chapters}}'**
  String bookChapterCount(int count);

  /// No description provided for @authorBooks.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get authorBooks;

  /// No description provided for @bookCardLabel.
  ///
  /// In en, this message translates to:
  /// **'{title}, {authors}'**
  String bookCardLabel(String title, String authors);

  /// No description provided for @adminColumnTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get adminColumnTitle;

  /// No description provided for @adminColumnStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get adminColumnStatus;

  /// No description provided for @adminColumnAccess.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get adminColumnAccess;

  /// No description provided for @adminColumnEditions.
  ///
  /// In en, this message translates to:
  /// **'Editions'**
  String get adminColumnEditions;

  /// No description provided for @adminColumnUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get adminColumnUpdated;

  /// No description provided for @adminColumnName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get adminColumnName;

  /// No description provided for @adminColumnSlug.
  ///
  /// In en, this message translates to:
  /// **'Slug'**
  String get adminColumnSlug;

  /// No description provided for @adminAllStatuses.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get adminAllStatuses;

  /// No description provided for @adminStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get adminStatusDraft;

  /// No description provided for @adminStatusInReview.
  ///
  /// In en, this message translates to:
  /// **'In review'**
  String get adminStatusInReview;

  /// No description provided for @adminStatusPublished.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get adminStatusPublished;

  /// No description provided for @adminStatusUnpublished.
  ///
  /// In en, this message translates to:
  /// **'Unpublished'**
  String get adminStatusUnpublished;

  /// No description provided for @adminStatusArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get adminStatusArchived;

  /// No description provided for @adminStatusWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Withdrawn'**
  String get adminStatusWithdrawn;

  /// No description provided for @adminActionSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit for review'**
  String get adminActionSubmit;

  /// No description provided for @adminActionRequestChanges.
  ///
  /// In en, this message translates to:
  /// **'Request changes'**
  String get adminActionRequestChanges;

  /// No description provided for @adminActionPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get adminActionPublish;

  /// No description provided for @adminActionUnpublish.
  ///
  /// In en, this message translates to:
  /// **'Unpublish'**
  String get adminActionUnpublish;

  /// No description provided for @adminActionArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get adminActionArchive;

  /// No description provided for @adminActionCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get adminActionCreate;

  /// No description provided for @adminNewBook.
  ///
  /// In en, this message translates to:
  /// **'New book'**
  String get adminNewBook;

  /// No description provided for @adminReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get adminReason;

  /// No description provided for @adminReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Recorded in the audit log'**
  String get adminReasonHint;

  /// No description provided for @adminSourceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Source language'**
  String get adminSourceLanguage;

  /// No description provided for @adminAccessFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get adminAccessFree;

  /// No description provided for @adminAccessRegistered.
  ///
  /// In en, this message translates to:
  /// **'Registered users'**
  String get adminAccessRegistered;

  /// No description provided for @adminAccessEntitled.
  ///
  /// In en, this message translates to:
  /// **'Premium (entitlement)'**
  String get adminAccessEntitled;

  /// No description provided for @adminTranslations.
  ///
  /// In en, this message translates to:
  /// **'Translations'**
  String get adminTranslations;

  /// No description provided for @adminEditions.
  ///
  /// In en, this message translates to:
  /// **'Editions'**
  String get adminEditions;

  /// No description provided for @adminContributors.
  ///
  /// In en, this message translates to:
  /// **'Contributors'**
  String get adminContributors;

  /// No description provided for @adminGateReady.
  ///
  /// In en, this message translates to:
  /// **'Provenance verified: ready to publish'**
  String get adminGateReady;

  /// No description provided for @adminGateBlocked.
  ///
  /// In en, this message translates to:
  /// **'Publishing blocked'**
  String get adminGateBlocked;

  /// No description provided for @adminGateNoProvenance.
  ///
  /// In en, this message translates to:
  /// **'No provenance recorded'**
  String get adminGateNoProvenance;

  /// No description provided for @adminGateNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Provenance awaits a second person\'s verification'**
  String get adminGateNotVerified;

  /// No description provided for @adminGateRightsNotCleared.
  ///
  /// In en, this message translates to:
  /// **'Rights are not cleared'**
  String get adminGateRightsNotCleared;

  /// No description provided for @adminGateOutsideWindow.
  ///
  /// In en, this message translates to:
  /// **'Outside the licence window'**
  String get adminGateOutsideWindow;

  /// No description provided for @adminGateTerritory.
  ///
  /// In en, this message translates to:
  /// **'Launch territory not covered'**
  String get adminGateTerritory;

  /// No description provided for @adminGateDisputed.
  ///
  /// In en, this message translates to:
  /// **'Rights are disputed'**
  String get adminGateDisputed;

  /// No description provided for @adminChapters.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No table of contents} =1{1 chapter} other{{count} chapters}}'**
  String adminChapters(int count);

  /// No description provided for @adminResults.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 result} other{{count} results}}'**
  String adminResults(int count);

  /// No description provided for @errorNotPublishable.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be published until its provenance is verified and rights are clear.'**
  String get errorNotPublishable;

  /// No description provided for @errorInvalidTransition.
  ///
  /// In en, this message translates to:
  /// **'That action isn\'t available in the current status.'**
  String get errorInvalidTransition;

  /// No description provided for @errorSelfVerification.
  ///
  /// In en, this message translates to:
  /// **'Someone else must verify what you recorded.'**
  String get errorSelfVerification;

  /// No description provided for @errorRecordLocked.
  ///
  /// In en, this message translates to:
  /// **'Submitted records are locked. Record a new entry instead.'**
  String get errorRecordLocked;

  /// No description provided for @errorSlugTaken.
  ///
  /// In en, this message translates to:
  /// **'This slug is already used.'**
  String get errorSlugTaken;
}

class _ObLocalizationsDelegate extends LocalizationsDelegate<ObLocalizations> {
  const _ObLocalizationsDelegate();

  @override
  Future<ObLocalizations> load(Locale locale) {
    return SynchronousFuture<ObLocalizations>(lookupObLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['bn', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_ObLocalizationsDelegate old) => false;
}

ObLocalizations lookupObLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return ObLocalizationsBn();
    case 'en':
      return ObLocalizationsEn();
  }

  throw FlutterError(
    'ObLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
