import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dsp/services/connection_profile_provider.dart';

void main() {
  test('saves and reloads connection profiles', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ConnectionProfileProvider();

    await provider.load();
    final saved = await provider.saveProfile(
      name: 'Rack DSP',
      host: '192.168.3.100',
      port: 9761,
    );

    expect(provider.selectedProfileId, saved.id);
    expect(provider.profiles.single.name, 'Rack DSP');

    final reloaded = ConnectionProfileProvider();
    await reloaded.load();

    expect(reloaded.selectedProfileId, saved.id);
    expect(reloaded.profiles.single.host, '192.168.3.100');
    expect(reloaded.profiles.single.port, 9761);
  });
}
