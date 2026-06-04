import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConnectionProfile {
  final String id;
  final String name;
  final String host;
  final int port;

  const ConnectionProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
  });

  ConnectionProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
  }) {
    return ConnectionProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
  };

  static ConnectionProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final host = value['host'];
    final port = value['port'];
    if (id is! String || name is! String || host is! String || port is! int) {
      return null;
    }
    return ConnectionProfile(id: id, name: name, host: host, port: port);
  }
}

class ConnectionProfileProvider extends ChangeNotifier {
  static const _profilesKey = 'connection_profiles';
  static const _lastProfileIdKey = 'connection_last_profile_id';

  final List<ConnectionProfile> _profiles = [];
  String? _selectedProfileId;
  bool _loaded = false;

  List<ConnectionProfile> get profiles => List.unmodifiable(_profiles);
  String? get selectedProfileId => _selectedProfileId;
  bool get loaded => _loaded;

  ConnectionProfile? get selectedProfile {
    final id = _selectedProfileId;
    if (id == null) return null;
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _profiles.clear();

    final rawProfiles = prefs.getStringList(_profilesKey) ?? [];
    for (final raw in rawProfiles) {
      try {
        final profile = ConnectionProfile.fromJson(jsonDecode(raw));
        if (profile != null) _profiles.add(profile);
      } catch (_) {
        // Ignore malformed saved profiles.
      }
    }

    _profiles.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    final lastProfileId = prefs.getString(_lastProfileIdKey);
    if (_profiles.any((profile) => profile.id == lastProfileId)) {
      _selectedProfileId = lastProfileId;
    } else {
      _selectedProfileId = _profiles.isNotEmpty ? _profiles.first.id : null;
    }

    _loaded = true;
    notifyListeners();
  }

  Future<ConnectionProfile> saveProfile({
    String? id,
    required String name,
    required String host,
    required int port,
  }) async {
    final cleanName = name.trim();
    final cleanHost = host.trim();
    final profile = ConnectionProfile(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: cleanName.isEmpty ? cleanHost : cleanName,
      host: cleanHost,
      port: port,
    );

    final existingIndex = _profiles.indexWhere(
      (existing) => existing.id == profile.id,
    );
    if (existingIndex >= 0) {
      _profiles[existingIndex] = profile;
    } else {
      _profiles.add(profile);
    }
    _profiles.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    _selectedProfileId = profile.id;

    await _persist();
    notifyListeners();
    return profile;
  }

  Future<void> selectProfile(String? id) async {
    _selectedProfileId = id;
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_lastProfileIdKey);
    } else {
      await prefs.setString(_lastProfileIdKey, id);
    }
    notifyListeners();
  }

  Future<void> deleteSelectedProfile() async {
    final id = _selectedProfileId;
    if (id == null) return;
    _profiles.removeWhere((profile) => profile.id == id);
    _selectedProfileId = _profiles.isNotEmpty ? _profiles.first.id : null;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _profilesKey,
      _profiles.map((profile) => jsonEncode(profile.toJson())).toList(),
    );
    final id = _selectedProfileId;
    if (id == null) {
      await prefs.remove(_lastProfileIdKey);
    } else {
      await prefs.setString(_lastProfileIdKey, id);
    }
  }
}
