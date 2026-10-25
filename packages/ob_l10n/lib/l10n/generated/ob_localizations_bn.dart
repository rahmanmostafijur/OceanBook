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
  String get adminAccessFree => 'বিনামূল্যে';

  @override
  String get adminAccessRegistered => 'লগইন করা ব্যবহারকারী';

  @override
  String get adminAccessEntitled => 'অধিকারপ্রাপ্ত';

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

  @override
  String get adminNewSource => 'নতুন কনটেন্টের উৎস';

  @override
  String get adminColumnKind => 'ধরন';

  @override
  String get adminColumnActive => 'সক্রিয়';

  @override
  String get adminWebsite => 'ওয়েবসাইট';

  @override
  String get adminSourceActive => 'সক্রিয়';

  @override
  String get adminSourceRetired => 'অবসরপ্রাপ্ত';

  @override
  String get adminSourceEducationBoard => 'শিক্ষা বোর্ড';

  @override
  String get adminSourcePublisher => 'প্রকাশক';

  @override
  String get adminSourceAuthor => 'লেখক';

  @override
  String get adminSourceGovernment => 'সরকারি';

  @override
  String get adminSourceWebsite => 'ওয়েবসাইট';

  @override
  String get adminSourcePartner => 'অংশীদার';

  @override
  String get adminSourceInternal => 'অভ্যন্তরীণ';

  @override
  String get adminSourceOther => 'অন্যান্য';

  @override
  String get adminLicenseCommercial => 'বাণিজ্যিক লাইসেন্স';

  @override
  String get adminLicensePermission => 'অনুমতি প্রাপ্ত';

  @override
  String get adminLicensePublicDomain => 'পাবলিক ডোমেইন';

  @override
  String get adminLicenseGovernmentOpen => 'সরকারি উন্মুক্ত লাইসেন্স';

  @override
  String get adminLicenseOriginal => 'নিজস্ব সৃষ্টি';

  @override
  String get adminLicenseUnknown => 'লাইসেন্স অজানা';

  @override
  String get adminRightsPending => 'স্বত্ব অপেক্ষমাণ';

  @override
  String get adminRightsCleared => 'স্বত্ব নিশ্চিত';

  @override
  String get adminRightsRestricted => 'স্বত্ব সীমিত';

  @override
  String get adminRightsExpired => 'স্বত্বের মেয়াদ শেষ';

  @override
  String get adminRightsDisputed => 'স্বত্ব নিয়ে বিরোধ';

  @override
  String get adminVerificationUnverified => 'যাচাই হয়নি';

  @override
  String get adminVerificationPending => 'যাচাইয়ের অপেক্ষায়';

  @override
  String get adminVerificationVerified => 'যাচাই সম্পন্ন';

  @override
  String get adminVerificationRejected => 'প্রত্যাখ্যাত';

  @override
  String get adminQueueEmpty => 'যাচাইয়ের জন্য কিছু অপেক্ষায় নেই।';

  @override
  String get adminActionVerify => 'যাচাই করুন';

  @override
  String get adminActionReject => 'প্রত্যাখ্যান করুন';

  @override
  String get adminRejectNotes => 'কী ঠিক করতে হবে';

  @override
  String get adminProvenance => 'উৎস ও স্বত্ব';

  @override
  String get adminRecordProvenance => 'উৎস-তথ্য যোগ করুন';

  @override
  String get adminChangeRights => 'স্বত্ব পরিবর্তন';

  @override
  String get adminLicense => 'লাইসেন্স';

  @override
  String get adminRights => 'স্বত্বের অবস্থা';

  @override
  String get adminTerritories => 'অঞ্চল';

  @override
  String get adminTerritoriesHint => 'দেশের কোড, যেমন BD, অথবা সারা বিশ্বের জন্য *';

  @override
  String get adminLicenseReference => 'লাইসেন্স নম্বর বা সূত্র';

  @override
  String get adminChangeRightsWarning =>
      'সঙ্গে সঙ্গে কার্যকর হবে এবং যে কনটেন্টের স্বত্ব আর নিশ্চিত নয় তা প্রকাশ থেকে সরে যাবে।';

  @override
  String get librarySearchHint => 'আপনার লাইব্রেরিতে খুঁজুন';

  @override
  String get libraryCategoryAll => 'সব';

  @override
  String get libraryCategoriesLabel => 'বিভাগ';

  @override
  String libraryProgress(int percent) {
    return '$percent% পড়া হয়েছে';
  }

  @override
  String get libraryNoMatches => 'আপনার খোঁজের সাথে কোনো বই মেলেনি';

  @override
  String get libraryNoMatchesHint => 'অন্য কোনো শব্দ বা অন্য ফিল্টার দিয়ে চেষ্টা করুন।';

  @override
  String get bookSynopsis => 'সারসংক্ষেপ';

  @override
  String get bookReadMore => 'আরও পড়ুন';

  @override
  String get bookReadLess => 'কম দেখুন';

  @override
  String bookRating(String rating) {
    return '৫-এর মধ্যে $rating রেটিং';
  }

  @override
  String get bookStartReading => 'পড়া শুরু করুন';

  @override
  String get bookContinueReading => 'পড়া চালিয়ে যান';

  @override
  String get readerSettings => 'পড়ার সেটিংস';

  @override
  String get readerTextSize => 'লেখার আকার';

  @override
  String get readerSmallerText => 'ছোট লেখা';

  @override
  String get readerLargerText => 'বড় লেখা';

  @override
  String get readerTheme => 'থিম';

  @override
  String get readerThemeDay => 'দিন';

  @override
  String get readerThemeNight => 'রাত';

  @override
  String get readerThemeSepia => 'সেপিয়া';

  @override
  String get readerAlignment => 'বিন্যাস';

  @override
  String get readerAlignStart => 'বামে';

  @override
  String get readerAlignJustify => 'সমান';

  @override
  String get readerClose => 'পাঠক বন্ধ করুন';

  @override
  String get readerPreviewNotice => 'নমুনা লেখা। পড়ার সুবিধা চালু হলে আসল বই এখানে খুলবে।';

  @override
  String get homeHeroTitle => 'আজ কী শিখবেন?';

  @override
  String get homeHeroSubtitle => 'বই, বিগত সালের প্রশ্ন আর অনুশীলন, সব এক জায়গায়।';

  @override
  String get homeHeroCta => 'খোঁজা শুরু করুন';

  @override
  String get homeQuickBooks => 'বই';

  @override
  String get homeQuickPapers => 'বিগত সালের প্রশ্ন';

  @override
  String get homeQuickPractice => 'অনুশীলন';

  @override
  String get filterSubject => 'বিষয়';

  @override
  String get filterAny => 'যেকোনো';

  @override
  String get questionTypeMcqSingle => 'বহুনির্বাচনী';

  @override
  String get questionTypeMcqMulti => 'একাধিক উত্তর';

  @override
  String get questionTypeTrueFalse => 'সত্য বা মিথ্যা';

  @override
  String get questionTypeShortAnswer => 'সংক্ষিপ্ত প্রশ্ন';

  @override
  String get questionTypeCreative => 'সৃজনশীল';

  @override
  String get questionTypeFillBlank => 'শূন্যস্থান পূরণ';

  @override
  String get questionTypeMatching => 'মিলকরণ';

  @override
  String questionDifficultyLevel(int level) {
    return 'স্তর $level';
  }

  @override
  String get questionAnswerSignIn => 'উত্তর দেখতে সাইন ইন করুন';

  @override
  String get questionAnswerPremium => 'উত্তর প্রিমিয়াম সদস্যদের জন্য';

  @override
  String get questionDetailTitle => 'প্রশ্ন';

  @override
  String get studyChooseSubject => 'একটি বিষয় বেছে নিন';

  @override
  String get questionOptionCorrectMark => 'সঠিক';

  @override
  String get questionOptionWrongMark => 'ভুল, আপনার উত্তর';

  @override
  String get questionModelAnswer => 'আদর্শ উত্তর';

  @override
  String get adminStatusApproved => 'অনুমোদিত';

  @override
  String get adminStatusChangesRequested => 'পরিবর্তন চাওয়া হয়েছে';

  @override
  String get adminActionApprove => 'অনুমোদন করুন';

  @override
  String get adminActionRestore => 'পুনরুদ্ধার করুন';

  @override
  String get adminNeedsReview => 'পর্যালোচনা দরকার';

  @override
  String get adminColumnStem => 'প্রশ্ন';

  @override
  String get adminColumnType => 'ধরন';

  @override
  String get adminColumnMarks => 'নম্বর';

  @override
  String get adminColumnExam => 'পরীক্ষা';

  @override
  String get adminColumnBoards => 'বোর্ড';

  @override
  String get adminColumnQuestions => 'প্রশ্ন';

  @override
  String get adminQuestionIssues => 'জমা দেওয়ার আগে যা ঠিক করতে হবে';

  @override
  String get adminPendingEdit => 'সম্পাদনা চলছে; প্রকাশিত সংস্করণ অপরিবর্তিত থাকবে।';

  @override
  String get adminAcknowledgeDuplicates => 'তবুও প্রকাশ করুন (ডুপ্লিকেট জানা আছে)';

  @override
  String get adminGateNoIndependentApproval => 'যিনি সম্পাদনা করেননি তাঁর অনুমোদন দরকার';

  @override
  String get adminGateDuplicate => 'বিদ্যমান প্রশ্নের ডুপ্লিকেট মনে হচ্ছে';

  @override
  String get adminGateNoItems => 'কাগজে কোনো প্রশ্ন নেই';

  @override
  String get adminGateItemsNotPublished => 'কাগজের কিছু প্রশ্ন প্রকাশিত নয়';

  @override
  String get adminExamBoardFinal => 'বোর্ড পরীক্ষা';

  @override
  String get adminExamTest => 'নির্বাচনী পরীক্ষা';

  @override
  String get adminExamPreTest => 'প্রাক-নির্বাচনী';

  @override
  String get adminExamModel => 'মডেল টেস্ট';

  @override
  String get adminExamAdmission => 'ভর্তি পরীক্ষা';

  @override
  String adminQuestionVersion(int version) {
    return 'সংস্করণ $version';
  }

  @override
  String get adminNoPapers => 'এখনও কোনো প্রশ্নপত্র নেই';

  @override
  String get adminNoSubjects => 'এখনও কোনো বিষয় নেই';

  @override
  String get contentBlank => 'ফাঁকা স্থান';

  @override
  String get questionPremium => 'প্রিমিয়াম';

  @override
  String get readerToggleControls => 'পড়ার নিয়ন্ত্রণ দেখান বা লুকান';

  @override
  String get readerProgress => 'পড়ার অগ্রগতি';

  @override
  String get adminReasonTooShort => 'কমপক্ষে ৩টি অক্ষর লিখুন';

  @override
  String get adminStatusActive => 'সক্রিয়';

  @override
  String get adminStatusSuspended => 'স্থগিত';

  @override
  String get adminStatusPendingDeletion => 'মুছে ফেলার অপেক্ষায়';

  @override
  String get adminStatusDeleted => 'মুছে ফেলা হয়েছে';

  @override
  String get adminRoleStudent => 'শিক্ষার্থী';

  @override
  String get adminRoleContentEditor => 'কনটেন্ট সম্পাদক';

  @override
  String get adminRoleReviewer => 'পর্যালোচক';

  @override
  String get adminRoleAdmin => 'প্রশাসক';

  @override
  String get adminRoleSuperAdmin => 'সুপার প্রশাসক';

  @override
  String get adminNoEmail => 'ইমেইল নেই';

  @override
  String get commonLoading => 'লোড হচ্ছে';

  @override
  String get adminAddChapter => 'অধ্যায় যোগ করুন';

  @override
  String get adminAddTopic => 'টপিক যোগ করুন';

  @override
  String get adminEditItem => 'সম্পাদনা';

  @override
  String get actionSave => 'সংরক্ষণ করুন';

  @override
  String get adminNameBangla => 'নাম (বাংলা, আবশ্যক)';

  @override
  String get adminNameEnglish => 'নাম (ইংরেজি)';

  @override
  String get adminChapterNumber => 'অধ্যায় নম্বর';

  @override
  String get adminArchiveItem => 'আর্কাইভ করুন';

  @override
  String get adminRestoreItem => 'পুনরুদ্ধার করুন';

  @override
  String get adminEditChapter => 'অধ্যায় সম্পাদনা';

  @override
  String get adminEditTopic => 'টপিক সম্পাদনা';

  @override
  String get adminNoChapters => 'এখনও কোনো অধ্যায় নেই';

  @override
  String get adminAddSubject => 'বিষয় যোগ করুন';

  @override
  String get adminEditSubject => 'বিষয় সম্পাদনা';

  @override
  String get adminCurriculum => 'শিক্ষাক্রম';

  @override
  String get adminLevel => 'স্তর';

  @override
  String get adminFamilyKey => 'পরিবার কী (যেমন physics)';

  @override
  String get adminBoardCode => 'বোর্ড কোড (ঐচ্ছিক)';

  @override
  String get adminPaperNumber => 'পত্র';

  @override
  String get adminPaperNone => 'পত্র নয়';

  @override
  String get adminPaperFirst => '১ম পত্র';

  @override
  String get adminPaperSecond => '২য় পত্র';

  @override
  String get adminGroupsHeading => 'বিভাগ';

  @override
  String get adminOfferingNone => 'নেই';

  @override
  String get adminOfferingCompulsory => 'আবশ্যিক';

  @override
  String get adminOfferingElective => 'নির্বাচনী';

  @override
  String get adminOfferingOptional => 'ঐচ্ছিক (৪র্থ বিষয়)';

  @override
  String get adminNewQuestion => 'নতুন প্রশ্ন';

  @override
  String get adminEditQuestion => 'প্রশ্ন সম্পাদনা';

  @override
  String get adminFieldType => 'প্রশ্নের ধরন';

  @override
  String get adminFieldLanguage => 'ভাষা';

  @override
  String get adminLanguageBangla => 'বাংলা';

  @override
  String get adminLanguageEnglish => 'ইংরেজি';

  @override
  String get adminFieldStem => 'প্রশ্ন';

  @override
  String get adminFieldExplanation => 'ব্যাখ্যা (ঐচ্ছিক)';

  @override
  String get adminMathHint => 'গণিত ডলার চিহ্নের মধ্যে লিখুন, যেমন \$x^2\$। ফাঁকা লাইন দিলে নতুন অনুচ্ছেদ শুরু হয়।';

  @override
  String get adminOptionsHeading => 'বিকল্প';

  @override
  String get adminOptionLabel => 'লেবেল';

  @override
  String get adminOptionText => 'বিকল্পের লেখা';

  @override
  String get adminOptionCorrect => 'সঠিক';

  @override
  String get adminAddOption => 'বিকল্প যোগ করুন';

  @override
  String get adminRemoveOption => 'বিকল্প মুছুন';

  @override
  String get adminFieldMarks => 'নম্বর';

  @override
  String get adminFieldDifficulty => 'কাঠিন্য';

  @override
  String get adminDifficultyNone => 'নির্ধারিত নয়';

  @override
  String get adminFieldAccess => 'প্রবেশাধিকার';

  @override
  String get adminEntitlementKey => 'অধিকার কী';

  @override
  String get adminFieldSubject => 'বিষয়';

  @override
  String get adminFieldChapter => 'অধ্যায় (ঐচ্ছিক)';

  @override
  String get adminFieldTopic => 'টপিক (ঐচ্ছিক)';

  @override
  String get adminNoneOption => 'নেই';

  @override
  String get adminChangeNote => 'কী বদলেছে (ঐচ্ছিক)';

  @override
  String get adminCorrectExactlyOne => 'ঠিক একটি বিকল্পকে সঠিক চিহ্নিত করুন।';

  @override
  String get adminCorrectAtLeastOne => 'অন্তত একটি বিকল্পকে সঠিক চিহ্নিত করুন।';

  @override
  String get adminEditorUnsupported =>
      'এই প্রশ্নে এমন ধরন বা ফরম্যাটিং আছে যা এখানে সম্পাদনা করা যায় না; এখানে বদলালে কিছু অংশ হারিয়ে যেতে পারে।';

  @override
  String get adminSkipToContent => 'মূল বিষয়বস্তুতে যান';

  @override
  String get actionClose => 'বন্ধ করুন';

  @override
  String adminPageOf(int page, int total) {
    final intl.NumberFormat pageNumberFormat = intl.NumberFormat.decimalPattern(localeName);
    final String pageString = pageNumberFormat.format(page);
    final intl.NumberFormat totalNumberFormat = intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return '$pageString / $totalString';
  }

  @override
  String readerFontPercent(int percent) {
    final intl.NumberFormat percentNumberFormat = intl.NumberFormat.decimalPattern(localeName);
    final String percentString = percentNumberFormat.format(percent);

    return '$percentString%';
  }

  @override
  String get adminFieldStimulus => 'উদ্দীপক';

  @override
  String get adminPartsHeading => 'প্রশ্নের অংশ';

  @override
  String get adminPartLabel => 'চিহ্ন';

  @override
  String get adminPartPrompt => 'অংশের প্রশ্ন';

  @override
  String get adminPartMarks => 'নম্বর';

  @override
  String get adminPartLevel => 'জ্ঞানের স্তর';

  @override
  String get adminAddPart => 'অংশ যোগ করুন';

  @override
  String get adminRemovePart => 'অংশ মুছুন';

  @override
  String get adminCognitiveKnowledge => 'জ্ঞানমূলক';

  @override
  String get adminCognitiveComprehension => 'অনুধাবনমূলক';

  @override
  String get adminCognitiveApplication => 'প্রয়োগমূলক';

  @override
  String get adminCognitiveHigherOrder => 'উচ্চতর দক্ষতা';

  @override
  String adminTotalMarks(String marks) {
    return 'মোট নম্বর: $marks';
  }

  @override
  String get adminNewPaper => 'নতুন প্রশ্নপত্র';

  @override
  String get adminEditPaper => 'প্রশ্নপত্র সম্পাদনা';

  @override
  String get adminFieldExamYear => 'পরীক্ষার বছর';

  @override
  String get adminFieldExamKind => 'পরীক্ষার ধরন';

  @override
  String get adminFieldSection => 'অংশ';

  @override
  String get adminSectionFull => 'পূর্ণাঙ্গ প্রশ্নপত্র';

  @override
  String get adminSectionMcq => 'বহুনির্বাচনি';

  @override
  String get adminSectionCq => 'সৃজনশীল';

  @override
  String get adminFieldPaperTitle => 'শিরোনাম (ঐচ্ছিক)';

  @override
  String get adminFieldPaperMarks => 'মোট নম্বর (ঐচ্ছিক)';

  @override
  String get adminFieldDuration => 'সময় (মিনিট, ঐচ্ছিক)';

  @override
  String get adminFieldBoards => 'বোর্ড';

  @override
  String get adminFieldGroup => 'বিভাগ';

  @override
  String get adminFieldMedium => 'মাধ্যম';

  @override
  String get adminPaperItems => 'এই প্রশ্নপত্রের প্রশ্ন';

  @override
  String get adminChooseQuestions => 'প্রশ্ন বাছাই করুন';

  @override
  String get adminChooseQuestionsHint => 'এই প্রশ্নপত্রের বিষয়ের প্রকাশিত প্রশ্ন';

  @override
  String get adminNoPublishedQuestions => 'এই বিষয়ে এখনও কোনো প্রকাশিত প্রশ্ন নেই।';

  @override
  String get adminNoPaperItems => 'এখনও কোনো প্রশ্ন যোগ করা হয়নি';

  @override
  String get adminItemNumber => 'নং';

  @override
  String get adminPaperLocked => 'শুধু খসড়া প্রশ্নপত্র সম্পাদনা করা যায়।';

  @override
  String get adminModelAnswer => 'আদর্শ উত্তর';

  @override
  String get adminMarkingGuidance => 'নম্বর দেওয়ার নির্দেশনা (ঐচ্ছিক)';

  @override
  String get adminBlankHint => 'প্রশ্নের লেখায় প্রতিটি শূন্যস্থান [[1]], [[2]] এভাবে লিখুন।';

  @override
  String adminBlankAnswers(int number) {
    return '$number নম্বর শূন্যস্থানের গ্রহণযোগ্য উত্তর';
  }

  @override
  String get adminBlankAnswersHint => 'প্রতি লাইনে একটি উত্তর';

  @override
  String get adminBlankMarkersInvalid =>
      'শূন্যস্থানের চিহ্ন [[1]], [[2]] ... ক্রমানুসারে দিন, কোনো সংখ্যা বাদ দেবেন না।';

  @override
  String get adminMatchingLeft => 'বাম কলাম';

  @override
  String get adminMatchingRight => 'ডান কলাম';

  @override
  String get adminMatchingItem => 'আইটেম';

  @override
  String get adminMatchesWith => 'মিল';

  @override
  String get adminAddItem => 'আইটেম যোগ করুন';

  @override
  String get adminRemoveItem => 'আইটেম মুছুন';

  @override
  String get adminFormatHelpTitle => 'লেখার নিয়ম';

  @override
  String get adminFormatHelp =>
      '**গাঢ়**  *তির্যক*  __আন্ডারলাইন__  H~2~O  x^2^\nলাইনের মধ্যে গণিতের জন্য \$x^2\$, আলাদা লাইনে গণিতের জন্য \$\$x^2\$\$\nএকটি ফাঁকা লাইন নতুন অনুচ্ছেদ শুরু করে\n- বুলেট তালিকা   1. সংখ্যার তালিকা   i. রোমান তালিকা   ক. বাংলা তালিকা (প্রতি লাইনে একটি)\n| ঘর | ঘর | দিয়ে সারণি (প্রতি লাইনে একটি সারি, প্রতি সারিতে সমান ঘর)\nব্যাকস্ল্যাশ পরের অক্ষরটি যেমন আছে তেমন লেখে: \\* \\\$ \\\\';

  @override
  String adminTranslationHeading(String language) {
    return 'অনুবাদ ($language)';
  }

  @override
  String get adminTranslationHint => 'ঐচ্ছিক। অনুবাদ না চাইলে সব ঘর খালি রাখুন।';

  @override
  String get adminTranslationUnsupported =>
      'এই অনুবাদে এমন বিন্যাস আছে যা এখানে এখনও সম্পাদনা করা যায় না। এটি যেমন আছে তেমনই থাকবে।';

  @override
  String get adminNavAcademicSetup => 'একাডেমিক সেটআপ';

  @override
  String get adminSetupLevels => 'স্তর';

  @override
  String get adminSetupGroups => 'বিভাগ';

  @override
  String get adminSetupCurricula => 'শিক্ষাক্রম';

  @override
  String get adminSetupBoards => 'বোর্ড';

  @override
  String get adminSetupMedia => 'মাধ্যম';

  @override
  String get adminSetupAdd => 'যোগ করুন';

  @override
  String get adminSetupEdit => 'সম্পাদনা';

  @override
  String get adminSetupEmpty => 'এখনও কিছু নেই';

  @override
  String get adminSetupKey => 'কী';

  @override
  String get adminSetupKeyHint => 'ইংরেজি ছোট হাতের অক্ষর, সংখ্যা ও আন্ডারস্কোর। পরে বদলানো যাবে না।';

  @override
  String get adminSetupPosition => 'ক্রম';

  @override
  String get adminSetupBoardType => 'বোর্ডের ধরন';

  @override
  String get adminSetupBoardGeneral => 'সাধারণ';

  @override
  String get adminSetupBoardMadrasah => 'মাদ্রাসা';

  @override
  String get adminSetupBoardTechnical => 'কারিগরি';

  @override
  String get adminSetupContentLocale => 'বিষয়বস্তুর ভাষা';

  @override
  String get adminSetupYearFrom => 'শুরুর বছর';

  @override
  String get adminSetupYearTo => 'শেষের বছর';

  @override
  String get adminSetupIsCurrent => 'চলমান শিক্ষাক্রম';

  @override
  String get adminSetupPickLevel => 'স্তর';

  @override
  String get librarySubtitle => 'আপনার বই, তাক আর পড়ার হিসাব এক জায়গায়';

  @override
  String get libraryTabBooks => 'বই';

  @override
  String get libraryTabShelves => 'তাক';

  @override
  String get libraryTabInsights => 'পরিসংখ্যান';

  @override
  String get libraryStatusWantToRead => 'পড়তে চাই';

  @override
  String get libraryStatusReading => 'পড়ছি';

  @override
  String get libraryStatusFinished => 'পড়া শেষ';

  @override
  String get libraryStatusLabel => 'পড়ার অবস্থা';

  @override
  String get libraryFilterFavorites => 'প্রিয়';

  @override
  String libraryFilterLabel(String label, int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$label ($countString)';
  }

  @override
  String get libraryFiltersLabel => 'বই বাছাই';

  @override
  String libraryBookCount(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countStringটি বই',
      zero: 'কোনো বই নেই',
    );
    return '$_temp0';
  }

  @override
  String get librarySort => 'বই সাজান';

  @override
  String get librarySortRecent => 'সম্প্রতি যোগ করা';

  @override
  String get librarySortUpdated => 'সম্প্রতি হালনাগাদ';

  @override
  String get librarySortTitle => 'নাম অনুযায়ী';

  @override
  String get libraryEmptyTitle => 'আপনার লাইব্রেরি এখনো খালি';

  @override
  String get libraryEmptyMessage =>
      'এক্সপ্লোর থেকে বই যোগ করুন, তারপর কোনটি পড়তে চান, পড়ছেন বা পড়া শেষ করেছেন তা গুছিয়ে রাখুন।';

  @override
  String get libraryExploreAction => 'বই খুঁজুন';

  @override
  String get libraryFilterEmpty => 'এখানে এখনো কোনো বই নেই';

  @override
  String get libraryFilterEmptyHint => 'এভাবে চিহ্নিত বইগুলো এখানে দেখা যাবে।';

  @override
  String get libraryFavorite => 'প্রিয়';

  @override
  String get libraryAddToLibrary => 'লাইব্রেরিতে যোগ করুন';

  @override
  String get libraryInLibrary => 'আপনার লাইব্রেরিতে আছে';

  @override
  String get librarySignInToAdd => 'লাইব্রেরিতে বই রাখতে সাইন ইন করুন।';

  @override
  String get libraryAdded => 'আপনার লাইব্রেরিতে যোগ হয়েছে';

  @override
  String get libraryRemove => 'লাইব্রেরি থেকে সরান';

  @override
  String get libraryRemoveConfirmTitle => 'বইটি সরাবেন?';

  @override
  String libraryRemoveConfirmMessage(String title) {
    return '“$title” আপনার লাইব্রেরি ও সব তাক থেকে সরে যাবে। বইটি ক্যাটালগে থাকবে, পরে আবার যোগ করতে পারবেন।';
  }

  @override
  String get libraryRemoveAction => 'সরান';

  @override
  String get libraryRemoved => 'লাইব্রেরি থেকে সরানো হয়েছে';

  @override
  String get libraryMarkFavorite => 'প্রিয় তালিকায় রাখুন';

  @override
  String get libraryUnmarkFavorite => 'প্রিয় তালিকা থেকে সরান';

  @override
  String get libraryOpenBookPage => 'বইয়ের পাতা দেখুন';

  @override
  String libraryAddedOn(String date) {
    return 'যোগ করেছেন $date';
  }

  @override
  String libraryStartedOn(String date) {
    return 'শুরু করেছেন $date';
  }

  @override
  String libraryFinishedOn(String date) {
    return 'শেষ করেছেন $date';
  }

  @override
  String get libraryUnknownAuthor => 'লেখকের নাম নেই';

  @override
  String libraryBookOptions(String title) {
    return '$title-এর অপশন';
  }

  @override
  String get errorLibraryFull => 'আপনার লাইব্রেরি সীমায় পৌঁছেছে। নতুন বই যোগ করতে একটি বই সরান।';

  @override
  String get errorCollectionLimit => 'আপনি সর্বোচ্চ সংখ্যক তাক তৈরি করে ফেলেছেন।';

  @override
  String get errorCollectionNameTaken => 'এই নামে আপনার একটি তাক আগে থেকেই আছে।';

  @override
  String get errorNotInLibrary => 'আগে বইটি লাইব্রেরিতে যোগ করুন।';

  @override
  String get shelvesNew => 'নতুন তাক';

  @override
  String shelvesCount(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countStringটি তাক',
    );
    return '$_temp0';
  }

  @override
  String get shelvesEmptyTitle => 'বইগুলো তাকে সাজিয়ে রাখুন';

  @override
  String get shelvesEmptyMessage =>
      '“ছুটির দিনের বই” বা “পরীক্ষার প্রস্তুতি”-র মতো তাক বানান, তারপর লাইব্রেরি থেকে বই যোগ করুন।';

  @override
  String get shelfName => 'তাকের নাম';

  @override
  String get shelfDescription => 'বিবরণ (ঐচ্ছিক)';

  @override
  String get shelfNameRequired => 'একটি নাম লিখুন।';

  @override
  String get shelfCreate => 'তৈরি করুন';

  @override
  String get shelfSave => 'সংরক্ষণ করুন';

  @override
  String get shelfEdit => 'তাক সম্পাদনা';

  @override
  String get shelfDelete => 'তাক মুছুন';

  @override
  String shelfDeleteConfirmTitle(String name) {
    return '“$name” মুছবেন?';
  }

  @override
  String get shelfDeleteConfirmMessage => 'তাকটি মুছে যাবে, তবে এর বইগুলো আপনার লাইব্রেরিতে থেকে যাবে।';

  @override
  String get shelfDeleteAction => 'মুছুন';

  @override
  String get shelfDeleted => 'তাক মুছে ফেলা হয়েছে';

  @override
  String shelfOptions(String name) {
    return '$name-এর অপশন';
  }

  @override
  String get shelfAddBooks => 'বই যোগ করুন';

  @override
  String get shelfEmptyTitle => 'এই তাকটি খালি';

  @override
  String get shelfEmptyMessage => 'লাইব্রেরি থেকে এই তাকে বই যোগ করুন।';

  @override
  String get shelfRemoveBook => 'তাক থেকে সরান';

  @override
  String shelfPickerTitle(String name) {
    return '$name-এ বই যোগ করুন';
  }

  @override
  String get shelfPickerEmpty => 'আপনার লাইব্রেরির সব বই এই তাকে আছে।';

  @override
  String get shelfPickerLibraryEmpty => 'আপনার লাইব্রেরি খালি। আগে এক্সপ্লোর থেকে বই যোগ করুন।';

  @override
  String get shelfDone => 'সম্পন্ন';

  @override
  String get shelfNone => 'আপনার এখনো কোনো তাক নেই।';

  @override
  String get insightsTotalBooks => 'মোট বই';

  @override
  String insightsFinishedYear(String year) {
    return '$year সালে শেষ';
  }

  @override
  String get insightsReadingNow => 'এখন পড়ছেন';

  @override
  String get insightsPagesFinished => 'শেষ করা পৃষ্ঠা';

  @override
  String insightsPagesUnknown(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countStringটি শেষ করা বইয়ের পৃষ্ঠাসংখ্যা জানা নেই',
    );
    return '$_temp0';
  }

  @override
  String get insightsFinishedTitle => 'শেষ করা বই';

  @override
  String get insightsPeriodWeek => 'সপ্তাহ';

  @override
  String get insightsPeriodMonth => 'মাস';

  @override
  String get insightsPeriodYear => 'বছর';

  @override
  String get insightsPeriodLifetime => 'সব সময়';

  @override
  String insightsFinishedInPeriod(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'এই সময়ে $countStringটি বই',
      zero: 'এই সময়ে কোনোটি নয়',
    );
    return '$_temp0';
  }

  @override
  String get insightsNothingFinished => 'এই সময়ে কোনো বই শেষ হয়নি';

  @override
  String get insightsNothingFinishedHint => 'কোনো বই শেষ হলে সেটিকে “পড়া শেষ” চিহ্নিত করুন, এখানে দেখা যাবে।';

  @override
  String insightsShareFinished(int percent) {
    final intl.NumberFormat percentNumberFormat = intl.NumberFormat.decimalPattern(localeName);
    final String percentString = percentNumberFormat.format(percent);

    return 'লাইব্রেরির $percentString% বই পড়া শেষ';
  }

  @override
  String get insightsGenresTitle => 'শীর্ষ বিভাগ';

  @override
  String get insightsGenresSubtitle => 'আপনার বইগুলোর ক্যাটালগ বিভাগ থেকে';

  @override
  String get insightsLanguagesTitle => 'ভাষা';

  @override
  String get insightsPublishersTitle => 'শীর্ষ প্রকাশক';

  @override
  String get insightsGrowthTitle => 'যোগ করা বই';

  @override
  String get insightsGrowthSubtitle => 'প্রতি মাসে, গত ১২ মাস';

  @override
  String get insightsLongestTitle => 'সবচেয়ে বড় বই';

  @override
  String get insightsShortestTitle => 'সবচেয়ে ছোট বই';

  @override
  String get insightsTopRatedTitle => 'পাঠকদের সর্বোচ্চ রেটিং';

  @override
  String get insightsTopRatedSubtitle => 'ক্যাটালগে গড় রেটিং';

  @override
  String insightsPages(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString পৃষ্ঠা',
    );
    return '$_temp0';
  }

  @override
  String insightsRatingValue(String rating, int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countStringটি রেটিংয়ে $rating',
    );
    return '$_temp0';
  }

  @override
  String get insightsNoCategories => 'আপনার কোনো বইয়ের বিভাগ এখনো নেই।';

  @override
  String get insightsNoPageCounts => 'আপনার কোনো বইয়ের পৃষ্ঠাসংখ্যা এখনো জানা নেই।';

  @override
  String get insightsNoRatings => 'আপনার কোনো বইয়ের রেটিং এখনো নেই।';

  @override
  String get insightsNoPublishers => 'আপনার কোনো বইয়ের প্রকাশকের নাম এখনো নেই।';

  @override
  String get insightsNoLanguages => 'আপনার কোনো বইয়ের ভাষা এখনো জানা নেই।';

  @override
  String get insightsOthers => 'অন্যান্য';

  @override
  String insightsChartItem(String label, int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$label: $countString';
  }

  @override
  String get insightsEmptyTitle => 'লাইব্রেরি বাড়লে পরিসংখ্যান দেখা যাবে';

  @override
  String get insightsEmptyMessage => 'কয়েকটি বই যোগ করে পড়ার অবস্থা হালনাগাদ করুন, তাহলে আপনার পড়ার ধরন দেখা যাবে।';

  @override
  String get settingsAccount => 'অ্যাকাউন্ট';

  @override
  String get settingsAppearance => 'প্রদর্শন';

  @override
  String get settingsPremium => 'প্রিমিয়াম';

  @override
  String get settingsPremiumUnavailable => 'প্রিমিয়াম প্ল্যান এখনো কেনা যাচ্ছে না।';

  @override
  String get settingsAbout => 'সম্পর্কে';

  @override
  String get settingsVersion => 'সংস্করণ';

  @override
  String get settingsGuestTitle => 'আপনি অতিথি হিসেবে দেখছেন';

  @override
  String get settingsGuestMessage => 'সব ডিভাইসে লাইব্রেরি, তাক আর পড়ার পরিসংখ্যান রাখতে সাইন ইন করুন।';

  @override
  String get settingsSignOutConfirmTitle => 'সাইন আউট করবেন?';

  @override
  String get settingsSignOutConfirmMessage =>
      'আপনার লাইব্রেরি অ্যাকাউন্টে সংরক্ষিত আছে। যেকোনো সময় আবার সাইন ইন করতে পারবেন।';

  @override
  String get settingsSavedOnDevice => 'ভাষা ও থিম এই ডিভাইসে সংরক্ষিত থাকে।';
}
