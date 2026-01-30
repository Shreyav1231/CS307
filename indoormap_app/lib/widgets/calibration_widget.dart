import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/calibration_point.dart';

class CalibrationWidget extends StatefulWidget {
  final bool isCalibrating;
  final Function(bool) onToggle;
  final Function() onReset;
  final Function() onExport;
  final List<CalibrationPoint> points;

  const CalibrationWidget({
    Key? key,
    required this.isCalibrating,
    required this.onToggle,
    required this.onReset,
    required this.onExport,
    required this.points,
  }) : super(key: key);

  @override
  State<CalibrationWidget> createState() => _CalibrationWidgetState();
}

class _CalibrationWidgetState extends State<CalibrationWidget> {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 100, // Below Search Bar
      right: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Mode Toggle
          FloatingActionButton.extended(
            heroTag: "calibration_toggle",
            onPressed: () => widget.onToggle(!widget.isCalibrating),
            label: Text(widget.isCalibrating ? "Stop Calibration" : "Calibrate Map"),
            icon: Icon(widget.isCalibrating ? Icons.stop : Icons.build),
            backgroundColor: widget.isCalibrating ? Colors.orange : Colors.white,
          ),
          const SizedBox(height: 10),
          
          // Instructions / Status
          if (widget.isCalibrating)
            Container(
              padding: const EdgeInsets.all(12),
              width: 200,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Calibration Mode",
                    style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Points Collected: ${widget.points.length}",
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Instructions:",
                    style: TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                  const Text(
                    "1. Stand at a known location.\n"
                    "2. Tap the map where you are.\n"
                    "3. Repeat for a 2nd point.",
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (widget.points.isNotEmpty)
                    Column(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            minimumSize: const Size.fromHeight(40),
                          ),
                          onPressed: widget.onExport,
                          icon: const Icon(Icons.copy, color: Colors.white),
                          label: const Text("Export Data", style: TextStyle(color: Colors.white)),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            minimumSize: const Size.fromHeight(36),
                          ),
                          onPressed: widget.onReset,
                          child: const Text("Reset Points", style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    )
                ],
              ),
            ),
        ],
      ),
    );
  }
}
