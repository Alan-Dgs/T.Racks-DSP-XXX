import 'package:flutter/material.dart';
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
import 'devices/t_racks408/widgets/matrix_tab.dart';

// Overlays
import 'devices/t_racks408/overlays/settings_overlay.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        // Services (singletons)
        ChangeNotifierProvider(create: (_) => SocketService()),
        Provider(create: (_) => ProtocolService()),

        // State providers
        ChangeNotifierProxyProvider<SocketService, DeviceProvider>(
          create: (context) => DeviceProvider(
            context.read<SocketService>(),
            context.read<ProtocolService>(),
          ),
          update: (context, socket, previous) =>
              previous ??
              DeviceProvider(
                socket,
                context.read<ProtocolService>(),
              ),
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
    ),
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
        cardTheme: CardThemeData(
          color: monokaiSurface,
          elevation: 2,
        ),
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
              fontWeight: FontWeight.bold),
        ),
        dropdownMenuTheme: const DropdownMenuThemeData(
          textStyle: TextStyle(color: monokaiFg),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? monokaiGreen
                  : Colors.transparent),
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
  final TextEditingController _ipController =
      TextEditingController(text: '192.168.3.100');
  final TextEditingController _portController =
      TextEditingController(text: '9761');

  // Debug log scroll
  final ScrollController _debugScrollController = ScrollController();
  bool _debugAtTop = true;
  int _lastMessageCount = 0;

  // UI state (local only)
  bool _showConnect = false;
  bool _showDebug = false;
  bool _showTimestamps = false;
  String? _selectedPreset;

  static const _tabs = [
    'Gain', 'Gate', 'Comp', 'Limit', 'Delay', 'Matrix', 'GEQ',
    'In A', 'In B', 'In C', 'In D',
    'Out 1', 'Out 2', 'Out 3', 'Out 4', 'Out 5', 'Out 6', 'Out 7', 'Out 8',
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
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionProvider = context.watch<ConnectionProvider>();
    final deviceProvider = context.watch<DeviceProvider>();

    // Auto-scroll debug log when at the top and new messages arrive
    final messageCount = connectionProvider.receivedMessages.length;
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
                    icon: Icon(_showConnect ? Icons.link_off : Icons.link,
                        size: 20),
                    tooltip: 'Connection',
                    onPressed: () =>
                        setState(() => _showConnect = !_showConnect),
                  ),
                  IconButton(
                    icon: Icon(_showDebug ? Icons.bug_report : Icons.bug_report_outlined,
                        size: 20),
                    tooltip: 'Debug',
                    onPressed: () =>
                        setState(() => _showDebug = !_showDebug),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, size: 20),
                    tooltip: 'Settings',
                    onPressed: () => SettingsOverlay.showSettingsOverlay(
                        context, context.read<SocketService>()),
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
                        fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const Spacer(),
                  if (connectionProvider.isConnected) ...[
                    Text('TX: ${connectionProvider.packetsSent}',
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 12),
                    Text('RX: ${connectionProvider.packetsReceived}',
                        style: const TextStyle(fontSize: 12)),
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
                                    onPressed: connectionProvider.isSocketConnected
                                        ? null
                                        : _connect,
                                    child: const Text('Connect'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: connectionProvider.isSocketConnected
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
                                  onPressed: connectionProvider.isSocketConnected
                                      ? null
                                      : _connect,
                                  child: const Text('Connect'),
                                ),
                                const SizedBox(width: 4),
                                ElevatedButton(
                                  onPressed: connectionProvider.isSocketConnected
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
                                      items: deviceProvider.presets.entries
                                          .map((entry) {
                                        final label =
                                            'U${(entry.key + 1).toString().padLeft(2, '0')}';
                                        return DropdownMenuItem<int>(
                                          value: entry.key,
                                          child: Text('$label: ${entry.value}'),
                                        );
                                      }).toList()
                                        ..sort(
                                            (a, b) => a.value!.compareTo(b.value!)),
                                      onChanged: (value) => setState(
                                          () => _selectedPreset = value?.toString()),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _selectedPreset != null
                                        ? () {
                                            final index = int.tryParse(_selectedPreset!);
                                            if (index != null) {
                                              context.read<ConnectionProvider>().loadPreset(index);
                                            }
                                          }
                                        : null,
                                    child: const Text('Load', style: TextStyle(fontSize: 12)),
                                  ),
                                  if (!narrow) ...[
                                    const SizedBox(width: 16),
                                    const Icon(Icons.music_note,
                                        color: Color(0xFFA6E22E)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Current: ${deviceProvider.currentPreset}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 12),
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
                                  const Icon(Icons.music_note,
                                      color: Color(0xFFA6E22E), size: 16),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Current: ${deviceProvider.currentPreset}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 12),
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
                    children: _tabs.map((name) {
                      if (name == 'Gain') {
                        return GainTab(deviceProvider: deviceProvider);
                      }
                      if (name == 'Matrix') {
                        return MatrixTab(deviceProvider: deviceProvider);
                      }
                      return Center(child: Text('$name Tab'));
                    }).toList(),
                  ),
                  if (!connectionProvider.isConnected || connectionProvider.isLoading)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (connectionProvider.isLoading) ...[
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
                              const SizedBox(height: 16),
                              Text(
                                  'Initializing... ${(connectionProvider.initProgress * 100).toInt()}%',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                            ] else
                              const Text('Not Connected',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white70)),
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
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          children: [
                            const Text('Debug Messages',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12)),
                            const Spacer(),
                            SizedBox(
                              height: 24,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: _showTimestamps,
                                    onChanged: (v) => setState(
                                        () => _showTimestamps = v ?? false),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const Text('Time',
                                      style: TextStyle(fontSize: 11)),
                                ],
                              ),
                            ),
                            IconButton(
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
                          itemCount:
                              connectionProvider.receivedMessages.length,
                          itemBuilder: (context, index) {
                            final msg =
                                connectionProvider.receivedMessages[index];
                            final timestamps =
                                connectionProvider.messageTimestamps;
                            final display = _showTimestamps &&
                                    index < timestamps.length
                                ? '[${timestamps[index].toStringAsFixed(4)}] $msg'
                                : msg;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 1),
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
                          size: 18),
                      label: const Text('Connection',
                          style: TextStyle(fontSize: 12)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () =>
                          setState(() => _showDebug = !_showDebug),
                      icon: Icon(
                          _showDebug
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 18),
                      label: const Text('Debug',
                          style: TextStyle(fontSize: 12)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => SettingsOverlay.showSettingsOverlay(context, context.read<SocketService>()),
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('Settings',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

}
