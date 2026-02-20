import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart'; // Add this import
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'auto_location_monitor.dart';

class DistanceDisplayWidget extends StatefulWidget {
  const DistanceDisplayWidget({Key? key}) : super(key: key);

  @override
  _DistanceDisplayWidgetState createState() => _DistanceDisplayWidgetState();
}

class _DistanceDisplayWidgetState extends State<DistanceDisplayWidget> {
  double? currentDistance;
  bool isLoading = true;
  FixedLocation? fixedLocation;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDistance();

    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadDistance();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel(); // Clean up timer
    super.dispose();
  }

  Future<void> _loadDistance() async {
    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      // Check if monitoring is active
      final isActive = await AutoLocationMonitor.isMonitoringActive();
      if (!isActive) {
        setState(() {
          currentDistance = null;
          isLoading = false;
        });
        return;
      }

      // Get fixed location
      fixedLocation = await AutoLocationMonitor.getFixedLocation();
      if (fixedLocation == null) {
        setState(() => isLoading = false);
        return;
      }

      // Check and request location permissions if needed
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions are denied');
          setState(() => isLoading = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Location permissions are permanently denied');
        setState(() => isLoading = false);
        return;
      }

      // Get current position
      final currentPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );

      // Calculate distance
      final distance = Geolocator.distanceBetween(
        fixedLocation!.latitude,
        fixedLocation!.longitude,
        currentPos.latitude,
        currentPos.longitude,
      );

      if (mounted) {
        setState(() {
          currentDistance = distance;
          isLoading = false;
        });
      }

    } catch (e) {
      print('Error loading distance: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  String _formatDistance(double? distance) {
    if (distance == null) return 'Unknown';

    if (distance >= 1000) {
      return '${(distance/1000).toStringAsFixed(2)} km';
    } else {
      return '${distance.toStringAsFixed(1)} m';
    }
  }

  Color _getDistanceColor(double? distance) {
    if (distance == null) return Colors.grey;
    if (distance <= 50) return Colors.green;
    if (distance <= 100) return Colors.orange;
    return Colors.red;
  }

  String _getDistanceStatus(double? distance) {
    if (distance == null) return 'Unknown';
    if (distance <= 50) return 'Safe Zone';
    if (distance <= 100) return 'Approaching Limit';
    return 'Outside Radius';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getDistanceColor(currentDistance).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: _getDistanceColor(currentDistance),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Distance from Fixed Location',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getDistanceStatus(currentDistance),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _getDistanceColor(currentDistance),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (currentDistance != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Current Distance:',
                        style: TextStyle(fontSize: 16),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getDistanceColor(currentDistance).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _formatDistance(currentDistance),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _getDistanceColor(currentDistance),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Progress bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Exit Radius Progress',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          Text(
                            '${((currentDistance! / 100) * 100).toStringAsFixed(0)}%',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (currentDistance! / 100).clamp(0.0, 1.0),
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getDistanceColor(currentDistance),
                          ),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('0m', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                          Text('50m', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                          Text('100m', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Fixed location info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_city, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              'Fixed Location',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          fixedLocation?.address ?? 'Unknown',
                          style: const TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  if (currentDistance! > 100)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Exit Alert',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  'You are ${(currentDistance! - 100).toStringAsFixed(1)}m beyond the 100m radius',
                                  style: const TextStyle(color: Colors.red, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              )
            else
              Center(
                child: Column(
                  children: [
                    Icon(Icons.location_off, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      'Monitoring not active',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // Refresh button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _loadDistance,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}