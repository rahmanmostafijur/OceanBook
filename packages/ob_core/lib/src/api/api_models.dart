import 'package:meta/meta.dart';

/// Error codes of the backend contract (backend/app/core/errors.py). Clients branch on codes, never on
/// messages. Unknown codes from a newer server map to [ApiErrorCode.unknown] rather than crashing.
enum ApiErrorCode {
  badRequest('BAD_REQUEST'),
  unauthenticated('UNAUTHENTICATED'),
  invalidCredentials('INVALID_CREDENTIALS'),
  tokenExpired('TOKEN_EXPIRED'),
  tokenRevoked('TOKEN_REVOKED'),
  forbidden('FORBIDDEN'),
  accountSuspended('ACCOUNT_SUSPENDED'),
  notFound('NOT_FOUND'),
  methodNotAllowed('METHOD_NOT_ALLOWED'),
  conflict('CONFLICT'),
  emailAlreadyRegistered('EMAIL_ALREADY_REGISTERED'),
  deviceLimitReached('DEVICE_LIMIT_REACHED'),
  mfaRequired('MFA_REQUIRED'),
  mfaInvalid('MFA_INVALID'),
  mfaAlreadyEnabled('MFA_ALREADY_ENABLED'),
  mfaEnrolmentTokenRequired('MFA_ENROLMENT_TOKEN_REQUIRED'),
  otpInvalid('OTP_INVALID'),
  otpExpired('OTP_EXPIRED'),
  otpCooldown('OTP_COOLDOWN'),
  phoneNotSupported('PHONE_NOT_SUPPORTED'),
  invalidIdentityToken('INVALID_IDENTITY_TOKEN'),
  identityProviderNotConfigured('IDENTITY_PROVIDER_NOT_CONFIGURED'),
  identityInUse('IDENTITY_IN_USE'),
  accountLinkRequired('ACCOUNT_LINK_REQUIRED'),
  lastIdentity('LAST_IDENTITY'),
  reauthRequired('REAUTH_REQUIRED'),
  payloadTooLarge('PAYLOAD_TOO_LARGE'),
  invalidStateTransition('INVALID_STATE_TRANSITION'),
  contentNotPublishable('CONTENT_NOT_PUBLISHABLE'),
  selfVerificationForbidden('SELF_VERIFICATION_FORBIDDEN'),
  recordLocked('RECORD_LOCKED'),
  slugTaken('SLUG_TAKEN'),
  inUse('IN_USE'),
  validationFailed('VALIDATION_FAILED'),
  rateLimited('RATE_LIMITED'),
  serviceUnavailable('SERVICE_UNAVAILABLE'),
  internalError('INTERNAL_ERROR'),
  unknown('UNKNOWN');

  const ApiErrorCode(this.wire);
  final String wire;

  static ApiErrorCode fromWire(String? value) =>
      ApiErrorCode.values.firstWhere((c) => c.wire == value, orElse: () => ApiErrorCode.unknown);
}

@immutable
class ApiErrorItem {
  const ApiErrorItem({required this.code, required this.message, this.field, this.details = const {}});

  factory ApiErrorItem.fromJson(Map<String, Object?> json) => ApiErrorItem(
    code: ApiErrorCode.fromWire(json['code'] as String?),
    message: (json['message'] as String?) ?? '',
    field: json['field'] as String?,
    details: (json['details'] as Map<String, Object?>?) ?? const {},
  );

  final ApiErrorCode code;
  final String message;
  final String? field;
  final Map<String, Object?> details;
}

/// Pagination metadata: cursor pages (feeds) or offset pages (admin tables).
@immutable
sealed class PageMeta {
  const PageMeta();

  static PageMeta? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    if (json.containsKey('next_cursor')) {
      return CursorPageMeta(
        nextCursor: json['next_cursor'] as String?,
        hasMore: (json['has_more'] as bool?) ?? false,
        limit: (json['limit'] as num?)?.toInt() ?? 0,
      );
    }
    return OffsetPageMeta(
      page: (json['page'] as num).toInt(),
      pageSize: (json['page_size'] as num).toInt(),
      total: (json['total'] as num).toInt(),
      totalIsEstimate: (json['total_is_estimate'] as bool?) ?? false,
    );
  }
}

final class CursorPageMeta extends PageMeta {
  const CursorPageMeta({required this.nextCursor, required this.hasMore, required this.limit});
  final String? nextCursor;
  final bool hasMore;
  final int limit;
}

final class OffsetPageMeta extends PageMeta {
  const OffsetPageMeta({required this.page, required this.pageSize, required this.total, this.totalIsEstimate = false});
  final int page;
  final int pageSize;
  final int total;
  final bool totalIsEstimate;
}

/// A successful response: decoded `data` plus `meta`.
@immutable
class ApiResponse<T> {
  const ApiResponse({required this.data, this.requestId, this.page});

  final T data;
  final String? requestId;
  final PageMeta? page;
}

/// Every failure the API layer can produce. UI code switches on these, never on Dio types.
@immutable
sealed class ApiFailure implements Exception {
  const ApiFailure({this.requestId});

  /// Correlates with server logs; shown in support/diagnostic views.
  final String? requestId;
}

/// The server answered with the error envelope.
final class ServerFailure extends ApiFailure {
  const ServerFailure({required this.status, required this.errors, super.requestId, this.retryAfter});

  final int status;
  final List<ApiErrorItem> errors;
  final Duration? retryAfter;

  ApiErrorCode get code => errors.isEmpty ? ApiErrorCode.unknown : errors.first.code;

  /// Field-level messages for forms (e.g. `{'email': 'value is not a valid email'}`).
  Map<String, String> get fieldErrors => {
    for (final e in errors)
      if (e.field != null) e.field!: e.message,
  };

  @override
  String toString() => 'ServerFailure($status ${code.wire}, request $requestId)';
}

/// No usable connection (offline, DNS, timeout). Safe to retry.
final class NetworkFailure extends ApiFailure {
  const NetworkFailure({required this.reason, super.requestId});
  final String reason;

  @override
  String toString() => 'NetworkFailure($reason)';
}

/// The session ended (refresh failed or tokens revoked). The app must sign the user in again.
final class SessionExpiredFailure extends ApiFailure {
  const SessionExpiredFailure({super.requestId});
}

/// The server sent something outside the contract (a bug, or a proxy error page).
final class UnexpectedResponseFailure extends ApiFailure {
  const UnexpectedResponseFailure({required this.status, required this.detail, super.requestId});
  final int? status;
  final String detail;

  @override
  String toString() => 'UnexpectedResponseFailure($status: $detail)';
}
