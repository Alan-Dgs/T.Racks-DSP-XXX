import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// Services
import 'devices/t_racks408/services/socket_service.dart';
import 'devices/t_racks408/services/protocol_service.dart';

// Providers
import 'devices/t_racks408/providers/device_provider.dart';
import 'devices/t_racks408/providers/connection_provider.dart';

// Widgets
import 'devices/t_racks408/widgets/gain_tab.dart';
import 'devices/t_racks408/widgets/dynamics_tabs.dart';
import 'devices/t_racks408/widgets/geq_tab.dart';
import 'devices/t_racks408/widgets/matrix_tab.dart';
import 'devices/t_racks408/widgets/peq_tab.dart';
import 'devices/t_racks408/widgets/rta_tab.dart';

// Overlays
import 'devices/t_racks408/overlays/settings_overlay.dart';

// RTA
import 'services/rta_settings_provider.dart';
import 'services/connection_profile_provider.dart';

void main() {
  runApp(buildApp());
}

Widget buildApp() {
  return MultiProvider(
    providers: [
      // Services (singletons)
      ChangeNotifierProvider(create: (_) => SocketService()),
      Provider(create: (_) => ProtocolService()),
      ChangeNotifierProvider(create: (_) => RtaSettingsProvider()),
      ChangeNotifierProvider(create: (_) => ConnectionProfileProvider()),

      // State providers
      ChangeNotifierProxyProvider<SocketService, DeviceProvider>(
        create: (context) => DeviceProvider(
          context.read<SocketService>(),
          context.read<ProtocolService>(),
        ),
        update: (context, socket, previous) =>
            previous ?? DeviceProvider(socket, context.read<ProtocolService>()),
      ),
      ChangeNotifierProxyProvider<SocketService, ConnectionProvider>(
        create: (context) {
          final provider = ConnectionProvider(
            context.read<SocketService>(),
            context.read<ProtocolService>(),
          );
          provider.deviceProvider = context.read<DeviceProvider>();
          return provider;
        },
        update: (context, socket, previous) {
          if (previous != null) {
            previous.deviceProvider = context.read<DeviceProvider>();
            return previous;
          }
          final provider = ConnectionProvider(
            socket,
            context.read<ProtocolService>(),
          );
          provider.deviceProvider = context.read<DeviceProvider>();
          return provider;
        },
      ),
    ],
    child: const MyApp(),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Monokai color palette
    const monokaiBg = Color(0xFF272822);
    const monokaiSurface = Color(0xFF3E3D32);
    const monokaiComment = Color(0xFF75715E);
    const monokaiGreen = Color(0xFFA6E22E);
    const monokaiPink = Color(0xFFF92672);
    const monokaiOrange = Color(0xFFFD971F);
    const monokaiPurple = Color(0xFFAE81FF);
    const monokaiFg = Color(0xFFF8F8F2);

    final monokaiScheme = ColorScheme.dark(
      surface: monokaiBg,
      primary: monokaiGreen,
      secondary: monokaiPurple,
      tertiary: monokaiOrange,
      error: monokaiPink,
      onSurface: monokaiFg,
      onPrimary: monokaiBg,
      onSecondary: monokaiFg,
      onError: monokaiFg,
      surfaceContainerHighest: monokaiSurface,
      outline: monokaiComment,
    );

    return MaterialApp(
      title: 'DSP408 Controller',
      theme: ThemeData(
        colorScheme: monokaiScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: monokaiBg,
        textTheme: GoogleFonts.robotoMonoTextTheme(
          ThemeData.dark().textTheme,
        ).apply(bodyColor: monokaiFg, displayColor: monokaiFg),
        appBarTheme: const AppBarTheme(
          backgroundColor: monokaiSurface,
          foregroundColor: monokaiFg,
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: monokaiGreen,
          unselectedLabelColor: monokaiComment,
          indicatorColor: monokaiGreen,
        ),
        cardTheme: CardThemeData(color: monokaiSurface, elevation: 2),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: monokaiSurface,
            foregroundColor: monokaiFg,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: const OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: monokaiComment),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: monokaiGreen),
          ),
          labelStyle: TextStyle(color: monokaiComment),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: monokaiSurface,
          titleTextStyle: TextStyle(
            color: monokaiOrange,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        dropdownMenuTheme: const DropdownMenuThemeData(
          textStyle: TextStyle(color: monokaiFg),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? monokaiGreen
                : Colors.transparent,
          ),
          checkColor: WidgetStateProperty.all(monokaiBg),
          side: BorderSide(color: monokaiComment),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: monokaiSurface,
          contentTextStyle: TextStyle(color: monokaiFg),
        ),
      ),
      home: const MyHomePage(title: 'DSP408 Controller'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // Text controllers
  final TextEditingController _ipController = TextEditingController(
    text: '192.168.3.100',
  );
  final TextEditingController _portController = TextEditingController(
    text: '9761',
  );
  final TextEditingController _profileNameController = TextEditingController(
    text: 'DSP',
  );

  // Debug log scroll
  final ScrollController _debugScrollController = ScrollController();
  bool _debugAtTop = true;
  int _lastMessageCount = 0;

  // UI state (local only)
  bool _showConnect = false;
  bool _showDebug = false;
  bool _showTimestamps = false;
  String? _selectedPreset;
  String? _lastSyncedPreset;
  String? _lastAppliedConnectionProfileId;

  static const _tabs = [
    'Gain',
    'Gate',
    'Comp',
    'Limit',
    'Delay',
    'Matrix',
    'GEQ',
    'PEQ',
    'RTA',
  ];

  @override
  void initState() {
    super.initState();
    _debugScrollController.addListener(() {
      final pos = _debugScrollController.position;
      // With reverse:true + .add(), newest messages are at maxScrollExtent (top)
      _debugAtTop = pos.pixels >= pos.maxScrollExtent - 10.0;
    });
    // Load saved channel aliases
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceProvider>().loadAliases();
      context.read<ConnectionProfileProvider>().load();
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _profileNameController.dispose();
    _debugScrollController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    final portText = _portController.text.trim();

    if (ip.isEmpty) {
      _showError('Please enter an IP address');
      return;
    }

    final port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) {
      _showError('Invalid port number');
      return;
    }

    try {
      await context.read<ConnectionProvider>().connect(ip, port);
    } catch (e) {
      _showError('Failed to connect: $e');
    }
  }

  Future<void> _disconnect() async {
    await context.read<ConnectionProvider>().disconnect();
  }

  Future<void> _saveConnectionProfile() async {
    final name = _profileNameController.text.trim();
    final host = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (host.isEmpty) {
      _showError('Please enter an IP address');
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      _showError('Invalid port number');
      return;
    }

    final profiles = context.read<ConnectionProfileProvider>();
    await profiles.saveProfile(
      id: profiles.selectedProfileId,
      name: name.isEmpty ? host : name,
      host: host,
      port: port,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Connection profile saved')));
  }

  Future<void> _deleteConnectionProfile() async {
    final profiles = context.read<ConnectionProfileProvider>();
    if (profiles.selectedProfileId == null) return;
    await profiles.deleteSelectedProfile();
    final selected = profiles.selectedProfile;
    if (selected != null) {
      _applyConnectionProfile(selected);
    }
  }

  void _applyConnectionProfile(ConnectionProfile profile) {
    _profileNameController.text = profile.name;
    _ipController.text = profile.host;
    _portController.text = profile.port.toString();
    _lastAppliedConnectionProfileId = profile.id;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _copyDebugLog(ConnectionProvider connectionProvider) async {
    final logText = connectionProvider.exportDebugLogText(
      includeTimestamps: _showTimestamps,
    );
    if (logText.isEmpty) {
      _showError('No debug messages to copy');
      return;
    }

    await Clipboard.setData(ClipboardData(text: logText));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Debug log copied')));
  }

  /// Format current preset with U-number, e.g. "U20: Test"
  String _currentPresetLabel(DeviceProvider dp) {
    final name = dp.currentPreset;
    // Find the preset index whose name matches
    for (final entry in dp.presets.entries) {
      if (entry.value == name) {
        final uNum = 'U${(entry.key + 1).toString().padLeft(2, '0')}';
        return '$uNum - $name';
      }
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final connectionProvider = context.watch<ConnectionProvider>();
    final deviceProvider = context.watch<DeviceProvider>();
    final profileProvider = context.watch<ConnectionProfileProvider>();

    final selectedConnectionProfile = profileProvider.selectedProfile;
    if (selectedConnectionProfile != null &&
        selectedConnectionProfile.id != _lastAppliedConnectionProfileId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyConnectionProfile(selectedConnectionProfile);
      });
    }

    // Sync dropdown to device preset only when the device preset changes
    final currentName = deviceProvider.currentPreset;
    if (currentName != _lastSyncedPreset) {
      _lastSyncedPreset = currentName;
      if (connectionProvider.isConnected && deviceProvider.presets.isNotEmpty) {
        final matchIndex = deviceProvider.presets.entries
            .where((e) => e.value == currentName)
            .map((e) => e.key)
            .firstOrNull;
        if (matchIndex != null) {
          _selectedPreset = matchIndex.toString();
        }
      }
    }

    // Auto-scroll debug log when at the top and new messages arrive
    final messageCount = connectionProvider.debugEntries.length;
    if (messageCount != _lastMessageCount) {
      _lastMessageCount = messageCount;
      if (_debugAtTop && _debugScrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_debugScrollController.hasClients) {
            _debugScrollController.jumpTo(
              _debugScrollController.position.maxScrollExtent,
            );
          }
        });
      }
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final narrow = screenWidth < 500;

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          title: Text(widget.title),
          actions: narrow
              ? [
                  IconButton(
                    icon: Icon(
                      _showConnect ? Icons.link_off : Icons.link,
                      size: 20,
                    ),
                    tooltip: 'Connection',
                    onPressed: () =>
                        setState(() => _showConnect = !_showConnect),
                  ),
                  IconButton(
                    icon: Icon(
                      _showDebug ? Icons.bug_report : Icons.bug_report_outlined,
                      size: 20,
                    ),
                    tooltip: 'Debug',
                    onPressed: () => setState(() => _showDebug = !_showDebug),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, size: 20),
                    tooltip: 'Settings',
                    onPressed: () => SettingsOverlay.showSettingsOverlay(
                      context,
                      context.read<SocketService>(),
                    ),
                  ),
                ]
              : null,
          bottom: TabBar(
            isScrollable: true,
            tabs: _tabs.map((name) => Tab(text: name)).toList(),
          ),
        ),
        body: Column(
          children: [
            // Connection status bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    connectionProvider.isConnected
                        ? Icons.check_circle
                        : Icons.cancel,
                    color: connectionProvider.isConnected
                        ? const Color(0xFFA6E22E)
                        : const Color(0xFFF92672),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    connectionProvider.connectionStatus,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  if (connectionProvider.isConnected) ...[
                    Text(
                      'TX: ${connectionProvider.packetsSent}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'RX: ${connectionProvider.packetsReceived}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),

            // Connection panel
            if (_showConnect)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 500;
                      return Column(
                        children: [
                          _buildConnectionProfileControls(
                            profileProvider,
                            narrow,
                          ),
                          const SizedBox(height: 8),
                          if (narrow) ...[
                            // Stacked layout for narrow screens
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _ipController,
                                    decoration: const InputDecoration(
                                      labelText: 'IP Address',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 80,
                                  child: TextField(
                                    controller: _portController,
                                    decoration: const InputDecoration(
                                      labelText: 'Port',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed:
                                        connectionProvider.isSocketConnected ||
                                            connectionProvider.isLoading
                                        ? null
                                        : _connect,
                                    child: const Text('Connect'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed:
                                        connectionProvider.isSocketConnected ||
                                            connectionProvider.isLoading
                                        ? _disconnect
                                        : null,
                                    child: const Text('Disconnect'),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            // Wide layout for desktop
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _ipController,
                                    decoration: const InputDecoration(
                                      labelText: 'IP Address',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 100,
                                  child: TextField(
                                    controller: _portController,
                                    decoration: const InputDecoration(
                                      labelText: 'Port',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed:
                                      connectionProvider.isSocketConnected
                                      ? null
                                      : _connect,
                                  child: const Text('Connect'),
                                ),
                                const SizedBox(width: 4),
                                ElevatedButton(
                                  onPressed:
                                      connectionProvider.isSocketConnected
                                      ? _disconnect
                                      : null,
                                  child: const Text('Disconnect'),
                                ),
                              ],
                            ),
                          ],
                          // Inner control panel, used for Gain, Comp, etc.
                          if (connectionProvider.isConnected)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: DropdownButton<int>(
                                      value: _selectedPreset != null
                                          ? int.tryParse(_selectedPreset!)
                                          : null,
                                      hint: const Text('Select Preset'),
                                      isExpanded: true,
                                      items:
                                          deviceProvider.presets.entries.map((
                                            entry,
                                          ) {
                                            final label =
                                                'U${(entry.key + 1).toString().padLeft(2, '0')}';
                                            return DropdownMenuItem<int>(
                                              value: entry.key,
                                              child: Text(
                                                '$label: ${entry.value}',
                                              ),
                                            );
                                          }).toList()..sort(
                                            (a, b) =>
                                                a.value!.compareTo(b.value!),
                                          ),
                                      onChanged: (value) => setState(
                                        () =>
                                            _selectedPreset = value?.toString(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _selectedPreset != null
                                        ? () async {
                                            final index = int.tryParse(
                                              _selectedPreset!,
                                            );
                                            if (index == null) return;
                                            final name =
                                                deviceProvider.presets[index] ??
                                                'Preset';
                                            final uNum =
                                                'U${(index + 1).toString().padLeft(2, '0')}';
                                            final confirmed =
                                                await showDialog<bool>(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
                                                    title: const Text(
                                                      'Save Preset',
                                                    ),
                                                    content: Text(
                                                      'Save current settings to $uNum "$name"?',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              ctx,
                                                              false,
                                                            ),
                                                        child: const Text(
                                                          'Cancel',
                                                        ),
                                                      ),
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              ctx,
                                                              true,
                                                            ),
                                                        child: const Text(
                                                          'Save',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                            if (confirmed == true &&
                                                context.mounted) {
                                              context
                                                  .read<ConnectionProvider>()
                                                  .savePreset(index, name);
                                            }
                                          }
                                        : null,
                                    child: const Text(
                                      'Save',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _selectedPreset != null
                                        ? () {
                                            final index = int.tryParse(
                                              _selectedPreset!,
                                            );
                                            if (index != null) {
                                              context
                                                  .read<ConnectionProvider>()
                                                  .loadPreset(index);
                                            }
                                          }
                                        : null,
                                    child: const Text(
                                      'Load',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  if (!narrow) ...[
                                    const SizedBox(width: 16),
                                    const Icon(
                                      Icons.music_note,
                                      color: Color(0xFFA6E22E),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Current: ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      _currentPresetLabel(deviceProvider),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          if (connectionProvider.isConnected && narrow)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.music_note,
                                    color: Color(0xFFA6E22E),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Current: ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _currentPresetLabel(deviceProvider),
                                      style: const TextStyle(fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),

            // Tab content with initialization overlay
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: _tabs.map((name) {
                      if (name == 'Gain') {
                        return GainTab(deviceProvider: deviceProvider);
                      }
                      if (name == 'Gate') {
                        return GateTab(deviceProvider: deviceProvider);
                      }
                      if (name == 'Comp') {
                        return CompressorTab(deviceProvider: deviceProvider);
                      }
                      if (name == 'Limit') {
                        return LimiterTab(deviceProvider: deviceProvider);
                      }
                      if (name == 'Delay') {
                        return DelayTab(deviceProvider: deviceProvider);
                      }
                      if (name == 'Matrix') {
                        return MatrixTab(deviceProvider: deviceProvider);
                      }
                      if (name == 'GEQ') {
                        return GeqTab(deviceProvider: deviceProvider);
                      }
                      if (name == 'PEQ') {
                        return PeqTab(deviceProvider: deviceProvider);
                      }
                      if (name == 'RTA') {
                        return const RtaTab();
                      }
                      return Center(child: Text('$name Tab'));
                    }).toList(),
                  ),
                  if (!connectionProvider.isConnected ||
                      connectionProvider.isLoading)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (connectionProvider.isLoading) ...[
                              if (connectionProvider.isSocketConnected) ...[
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: CircularProgressIndicator(
                                    value: connectionProvider.initProgress,
                                    color: const Color(0xFFA6E22E),
                                    backgroundColor: const Color(0xFF75715E),
                                    strokeWidth: 4,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Text(
                                connectionProvider.isSocketConnected &&
                                        connectionProvider.isLoading
                                    ? 'Initializing... ${(connectionProvider.initProgress * 100).toInt()}%'
                                    : "Establishing Connection...",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ] else
                              const Text(
                                'Not Connected',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white70,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Debug panel
            if (_showDebug)
              SizedBox(
                height: 200,
                child: Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          children: [
                            const Text(
                              'Debug Messages',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              height: 24,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _debugCheckbox(
                                    value: connectionProvider.showRx,
                                    label: 'Rx',
                                    onChanged: () =>
                                        connectionProvider.toggleShowRx(),
                                  ),
                                  _debugCheckbox(
                                    value: connectionProvider.showTx,
                                    label: 'Tx',
                                    onChanged: () =>
                                        connectionProvider.toggleShowTx(),
                                  ),
                                  _debugCheckbox(
                                    value: connectionProvider.showDecoded,
                                    label: 'Decode',
                                    onChanged: () =>
                                        connectionProvider.toggleShowDecoded(),
                                  ),
                                  _debugCheckbox(
                                    value: _showTimestamps,
                                    label: 'Time',
                                    onChanged: () => setState(
                                      () => _showTimestamps = !_showTimestamps,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy debug log',
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () =>
                                  _copyDebugLog(connectionProvider),
                            ),
                            IconButton(
                              tooltip: 'Clear debug messages',
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => context
                                  .read<ConnectionProvider>()
                                  .clearMessages(),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _debugScrollController,
                          reverse: true,
                          itemCount: connectionProvider.debugEntries.length,
                          itemBuilder: (context, index) {
                            final entry =
                                connectionProvider.debugEntries[index];
                            final msg = entry.display(
                              connectionProvider.showDecoded,
                            );
                            final display = _showTimestamps
                                ? '[${entry.timestamp.toStringAsFixed(4)}] $msg'
                                : msg;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 1,
                              ),
                              child: Text(
                                display,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom controls (desktop only — on mobile these are in the app bar)
            if (!narrow)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () =>
                          setState(() => _showConnect = !_showConnect),
                      icon: Icon(
                        _showConnect
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 18,
                      ),
                      label: const Text(
                        'Connection',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _showDebug = !_showDebug),
                      icon: Icon(
                        _showDebug
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 18,
                      ),
                      label: const Text(
                        'Debug',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => SettingsOverlay.showSettingsOverlay(
                        context,
                        context.read<SocketService>(),
                      ),
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text(
                        'Settings',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _debugCheckbox({
    required bool value,
    required String label,
    required VoidCallback onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: (_) => onChanged(),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildConnectionProfileControls(
    ConnectionProfileProvider profiles,
    bool narrow,
  ) {
    final profileItems = profiles.profiles
        .map(
          (profile) => DropdownMenuItem<String>(
            value: profile.id,
            child: Text('${profile.name} (${profile.host}:${profile.port})'),
          ),
        )
        .toList();

    final profileDropdown = DropdownButton<String>(
      value: profiles.selectedProfileId,
      hint: const Text('Connection Profile'),
      isExpanded: true,
      items: profileItems,
      onChanged: (id) async {
        await profiles.selectProfile(id);
        final selected = profiles.selectedProfile;
        if (selected != null) _applyConnectionProfile(selected);
      },
    );

    final nameField = TextField(
      controller: _profileNameController,
      decoration: const InputDecoration(
        labelText: 'Profile Name',
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );

    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Save connection profile',
          onPressed: _saveConnectionProfile,
          icon: const Icon(Icons.save, size: 20),
        ),
        IconButton(
          tooltip: 'Delete selected connection profile',
          onPressed: profiles.selectedProfileId == null
              ? null
              : _deleteConnectionProfile,
          icon: const Icon(Icons.delete_outline, size: 20),
        ),
      ],
    );

    if (narrow) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: profileDropdown),
              buttons,
            ],
          ),
          const SizedBox(height: 8),
          nameField,
        ],
      );
    }

    return Row(
      children: [
        SizedBox(width: 280, child: profileDropdown),
        const SizedBox(width: 8),
        Expanded(child: nameField),
        const SizedBox(width: 4),
        buttons,
      ],
    );
  }
}
