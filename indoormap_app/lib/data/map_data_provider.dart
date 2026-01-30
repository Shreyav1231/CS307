import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapData {
  final List<MapNode> nodes;
  final List<MapAnchor> anchors;
  final List<MapAnchor> userCalibration; // New persistent field

  MapData({required this.nodes, required this.anchors, this.userCalibration = const []});

  factory MapData.fromJson(Map<String, dynamic> json) {
    return MapData(
      nodes: (json['nodes'] as List?)?.map((e) => MapNode.fromJson(e)).toList() ?? [],
      anchors: (json['anchors'] as List?)?.map((e) => MapAnchor.fromJson(e)).toList() ?? [],
      userCalibration: (json['userCalibration'] as List?)?.map((e) => MapAnchor.fromJson(e)).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nodes': nodes.map((e) => e.toJson()).toList(),
      'anchors': anchors.map((e) => e.toJson()).toList(),
      'userCalibration': userCalibration.map((e) => e.toJson()).toList(),
    };
  }
}

class MapNode {
  final String id;
  final String name;
  final List<double> pixel; 
  final String type;
  /// BSSID -> RSSI map for fingerprinting
  final Map<String, int>? wifiFingerprint; 

  MapNode({
    required this.id, 
    required this.name, 
    required this.pixel, 
    required this.type,
    this.wifiFingerprint,
  });

  factory MapNode.fromJson(Map<String, dynamic> json) {
    return MapNode(
      id: json['id'],
      name: json['name'],
      pixel: (json['pixel'] as List).map((e) => (e as num).toDouble()).toList(),
      type: json['type'],
      wifiFingerprint: (json['wifiFingerprint'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value as int),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'pixel': pixel,
      'type': type,
      'wifiFingerprint': wifiFingerprint,
    };
  }
}

class MapAnchor {
  final String id;
  final List<double> gps;
  final List<double> pixel;
  final Map<String, int>? wifiFingerprint;

  MapAnchor({
    required this.id, 
    required this.gps, 
    required this.pixel, 
    this.wifiFingerprint
  });

  factory MapAnchor.fromJson(Map<String, dynamic> json) {
    return MapAnchor(
      id: json['id'],
      gps: (json['gps'] as List).map((e) => (e as num).toDouble()).toList(),
      pixel: (json['pixel'] as List).map((e) => (e as num).toDouble()).toList(),
      wifiFingerprint: (json['wifiFingerprint'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value as int),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gps': gps,
      'pixel': pixel,
      'wifiFingerprint': wifiFingerprint,
    };
  }
}

class MapDataProvider {
  static const String _storageKey = 'map_data_v1';

  /// Loads data: 
  /// 1. Tries local storage (user edits).
  /// 2. Falls back to assets (base data).
  static Future<MapData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final String? localType = prefs.getString(_storageKey);

    if (localType != null) {
      try {
        final data = json.decode(localType);
        return MapData.fromJson(data);
      } catch (e) {
        print("Error loading local data: $e");
      }
    }

    // Fallback to asset
    final String response = await rootBundle.loadString('assets/map_data.json');
    final data = await json.decode(response);
    return MapData.fromJson(data);
  }

  /// Saves current data state to local storage
  static Future<void> save(MapData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, json.encode(data.toJson()));
  }
  
  /// Clears local storage (reset to factory)
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
