import 'package:ob_l10n/ob_l10n.dart';

String sourceKindLabel(ObLocalizations l10n, String kind) => switch (kind) {
  'education_board' => l10n.adminSourceEducationBoard,
  'publisher' => l10n.adminSourcePublisher,
  'author' => l10n.adminSourceAuthor,
  'government' => l10n.adminSourceGovernment,
  'website' => l10n.adminSourceWebsite,
  'partner' => l10n.adminSourcePartner,
  'internal' => l10n.adminSourceInternal,
  _ => l10n.adminSourceOther,
};

String licenseLabel(ObLocalizations l10n, String type) => switch (type) {
  'licensed_commercial' => l10n.adminLicenseCommercial,
  'permission_granted' => l10n.adminLicensePermission,
  'public_domain' => l10n.adminLicensePublicDomain,
  'government_open' => l10n.adminLicenseGovernmentOpen,
  'cc_by' => 'CC BY',
  'cc_by_sa' => 'CC BY-SA',
  'cc_by_nc' => 'CC BY-NC',
  'original_work' => l10n.adminLicenseOriginal,
  _ => l10n.adminLicenseUnknown,
};

String rightsLabel(ObLocalizations l10n, String status) => switch (status) {
  'pending' => l10n.adminRightsPending,
  'cleared' => l10n.adminRightsCleared,
  'restricted' => l10n.adminRightsRestricted,
  'expired' => l10n.adminRightsExpired,
  'disputed' => l10n.adminRightsDisputed,
  _ => l10n.adminLicensePublicDomain,
};

String verificationLabel(ObLocalizations l10n, String status) => switch (status) {
  'pending' => l10n.adminVerificationPending,
  'verified' => l10n.adminVerificationVerified,
  'rejected' => l10n.adminVerificationRejected,
  _ => l10n.adminVerificationUnverified,
};
