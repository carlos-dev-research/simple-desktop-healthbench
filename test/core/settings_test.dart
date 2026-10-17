// Connection and model settings (spec 002 FR-004, FR-005, FR-008; research R9).
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/settings.dart';

void main() {
  group('base URL', () {
    test('accepts http(s) and removes a trailing slash', () {
      expect(
        ConnectionSettings.parseBaseUrl('https://api.groq.com/openai/v1/'),
        Uri.parse('https://api.groq.com/openai/v1'),
      );
      expect(
        ConnectionSettings.parseBaseUrl('http://localhost:11434/v1'),
        Uri.parse('http://localhost:11434/v1'),
      );
    });

    for (final (url, why) in [
      ('ftp://example.com/v1', 'scheme'),
      ('https://user:pass@example.com/v1', 'user info'),
      ('https://example.com/v1?key=abc', 'query'),
      ('https://example.com/v1#x', 'fragment'),
      ('not a url', 'no host'),
      ('', 'empty'),
    ]) {
      test('rejects $why: $url', () {
        expect(
          () => ConnectionSettings.parseBaseUrl(url),
          throwsA(isA<ArgumentError>()),
        );
      });
    }
  });

  test('API key is required and never shown by toString', () {
    final settings = ConnectionSettings(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-secret-123',
    );
    expect(settings.toString(), isNot(contains('sk-secret-123')));
    expect(
      () => ConnectionSettings(baseUrl: 'https://a.b/v1', apiKey: ''),
      throwsA(isA<ArgumentError>()),
    );
  });

  group('reasoning effort', () {
    test('only low, medium and high are sent', () {
      expect(ReasoningEffort.none.requestValue, isNull);
      expect(ReasoningEffort.low.requestValue, 'low');
      expect(ReasoningEffort.medium.requestValue, 'medium');
      expect(ReasoningEffort.high.requestValue, 'high');
    });

    test('parses its names and rejects others', () {
      expect(ReasoningEffort.parse('medium'), ReasoningEffort.medium);
      expect(() => ReasoningEffort.parse('max'), throwsFormatException);
    });
  });

  test('model name is required', () {
    expect(() => ModelSettings(name: ' '), throwsA(isA<ArgumentError>()));
    expect(ModelSettings(name: 'm').reasoningEffort, ReasoningEffort.none);
  });

  test('client defaults match the reference (FR-007)', () {
    const options = ClientOptions();
    expect(options.timeout, const Duration(seconds: 180));
    expect(options.maxRetries, 4);
    expect(requestTemperature, 0.3);
  });
}
