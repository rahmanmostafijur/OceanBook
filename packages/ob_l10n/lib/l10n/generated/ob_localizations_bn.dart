// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'ob_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class ObLocalizationsBn extends ObLocalizations {
  ObLocalizationsBn([String locale = 'bn']) : super(locale);

  @override
  String get appTitle => 'OceanBook';

  @override
  String get adminTitle => 'OceanBook অ্যাডমিন';

  @override
  String get navHome => 'হোম';

  @override
  String get navExplore => 'খুঁজুন';

  @override
  String get navStudy => 'পড়াশোনা';

  @override
  String get navLibrary => 'লাইব্রেরি';

  @override
  String get navProfile => 'প্রোফাইল';

  @override
  String get actionRetry => 'আবার চেষ্টা করুন';

  @override
  String get actionCancel => 'বাতিল';

  @override
  String get actionContinue => 'এগিয়ে যান';

  @override
  String get actionSignIn => 'সাইন ইন';

  @override
  String get actionSignOut => 'সাইন আউট';

  @override
  String get actionCreateAccount => 'অ্যাকাউন্ট খুলুন';

  @override
  String get actionSeeAll => 'সব দেখুন';

  @override
  String get actionReadPreview => 'প্রিভিউ পড়ুন';

  @override
  String get actionReadNow => 'এখনই পড়ুন';

  @override
  String get readingComingSoon => 'বই পড়ার সুবিধা শিগগিরই চালু হবে। এখন বইয়ের বিবরণ ও প্রিভিউ দেখতে পারবেন।';

  @override
  String get authWelcome => 'OceanBook-এ স্বাগতম';

  @override
  String get authSubtitle => 'পড়ুন, শিখুন, এসএসসি ও এইচএসসির প্রস্তুতি নিন।';

  @override
  String get authEmail => 'ইমেইল';

  @override
  String get authPassword => 'পাসওয়ার্ড';

  @override
  String get authDisplayName => 'আপনার নাম';

  @override
  String get authPhone => 'মোবাইল নম্বর';

  @override
  String get authPhoneHint => '০১XXXXXXXXX';

  @override
  String get authOtpCode => '৬ সংখ্যার কোড';

  @override
  String get authSendCode => 'কোড পাঠান';

  @override
  String authResendIn(int seconds) {
    return '$seconds সেকেন্ড পরে আবার পাঠান';
  }

  @override
  String get authContinueWithGoogle => 'Google দিয়ে চালিয়ে যান';

  @override
  String get authContinueWithApple => 'Apple দিয়ে চালিয়ে যান';

  @override
  String get authUsePhone => 'মোবাইল নম্বর ব্যবহার করুন';

  @override
  String get authUseEmail => 'ইমেইল ব্যবহার করুন';

  @override
  String get authNoAccount => 'নতুন?';

  @override
  String get authMfaTitle => 'দুই ধাপের যাচাই';

  @override
  String get authMfaPrompt => 'অথেনটিকেটর অ্যাপের ৬ সংখ্যার কোডটি লিখুন।';

  @override
  String get authMfaUseRecovery => 'রিকভারি কোড ব্যবহার করুন';

  @override
  String get authRecoveryCode => 'রিকভারি কোড';

  @override
  String get authGuestBrowse => 'অ্যাকাউন্ট ছাড়াই দেখুন';

  @override
  String get themeSystem => 'সিস্টেম';

  @override
  String get themeLight => 'লাইট';

  @override
  String get themeDark => 'ডার্ক';

  @override
  String get settingsTheme => 'থিম';

  @override
  String get settingsLanguage => 'ভাষা';

  @override
  String get languageBangla => 'বাংলা';

  @override
  String get languageEnglish => 'English';

  @override
  String get homeGreetingMorning => 'শুভ সকাল';

  @override
  String get homeGreetingAfternoon => 'শুভ দুপুর';

  @override
  String get homeGreetingEvening => 'শুভ সন্ধ্যা';

  @override
  String get homeContinueReading => 'পড়া চালিয়ে যান';

  @override
  String get homeStudyProgress => 'আপনার পড়াশোনার অগ্রগতি';

  @override
  String get homePopularBooks => 'জনপ্রিয় বই';

  @override
  String get homeFreeBooks => 'ফ্রি বই';

  @override
  String get homeSscPrep => 'এসএসসি প্রস্তুতি';

  @override
  String get homeHscPrep => 'এইচএসসি প্রস্তুতি';

  @override
  String get booksTitle => 'বই';

  @override
  String get bookFree => 'ফ্রি';

  @override
  String get bookPremium => 'প্রিমিয়াম';

  @override
  String get bookPreviewAvailable => 'প্রিভিউ আছে';

  @override
  String get bookContents => 'সূচিপত্র';

  @override
  String get bookAbout => 'বইটি সম্পর্কে';

  @override
  String get bookDetails => 'বইয়ের তথ্য';

  @override
  String get bookIsbn => 'আইএসবিএন';

  @override
  String get bookLanguage => 'ভাষা';

  @override
  String get bookPages => 'পৃষ্ঠা';

  @override
  String get bookPublished => 'প্রকাশকাল';

  @override
  String get bookEdition => 'সংস্করণ';

  @override
  String bookBy(String authors) {
    return 'লেখক: $authors';
  }

  @override
  String get authorsTitle => 'লেখক';

  @override
  String get publishersTitle => 'প্রকাশনী';

  @override
  String get categoriesTitle => 'বিভাগ';

  @override
  String get searchHint => 'বই, লেখক, প্রশ্ন খুঁজুন';

  @override
  String get studyTitle => 'পড়াশোনা';

  @override
  String get studySsc => 'এসএসসি';

  @override
  String get studyHsc => 'এইচএসসি';

  @override
  String get studySubjects => 'বিষয়';

  @override
  String get studyQuestionBank => 'প্রশ্ন ব্যাংক';

  @override
  String get studyPreviousPapers => 'বিগত সালের প্রশ্ন';

  @override
  String get questionShowAnswer => 'উত্তর দেখুন';

  @override
  String get questionHideAnswer => 'উত্তর লুকান';

  @override
  String get questionExplanation => 'ব্যাখ্যা';

  @override
  String get questionCorrectAnswer => 'সঠিক উত্তর';

  @override
  String get questionStimulus => 'উদ্দীপকটি পড়ুন';

  @override
  String questionMarks(num marks) {
    return '$marks নম্বর';
  }

  @override
  String questionAppearedIn(String papers) {
    return 'যেখানে এসেছে: $papers';
  }

  @override
  String get filterBoard => 'বোর্ড';

  @override
  String get filterYear => 'সাল';

  @override
  String get filterChapter => 'অধ্যায়';

  @override
  String get filterType => 'ধরন';

  @override
  String get filterDifficulty => 'কাঠিন্য';

  @override
  String get filterClear => 'ফিল্টার মুছুন';

  @override
  String get libraryTitle => 'লাইব্রেরি';

  @override
  String get profileTitle => 'প্রোফাইল';

  @override
  String get notificationsTitle => 'নোটিফিকেশন';

  @override
  String get emptyBooks => 'কোনো বই পাওয়া যায়নি';

  @override
  String get emptyBooksHint => 'অন্য বিভাগ দেখুন অথবা ফিল্টার মুছে ফেলুন।';

  @override
  String get emptyQuestions => 'এই ফিল্টারে কোনো প্রশ্ন নেই';

  @override
  String get emptyQuestionsHint => 'আরও প্রশ্ন দেখতে একটি ফিল্টার সরিয়ে দিন।';

  @override
  String get emptyLibrary => 'আপনার লাইব্রেরি খালি';

  @override
  String get emptyLibraryHint => 'আপনার পড়া ও সংরক্ষিত বই এখানে দেখা যাবে।';

  @override
  String get emptyNotifications => 'নতুন কোনো নোটিফিকেশন নেই';

  @override
  String get errorTitle => 'কিছু একটা সমস্যা হয়েছে';

  @override
  String get errorNetwork => 'আপনি অফলাইনে আছেন। ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।';

  @override
  String get errorServer => 'এই মুহূর্তে সমস্যা হচ্ছে। একটু পরে আবার চেষ্টা করুন।';

  @override
  String get errorSessionExpired => 'আপনার সেশন শেষ হয়েছে। আবার সাইন ইন করুন।';

  @override
  String get errorInvalidCredentials => 'ইমেইল বা পাসওয়ার্ড সঠিক নয়।';

  @override
  String get errorRateLimited => 'অনেকবার চেষ্টা করা হয়েছে। একটু অপেক্ষা করে আবার চেষ্টা করুন।';

  @override
  String get errorForbidden => 'এটি দেখার অনুমতি আপনার নেই।';

  @override
  String get errorNotFound => 'এটি খুঁজে পাওয়া যায়নি।';

  @override
  String get errorValidation => 'চিহ্নিত ঘরগুলো আবার দেখুন।';

  @override
  String get errorEmailTaken => 'এই ইমেইলে আগে থেকেই একটি অ্যাকাউন্ট আছে।';

  @override
  String get errorOtpInvalid => 'কোডটি সঠিক নয়।';

  @override
  String get errorOtpExpired => 'কোডের মেয়াদ শেষ। নতুন কোড নিন।';

  @override
  String get errorOtpCooldown => 'নতুন কোড চাওয়ার আগে একটু অপেক্ষা করুন।';

  @override
  String get errorPhoneNotSupported => 'এই নম্বর দিয়ে সাইন ইন করা যাচ্ছে না।';

  @override
  String get errorAccountLinkRequired =>
      'এই ইমেইলে একটি অ্যাকাউন্ট আছে। সেটিতে সাইন ইন করে প্রোফাইল থেকে এই পদ্ধতিটি যুক্ত করুন।';

  @override
  String get errorProviderUnavailable => 'এই সাইন-ইন পদ্ধতিটি এখনো চালু হয়নি।';

  @override
  String get errorMfaInvalid => 'কোডটি সঠিক নয়।';

  @override
  String get errorMfaRequired => 'এই কাজের জন্য দুই ধাপের যাচাই প্রয়োজন।';

  @override
  String get errorReauthRequired => 'চালিয়ে যেতে আপনার পরিচয় নিশ্চিত করুন।';

  @override
  String get errorAccountSuspended => 'এই অ্যাকাউন্টটি সক্রিয় নয়।';

  @override
  String get errorDeviceLimit => 'অনেকগুলো ডিভাইসে সাইন ইন করা আছে। আগে একটি থেকে সাইন আউট করুন।';

  @override
  String get adminNavDashboard => 'ড্যাশবোর্ড';

  @override
  String get adminNavPeople => 'ব্যবহারকারী';

  @override
  String get adminNavUsers => 'ব্যবহারকারী';

  @override
  String get adminNavRoles => 'ভূমিকা';

  @override
  String get adminNavCatalog => 'ক্যাটালগ';

  @override
  String get adminNavBooks => 'বই';

  @override
  String get adminNavAuthors => 'লেখক';

  @override
  String get adminNavPublishers => 'প্রকাশনী';

  @override
  String get adminNavCategories => 'বিভাগ';

  @override
  String get adminNavRights => 'কনটেন্ট ও স্বত্ব';

  @override
  String get adminNavContentSources => 'কনটেন্টের উৎস';

  @override
  String get adminNavRightsVerification => 'স্বত্ব যাচাই';

  @override
  String get adminNavQuestionBank => 'প্রশ্ন ব্যাংক';

  @override
  String get adminNavQuestions => 'প্রশ্ন';

  @override
  String get adminNavSubjects => 'বিষয়';

  @override
  String get adminNavChapters => 'অধ্যায়';

  @override
  String get adminNavTopics => 'টপিক';

  @override
  String get adminNavQuestionPapers => 'প্রশ্নপত্র';

  @override
  String get adminNavAssessment => 'মূল্যায়ন';

  @override
  String get adminNavQuizzes => 'কুইজ';

  @override
  String get adminNavExams => 'পরীক্ষা ব্যবস্থাপনা';

  @override
  String get adminNavCommerce => 'বাণিজ্য';

  @override
  String get adminNavSubscriptions => 'সাবস্ক্রিপশন';

  @override
  String get adminNavEntitlements => 'অ্যাক্সেস অধিকার';

  @override
  String get adminNavPayments => 'পেমেন্ট';

  @override
  String get adminNavOperations => 'পরিচালনা';

  @override
  String get adminNavAnalytics => 'অ্যানালিটিক্স';

  @override
  String get adminNavNotifications => 'নোটিফিকেশন';

  @override
  String get adminNavAuditLogs => 'অডিট লগ';

  @override
  String get adminNavSystemHealth => 'সিস্টেমের অবস্থা';

  @override
  String adminComingInPhase(int phase) {
    return 'পর্যায় $phase-এ চালু হবে';
  }

  @override
  String get adminStaffOnly => 'এই কনসোলটি OceanBook কর্মীদের জন্য।';

  @override
  String get adminSignInTitle => 'কর্মী সাইন-ইন';

  @override
  String get catalogAll => 'সব';

  @override
  String get catalogSortNewest => 'নতুন';

  @override
  String get catalogSortPopular => 'জনপ্রিয়';

  @override
  String get catalogSortRating => 'সেরা রেটিং';

  @override
  String get catalogSortLabel => 'বই সাজান';

  @override
  String get bookRegistered => 'অ্যাকাউন্টে ফ্রি';

  @override
  String get bookSignInToRead => 'বইটি পড়তে সাইন ইন করুন।';

  @override
  String get bookPremiumRequired => 'প্রিমিয়ামে অন্তর্ভুক্ত।';

  @override
  String get bookRightsRestricted => 'এই সংস্করণটি অনলাইনে পড়ার সুযোগ নেই।';

  @override
  String get bookNotAvailable => 'বইটি এখনো পড়ার জন্য উন্মুক্ত নয়।';

  @override
  String bookShownInLanguage(String language) {
    return '$language ভাষায় দেখানো হচ্ছে: আপনার ভাষায় অনুবাদ এখনো নেই।';
  }

  @override
  String get bookPublisher => 'প্রকাশক';

  @override
  String get bookPreviewBadge => 'প্রিভিউ';

  @override
  String get bookCredits => 'কৃতজ্ঞতা';

  @override
  String get bookRoleEditor => 'সম্পাদক';

  @override
  String get bookRoleTranslator => 'অনুবাদক';

  @override
  String get bookRoleIllustrator => 'চিত্রকর';

  @override
  String get bookRoleContributor => 'সহযোগী';

  @override
  String bookChapterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countটি অধ্যায়',
    );
    return '$_temp0';
  }

  @override
  String get authorBooks => 'বইসমূহ';

  @override
  String bookCardLabel(String title, String authors) {
    return '$title, $authors';
  }

  @override
  String get adminColumnTitle => 'শিরোনাম';

  @override
  String get adminColumnStatus => 'অবস্থা';

  @override
  String get adminColumnAccess => 'অ্যাক্সেস';

  @override
  String get adminColumnEditions => 'সংস্করণ';

  @override
  String get adminColumnUpdated => 'হালনাগাদ';

  @override
  String get adminColumnName => 'নাম';

  @override
  String get adminColumnSlug => 'স্লাগ';

  @override
  String get adminAllStatuses => 'সব অবস্থা';

  @override
  String get adminStatusDraft => 'খসড়া';

  @override
  String get adminStatusInReview => 'পর্যালোচনায়';

  @override
  String get adminStatusPublished => 'প্রকাশিত';

  @override
  String get adminStatusUnpublished => 'অপ্রকাশিত';

  @override
  String get adminStatusArchived => 'আর্কাইভ';

  @override
  String get adminStatusWithdrawn => 'প্রত্যাহৃত';

  @override
  String get adminActionSubmit => 'পর্যালোচনায় পাঠান';

  @override
  String get adminActionRequestChanges => 'সংশোধন চান';

  @override
  String get adminActionPublish => 'প্রকাশ করুন';

  @override
  String get adminActionUnpublish => 'প্রকাশ বন্ধ করুন';

  @override
  String get adminActionArchive => 'আর্কাইভ করুন';

  @override
  String get adminActionCreate => 'তৈরি করুন';

  @override
  String get adminNewBook => 'নতুন বই';

  @override
  String get adminReason => 'কারণ';

  @override
  String get adminReasonHint => 'অডিট লগে সংরক্ষিত হবে';

  @override
  String get adminSourceLanguage => 'মূল ভাষা';

  @override
  String get adminAccessFree => 'ফ্রি';

  @override
  String get adminAccessRegistered => 'নিবন্ধিত ব্যবহারকারী';

  @override
  String get adminAccessEntitled => 'প্রিমিয়াম (এনটাইটেলমেন্ট)';

  @override
  String get adminTranslations => 'অনুবাদ';

  @override
  String get adminEditions => 'সংস্করণসমূহ';

  @override
  String get adminContributors => 'লেখক ও সহযোগী';

  @override
  String get adminGateReady => 'উৎস যাচাই সম্পন্ন: প্রকাশের জন্য প্রস্তুত';

  @override
  String get adminGateBlocked => 'প্রকাশ আটকে আছে';

  @override
  String get adminGateNoProvenance => 'কোনো উৎস-তথ্য নেই';

  @override
  String get adminGateNotVerified => 'উৎস-তথ্য দ্বিতীয় ব্যক্তির যাচাইয়ের অপেক্ষায়';

  @override
  String get adminGateRightsNotCleared => 'স্বত্ব নিশ্চিত হয়নি';

  @override
  String get adminGateOutsideWindow => 'লাইসেন্সের মেয়াদের বাইরে';

  @override
  String get adminGateTerritory => 'প্রকাশের অঞ্চল অন্তর্ভুক্ত নয়';

  @override
  String get adminGateDisputed => 'স্বত্ব নিয়ে বিরোধ আছে';

  @override
  String adminChapters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countটি অধ্যায়',
      zero: 'সূচিপত্র নেই',
    );
    return '$_temp0';
  }

  @override
  String adminResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countটি ফলাফল',
    );
    return '$_temp0';
  }

  @override
  String get errorNotPublishable => 'উৎস যাচাই ও স্বত্ব নিশ্চিত না হওয়া পর্যন্ত এটি প্রকাশ করা যাবে না।';

  @override
  String get errorInvalidTransition => 'বর্তমান অবস্থায় এই কাজটি করা যায় না।';

  @override
  String get errorSelfVerification => 'আপনার লেখা তথ্য অন্য কাউকে যাচাই করতে হবে।';

  @override
  String get errorRecordLocked => 'জমা দেওয়া তথ্য সম্পাদনা করা যায় না। নতুন তথ্য যোগ করুন।';

  @override
  String get errorSlugTaken => 'এই স্লাগটি আগেই ব্যবহৃত হয়েছে।';
}
