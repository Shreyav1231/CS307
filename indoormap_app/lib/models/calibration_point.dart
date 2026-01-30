import 'package:latlong2/latlong.dart';

class CalibrationPoint {
  final LatLng pixelLocation; // Where user tapped on map (scaled)
  final LatLng gpsLocation;   // Real GPS from device
  final Map<String, int> wifiFingerprint; // Captured RSSI data

  CalibrationPoint({
    required this.pixelLocation,
    required this.gpsLocation,
    required this.wifiFingerprint,
  });

  @override
  String toString() => 'Pixel: $pixelLocation, GPS: $gpsLocation, Wi-Fi APs: ${wifiFingerprint.length}';
}
