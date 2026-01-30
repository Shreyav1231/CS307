import 'package:wifi_scan/wifi_scan.dart';

class WifiLocationService {
  /// Returns a map of BSSID -> RSSI for all visible networks
  /// Filtered by SSID if provided (e.g. "PAL3.0")
  Future<Map<String, int>> getFingerprint({String? targetSsid}) async {
    // 1. Check support
    final canScan = await WiFiScan.instance.canStartScan();
    if (canScan != CanStartScan.yes) {
      print("[WifiLocationService] Cannot start scan. Reason: $canScan");
      return {}; // Cannot scan (permissions, hardware, etc)
    }

    // 2. Start Scan
    final result = await WiFiScan.instance.startScan();
    if (!result) {
       print("[WifiLocationService] StartScan failed.");
       return {};
    }

    // 3. Get Results
    final accessPoints = await WiFiScan.instance.getScannedResults();
    
    // 4. Transform to Map
    Map<String, int> fingerprint = {};
    for (var ap in accessPoints) {
      if (targetSsid == null || ap.ssid == targetSsid) {
        fingerprint[ap.bssid] = ap.level;
      }
    }
    return fingerprint;
  }

  /// Calculates similarity between two fingerprints
  /// Returns a score (lower is better/closer)
  double calculateDifference(Map<String, int> f1, Map<String, int> f2) {
    double totalDiff = 0;
    int matches = 0;

    for (var bssid in f1.keys) {
      if (f2.containsKey(bssid)) {
        totalDiff += (f1[bssid]! - f2[bssid]!).abs();
        matches++;
      } else {
        // Penalty for missing AP
        totalDiff += 100; 
      }
    }

    if (matches == 0) return 9999.0; // No common APs
    return totalDiff / matches;
  }
}
