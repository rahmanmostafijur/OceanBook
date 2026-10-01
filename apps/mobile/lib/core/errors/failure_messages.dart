import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

/// Turns an [ApiFailure] into a localised, user-facing sentence. Branches on server *codes* only.
String failureMessage(ObLocalizations l10n, Object error) {
  return switch (error) {
    NetworkFailure() => l10n.errorNetwork,
    SessionExpiredFailure() => l10n.errorSessionExpired,
    ServerFailure(:final code) => switch (code) {
      ApiErrorCode.invalidCredentials => l10n.errorInvalidCredentials,
      ApiErrorCode.rateLimited => l10n.errorRateLimited,
      ApiErrorCode.forbidden => l10n.errorForbidden,
      ApiErrorCode.notFound => l10n.errorNotFound,
      ApiErrorCode.validationFailed => l10n.errorValidation,
      ApiErrorCode.emailAlreadyRegistered => l10n.errorEmailTaken,
      ApiErrorCode.otpInvalid => l10n.errorOtpInvalid,
      ApiErrorCode.otpExpired => l10n.errorOtpExpired,
      ApiErrorCode.otpCooldown => l10n.errorOtpCooldown,
      ApiErrorCode.phoneNotSupported => l10n.errorPhoneNotSupported,
      ApiErrorCode.accountLinkRequired => l10n.errorAccountLinkRequired,
      ApiErrorCode.identityProviderNotConfigured => l10n.errorProviderUnavailable,
      ApiErrorCode.mfaInvalid => l10n.errorMfaInvalid,
      ApiErrorCode.mfaRequired => l10n.errorMfaRequired,
      ApiErrorCode.reauthRequired => l10n.errorReauthRequired,
      ApiErrorCode.accountSuspended => l10n.errorAccountSuspended,
      ApiErrorCode.deviceLimitReached => l10n.errorDeviceLimit,
      ApiErrorCode.tokenExpired ||
      ApiErrorCode.tokenRevoked ||
      ApiErrorCode.unauthenticated => l10n.errorSessionExpired,
      _ => l10n.errorServer,
    },
    _ => l10n.errorServer,
  };
}
