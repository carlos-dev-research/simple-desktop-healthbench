/// Connection, model and client settings for an evaluation run
/// (spec 002 FR-004–FR-008; research R2, R9).
library;

/// Both models are sampled at this temperature, as in the reference.
const double requestTemperature = 0.3;

/// Reasoning effort requested from a model. [none] sends no parameter at all,
/// for models that don't support it (spec 002 FR-005).
enum ReasoningEffort {
  none,
  low,
  medium,
  high;

  /// The `reasoning_effort` value to send, or `null` to leave it out.
  String? get requestValue => this == none ? null : name;

  static ReasoningEffort parse(String value) => values.firstWhere(
    (effort) => effort.name == value,
    orElse: () => throw FormatException('Unknown reasoning effort: $value'),
  );
}

/// A model and the reasoning effort to request from it.
class ModelSettings {
  ModelSettings({
    required this.name,
    this.reasoningEffort = ReasoningEffort.none,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'A model name is required');
    }
  }

  final String name;
  final ReasoningEffort reasoningEffort;

  @override
  String toString() => 'ModelSettings($name, ${reasoningEffort.name})';
}

/// Where requests go. The API key lives in memory only (Constitution III).
class ConnectionSettings {
  ConnectionSettings({required String baseUrl, required this.apiKey})
    : baseUrl = parseBaseUrl(baseUrl) {
    if (apiKey.trim().isEmpty) {
      throw ArgumentError('An API key is required');
    }
  }

  final Uri baseUrl;
  final String apiKey;

  /// Validates an OpenAI-compatible base URL: http(s) with a host and no user
  /// info, query or fragment, so it can never carry a secret (research R9).
  /// A trailing slash is removed.
  static Uri parseBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    String? problem;
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      problem = 'must be a full http(s) URL with a host';
    } else if (uri.scheme != 'http' && uri.scheme != 'https') {
      problem = 'must use http or https';
    } else if (uri.userInfo.isNotEmpty) {
      problem = 'must not contain a user name or password';
    } else if (uri.hasQuery) {
      problem = 'must not contain a query (?…)';
    } else if (uri.hasFragment) {
      problem = 'must not contain a fragment (#…)';
    }
    if (problem != null) {
      // The value is not echoed: it might contain a secret.
      throw ArgumentError('Base URL $problem');
    }
    var path = uri!.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return uri.replace(path: path);
  }

  @override
  String toString() => 'ConnectionSettings($baseUrl, apiKey: ***)';
}

/// Timeouts and retries; the defaults are the reference's (spec 002 FR-007,
/// research R2). Tests use short values.
class ClientOptions {
  const ClientOptions({
    this.timeout = const Duration(seconds: 180),
    this.maxRetries = 4,
    this.initialBackoff = const Duration(milliseconds: 500),
    this.maxBackoff = const Duration(seconds: 8),
    this.maxRetryAfter = const Duration(seconds: 60),
    this.maxResponseBytes = 16 * 1024 * 1024,
  });

  final Duration timeout;
  final int maxRetries;
  final Duration initialBackoff;
  final Duration maxBackoff;

  /// Server-requested waits (Retry-After) longer than this are ignored.
  final Duration maxRetryAfter;

  /// Responses larger than this are rejected (research R12).
  final int maxResponseBytes;
}
