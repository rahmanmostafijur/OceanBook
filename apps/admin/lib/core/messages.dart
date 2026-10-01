import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

/// Maps API failures to localised staff-facing copy by error code (never by server text).
String adminFailureMessage(ObLocalizations l10n, Object error) {
  if (error is NetworkFailure) return l10n.errorNetwork;
  if (error is SessionExpiredFailure) return l10n.errorSessionExpired;
  if (error is! ServerFailure) return l10n.errorServer;
  return switch (error.code) {
    ApiErrorCode.forbidden => l10n.errorForbidden,
    ApiErrorCode.mfaRequired => l10n.errorMfaRequired,
    ApiErrorCode.notFound => l10n.errorNotFound,
    ApiErrorCode.validationFailed => l10n.errorValidation,
    ApiErrorCode.rateLimited => l10n.errorRateLimited,
    ApiErrorCode.contentNotPublishable => l10n.errorNotPublishable,
    ApiErrorCode.invalidStateTransition => l10n.errorInvalidTransition,
    ApiErrorCode.selfVerificationForbidden => l10n.errorSelfVerification,
    ApiErrorCode.recordLocked => l10n.errorRecordLocked,
    ApiErrorCode.slugTaken => l10n.errorSlugTaken,
    _ => l10n.errorServer,
  };
}

/// Publish-gate reason codes from `provenance.reasons` / `CONTENT_NOT_PUBLISHABLE` details.
String gateReason(ObLocalizations l10n, String code) => switch (code) {
  'NO_PROVENANCE' => l10n.adminGateNoProvenance,
  'NOT_VERIFIED' => l10n.adminGateNotVerified,
  'RIGHTS_NOT_CLEARED' => l10n.adminGateRightsNotCleared,
  'OUTSIDE_VALIDITY_WINDOW' => l10n.adminGateOutsideWindow,
  'TERRITORY_NOT_COVERED' => l10n.adminGateTerritory,
  'DISPUTED' => l10n.adminGateDisputed,
  _ => code,
};

/// The reasons a CONTENT_NOT_PUBLISHABLE failure carries, if any.
List<String> blockReasonsOf(Object error) {
  if (error is! ServerFailure || error.code != ApiErrorCode.contentNotPublishable) return const [];
  final details = error.errors.firstOrNull?.details ?? const {};
  return [for (final r in (details['reasons'] as List?) ?? const <Object?>[]) '$r'];
}

String statusLabel(ObLocalizations l10n, String status) => switch (status) {
  'draft' => l10n.adminStatusDraft,
  'in_review' => l10n.adminStatusInReview,
  'published' => l10n.adminStatusPublished,
  'unpublished' => l10n.adminStatusUnpublished,
  'archived' => l10n.adminStatusArchived,
  'withdrawn' => l10n.adminStatusWithdrawn,
  _ => status,
};

String accessLabel(ObLocalizations l10n, String level) => switch (level) {
  'free' => l10n.adminAccessFree,
  'registered' => l10n.adminAccessRegistered,
  _ => l10n.adminAccessEntitled,
};
