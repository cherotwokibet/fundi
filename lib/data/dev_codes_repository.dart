import 'package:supabase_flutter/supabase_flutter.dart';

/// A mock sign-in code, as shown on the test codes page.
typedef DevCode = ({String phone, String otp, DateTime createdAt});

/// A text message queued for a mechanic, shop or buyer (not sent while SMS
/// is mocked).
typedef DevMessage = ({String phone, String body, DateTime createdAt});

/// DEVELOPMENT ONLY. Reads the mock SMS codes with a secret key, so testers
/// can sign in from any device. Switched off before launch.
abstract class DevCodesRepository {
  /// Codes from the last 15 minutes, newest first. Throws if the key is wrong.
  Future<List<DevCode>> latest(String key);

  /// Alerts queued in the last 24 hours, newest first. Same key.
  Future<List<DevMessage>> messages(String key) async => const [];
}

class SupabaseDevCodesRepository implements DevCodesRepository {
  SupabaseDevCodesRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<DevCode>> latest(String key) async {
    final rows =
        await _client.rpc('dev_latest_codes', params: {'p_key': key}) as List;
    return [
      for (final r in rows)
        (
          phone: r['phone'] as String,
          otp: r['otp'] as String,
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        ),
    ];
  }

  @override
  Future<List<DevMessage>> messages(String key) async {
    final rows = await _client.rpc(
      'dev_latest_messages',
      params: {'p_key': key},
    ) as List;
    return [
      for (final r in rows)
        (
          phone: r['to_phone'] as String,
          body: r['body'] as String,
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        ),
    ];
  }
}

/// Sample mode has no SMS at all: every number accepts 123456.
class SampleDevCodesRepository extends DevCodesRepository {
  @override
  Future<List<DevCode>> latest(String key) async => [
    (
      phone: 'Any number (sample mode)',
      otp: '123456',
      createdAt: DateTime.now(),
    ),
  ];
}
