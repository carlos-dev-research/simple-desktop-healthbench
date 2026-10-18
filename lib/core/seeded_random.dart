/// A deterministic pseudo-random generator whose sequence is fixed by its
/// definition: SplitMix64 (Steele, Lea & Flood, 2014; Vigna's splitmix64.c).
///
/// `dart:math`'s `Random(seed)` doesn't promise the same sequence across Dart
/// versions, so reproducible results (spec 006 bootstrap, spec 005 samples)
/// use this instead. Relies on 64-bit wrapping integers (Dart native).
library;

class SplitMix64 {
  SplitMix64(int seed) : _state = seed;

  int _state;

  /// The next 64 random bits, as a signed 64-bit int.
  int nextInt64() {
    _state += 0x9E3779B97F4A7C15;
    var z = _state;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    return z ^ (z >>> 31);
  }

  static const int _top = 1 << 53;

  /// A uniform int in `[0, bound)`, without modulo bias (53-bit draws with
  /// rejection). [bound] must be between 1 and 2^53.
  int nextIntBelow(int bound) {
    if (bound < 1 || bound > _top) {
      throw ArgumentError.value(bound, 'bound', 'Must be in 1..2^53');
    }
    final limit = _top - _top % bound;
    while (true) {
      final r = nextInt64() >>> 11;
      if (r < limit) return r % bound;
    }
  }

  /// A uniform double in `[0, 1)`.
  double nextDouble() => (nextInt64() >>> 11) / _top;
}
