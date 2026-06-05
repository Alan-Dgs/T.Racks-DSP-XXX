import 'package:flutter_test/flutter_test.dart';

import 'package:dsp/devices/t_racks408/providers/connection_provider.dart';
import 'package:dsp/devices/t_racks408/services/protocol_service.dart';
import 'package:dsp/devices/t_racks408/services/socket_service.dart';

void main() {
  test('exports debug status messages as plain text', () {
    final socket = SocketService();
    final provider = ConnectionProvider(socket, ProtocolService());

    provider.addDebugMessage('Connected - sending handshake...');

    expect(
      provider.exportDebugLogText(includeTimestamps: false),
      'Connected - sending handshake...',
    );

    provider.dispose();
    socket.dispose();
  });
}
