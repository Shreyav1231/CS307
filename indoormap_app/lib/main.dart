import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'data/map_data_provider.dart';
import 'services/user_location_service.dart';
import 'services/wifi_location_service.dart';
import 'widgets/search_widget.dart';
import 'widgets/calibration_widget.dart';
import 'models/calibration_point.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hillenbrand Map',
      theme: ThemeData(
        primarySwatch: Colors.amber,
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Scaling factor to map pixels to valid LatLng range
  // We use 100 so 1508 pixels becomes 15.08 units (must be < 90)
  final double scale = 500.0;
  final double imageWidth = 1780;
  final double imageHeight = 1508;
  late final LatLngBounds _bounds;
  Future<MapData>? _mapDataFuture;

  final UserLocationService _locationService = UserLocationService();
  final WifiLocationService _wifiService = WifiLocationService();
  Stream<Position>? _locationStream;
  
  // Calibration State
  bool _isCalibrating = false;
  List<CalibrationPoint> _calibrationPoints = [];

  MapData? _currentData;

  @override
  void initState() {
    super.initState();
    _bounds = LatLngBounds(
      const LatLng(0, 0),
      LatLng(imageHeight / scale, imageWidth / scale),
    );
    _loadData();
    _startWifiScanning();
  }

  Future<void> _loadData() async {
    final data = await MapDataProvider.load();
    setState(() {
      _currentData = data;
      _mapDataFuture = Future.value(data);
      // Load saved calibration
      _calibrationPoints = data.userCalibration.map((a) => CalibrationPoint(
        pixelLocation: LatLng(a.pixel[0], a.pixel[1]),
        gpsLocation: LatLng(a.gps[0], a.gps[1]),
        wifiFingerprint: a.wifiFingerprint ?? {},
      )).toList();
    });
  }

  Future<void> _savePoints() async {
    if (_currentData == null) return;
    final updatedData = MapData(
      nodes: _currentData!.nodes,
      anchors: _currentData!.anchors,
      userCalibration: _calibrationPoints.map((p) => MapAnchor(
        id: "user_${DateTime.now().millisecondsSinceEpoch}",
        gps: [p.gpsLocation.latitude, p.gpsLocation.longitude],
        pixel: [p.pixelLocation.latitude, p.pixelLocation.longitude],
        wifiFingerprint: p.wifiFingerprint,
      )).toList(),
    );
    await MapDataProvider.save(updatedData);
    _currentData = updatedData;
  }

  void _enableTracking() {
    if (_locationStream == null) {
      setState(() {
        _locationStream = _locationService.getRawPositionStream();
      });
    }
  }

  Future<void> _handleMapTap(TapPosition tapPos, LatLng point) async {
    if (_isCalibrating) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Capturing GPS and Wi-Fi... Please hold still."),
        duration: Duration(seconds: 2),
      ));

      try {
        final Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
        );
        final LatLng gpsLatLng = LatLng(pos.latitude, pos.longitude);
        
        Map<String, int> wifiData = {};
        int retries = 3;
        while (retries > 0) {
          try {
            wifiData = await _wifiService.getFingerprint(); 
            if (wifiData.isNotEmpty) break;
          } catch (e) {
            debugPrint("Wi-Fi Scan attempt failed: $e");
          }
          await Future.delayed(const Duration(milliseconds: 500));
          retries--;
        }
        
        setState(() {
          _calibrationPoints.add(CalibrationPoint(
            pixelLocation: point, 
            gpsLocation: gpsLatLng,
            wifiFingerprint: wifiData,
          ));
        });
        
        await _savePoints(); // Persist

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Point ${_calibrationPoints.length} saved. Data persistent!"),
          backgroundColor: wifiData.isEmpty ? Colors.orange : Colors.green,
        ));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Error capturing location: $e"),
          backgroundColor: Colors.red,
        ));
      }
    }
  }
 
  // Helper to transform raw GPS to Map Pixels using our calibration points
  LatLng _transformGpsToMap(LatLng currentGps, List<MapAnchor> defaultAnchors) {
    // 1. If we have enough points, use Weighted KNN (Inverse Distance Weighting)
    if (_calibrationPoints.length >= 2) {
      // Find distances to all calibration points
      List<MapEntry<double, CalibrationPoint>> sortedPoints = _calibrationPoints.map((p) {
        double dist = const Distance().as(LengthUnit.Meter, currentGps, p.gpsLocation);
        return MapEntry(dist, p);
      }).toList();

      // Sort by distance (closest first)
      sortedPoints.sort((a, b) => a.key.compareTo(b.key));

      // Use the closest K points (e.g., K=3)
      int k = 3;
      if (sortedPoints.length < k) k = sortedPoints.length;
      
      final nearest = sortedPoints.take(k).toList();

      double totalWeight = 0;
      double weightedPixelLat = 0;
      double weightedPixelLng = 0;

      for (var entry in nearest) {
        double dist = entry.key;
        // Avoid division by zero if we are exactly on a point
        if (dist < 0.5) return entry.value.pixelLocation; 
        
        // Weight = 1 / distance^2 (Standard IDW)
        double weight = 1 / (dist * dist);
        
        totalWeight += weight;
        weightedPixelLat += entry.value.pixelLocation.latitude * weight;
        weightedPixelLng += entry.value.pixelLocation.longitude * weight;
      }

      return LatLng(weightedPixelLat / totalWeight, weightedPixelLng / totalWeight);
    } 
    
    // 2. Fallback to 1-point translation
    else if (_calibrationPoints.length == 1) {
       return _calibrationPoints[0].pixelLocation;
    }

    // 3. Default: Use JSON anchors
    if (defaultAnchors.length >= 2) {
      final a1 = defaultAnchors[0];
      final a2 = defaultAnchors[1];
      double dLat = a2.gps[0] - a1.gps[0];
      double dLng = a2.gps[1] - a1.gps[1];
      
      if (dLat.abs() < 0.00001 || dLng.abs() < 0.00001) return const LatLng(0,0);

      double latRatio = (currentGps.latitude - a1.gps[0]) / dLat;
      double lngRatio = (currentGps.longitude - a1.gps[1]) / dLng;

      return LatLng(
        (a1.pixel[0] + latRatio * (a2.pixel[0] - a1.pixel[0])) / scale,
        (a1.pixel[1] + lngRatio * (a2.pixel[1] - a1.pixel[1])) / scale
      );
    }

    return const LatLng(0,0);
  }

  final MapController _mapController = MapController();

  void _onNodeSelected(MapNode node) {
    _mapController.move(
      LatLng(node.pixel[0] / scale, node.pixel[1] / scale), 
      2.0 
    );
  }

  Map<String, int> _currentWifiScan = {};
  
  void _startWifiScanning() {
    // Basic periodic scan
    Timer.periodic(const Duration(seconds: 5), (timer) async {
       if (!mounted) return;
       try {
         final scan = await _wifiService.getFingerprint(); // Scan all
         setState(() {
           _currentWifiScan = scan;
         });
       } catch (e) {
         debugPrint("Periodic Wifi Scan failed: $e");
       }
    });
  }

  // Find nearest flag based on Wi-Fi fingerprint
  LatLng? _checkWifiSnapping() {
    if (_currentWifiScan.isEmpty || _calibrationPoints.isEmpty) return null;

    CalibrationPoint? bestMatch;
    double minDiff = 30.0; // Threshold: Average RSSI difference must be less than 30

    for (var p in _calibrationPoints) {
      if (p.wifiFingerprint.isEmpty) continue;
      
      double diff = _wifiService.calculateDifference(_currentWifiScan, p.wifiFingerprint);
      if (diff < minDiff) {
        minDiff = diff;
        bestMatch = p;
      }
    }

    return bestMatch?.pixelLocation;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<MapData>(
        future: _mapDataFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final nodes = snapshot.data?.nodes ?? [];
          final anchors = snapshot.data?.anchors ?? [];

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(
                    (imageHeight / 2) / scale,
                    (imageWidth / 2) / scale,
                  ),
                  initialZoom: 1.0, 
                  minZoom: 0.1,
                  maxZoom: 10.0,
                  crs: const CrsSimple(),
                  onTap: _handleMapTap, // Capture taps
                ),
                children: [
                  OverlayImageLayer(
                    overlayImages: [
                      OverlayImage(
                        bounds: _bounds,
                        opacity: 1.0,
                        imageProvider:
                            const AssetImage('assets/hilly6-floorplan.png'),
                      ),
                    ],
                  ),
                  // Nodes
                  MarkerLayer(
                    markers: nodes.map((node) {
                      return Marker(
                        point: LatLng(node.pixel[0] / scale, node.pixel[1] / scale),
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on,
                            color: Colors.red, size: 30),
                      );
                    }).toList(),
                  ),
                  // Calibration Points (show as Green Flags)
                   MarkerLayer(
                    markers: _calibrationPoints.map((p) {
                      return Marker(
                        point: p.pixelLocation,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.flag, color: Colors.green, size: 40),
                      );
                    }).toList(),
                  ),
                  
                  // User Location Marker
                  if (_locationStream != null)
                    StreamBuilder<Position>(
                      stream: _locationStream,
                      builder: (context, locSnapshot) {
                        // Priority 1: Wi-Fi Snapping (More accurate indoors)
                        LatLng? wifiSnap = _checkWifiSnapping();
                        
                        LatLng? mapPoint;
                        if (wifiSnap != null) {
                          mapPoint = wifiSnap;
                        } else if (locSnapshot.hasData) {
                          // Priority 2: GPS Transformation
                          final currentGps = LatLng(locSnapshot.data!.latitude, locSnapshot.data!.longitude);
                          mapPoint = _transformGpsToMap(currentGps, anchors);
                        }

                        if (mapPoint != null) {
                          return MarkerLayer(
                            markers: [
                              Marker(
                                point: mapPoint,
                                width: 20,
                                height: 20,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: wifiSnap != null ? Colors.green : Colors.blue,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        blurRadius: 5, 
                                        color: wifiSnap != null ? Colors.greenAccent : Colors.blueAccent
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                ],
              ),
              
              // Search Bar (Hide when calibrating to reduce clutter?)
              if (!_isCalibrating)
                Positioned(
                  top: 40,
                  left: 0,
                  right: 0,
                  child: SearchWidget(
                    nodes: nodes,
                    onNodeSelected: _onNodeSelected,
                  ),
                ),

              // Calibration UI
              CalibrationWidget(
                isCalibrating: _isCalibrating,
                points: _calibrationPoints,
                onToggle: (val) => setState(() => _isCalibrating = val),
                onReset: () async {
                  setState(() => _calibrationPoints.clear());
                  await _savePoints();
                },
                onExport: () {
                   // Generate the JSON string from current calibration points
                   final exportData = _calibrationPoints.map((p) => {
                     'pixel': [p.pixelLocation.latitude, p.pixelLocation.longitude],
                     'gps': [p.gpsLocation.latitude, p.gpsLocation.longitude],
                     'wifi': p.wifiFingerprint,
                   }).toList();
                   final jsonStr = jsonEncode(exportData);
                   Clipboard.setData(ClipboardData(text: jsonStr));
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                     content: Text("Calibration data copied to clipboard!"),
                   ));
                },
              ),

              Positioned(
                bottom: 20,
                right: 20,
                child: FloatingActionButton(
                  onPressed: () {
                    if (_locationStream == null) {
                      _enableTracking();
                    } else {
                      // Logic to jump map center to user location
                      // Note: We need to get the last known position to center on it
                      // For now, _startListeningAndFocus handles the stream start.
                      // We'll add a snackbar to confirm it's tracking.
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Tracking location... Map will follow."),
                        duration: Duration(seconds: 1),
                      ));
                    }
                  },
                  child: const Icon(Icons.my_location),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
