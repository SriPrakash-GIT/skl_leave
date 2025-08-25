import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'login.dart';
import 'custom/appBar.dart';
import 'custom/sideBar.dart';
import 'globalVariable.dart';

class ReachedWorkPage extends StatefulWidget {
  @override
  _ReachedWorkPageState createState() => _ReachedWorkPageState();
}

class _ReachedWorkPageState extends State<ReachedWorkPage>
    with WidgetsBindingObserver {
  // --- UI / State ---
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  GoogleMapController? _mapController;

  final Color _primaryColor = Colors.orange.shade600;
  final Color _accentColor = Colors.purple.shade900;
  final Color _darkColor = const Color(0xFF2D3336);

  String screenType = "Update Location";
  bool _isTracking = false;
  bool _showMap = true; // show a live mini-map

  // --- Timer / Counters ---
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  int _frequencyCount = 0; // increments every 15 minutes

  // --- Location / Path ---
  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;
  Position? _startPosition;
  String? _addressStart = "";
  String? _addressStop = "";
  String? _startTimeHHmm;
  String? _endTimeHHmm;

  // Live path (actual route) & distance
  final List<LatLng> _path = [];
  double _totalDistanceMeters = 0.0;

  // Map drawables
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _positionStream?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // -------- Lifecycle awareness (optional toast placeholders) --------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isTracking) return;
    // You can show snackbars if needed:
    // if (state == AppLifecycleState.paused) _showSnack("Tracking continues in background");
    // if (state == AppLifecycleState.resumed) _showSnack("Back to foreground");
  }

  // -------- Helpers --------
  String _fmtHHmm(DateTime t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: _darkColor,
    ));
  }

  Future<void> _saveSession() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('isTracking', _isTracking);
    await p.setString('startTime', _startTimeHHmm ?? '');
    await p.setString('startAddress', _addressStart ?? '');
    await p.setInt('elapsedSeconds', _elapsed.inSeconds);
    await p.setInt('frequencyCount', _frequencyCount);
    await p.setDouble('totalDistance', _totalDistanceMeters);

    // Persist path compactly
    final pathJson =
        _path.map((e) => {'lat': e.latitude, 'lng': e.longitude}).toList();
    await p.setString('pathJson', jsonEncode(pathJson));

    if (_startPosition != null) {
      await p.setString('startPos',
          "${_startPosition!.latitude},${_startPosition!.longitude}");
    }
  }

  Future<void> _clearSession() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('isTracking');
    await p.remove('startTime');
    await p.remove('startAddress');
    await p.remove('elapsedSeconds');
    await p.remove('frequencyCount');
    await p.remove('totalDistance');
    await p.remove('pathJson');
    await p.remove('startPos');
  }

  Future<void> _restoreSession() async {
    final p = await SharedPreferences.getInstance();
    final resume = p.getBool('isTracking') ?? false;
    if (!resume) return;

    setState(() {
      _isTracking = true;
      _startTimeHHmm = p.getString('startTime');
      _addressStart = p.getString('startAddress');
      _elapsed = Duration(seconds: p.getInt('elapsedSeconds') ?? 0);
      _frequencyCount = p.getInt('frequencyCount') ?? 0;
      _totalDistanceMeters = p.getDouble('totalDistance') ?? 0.0;
    });

    // restore path
    final pathStr = p.getString('pathJson');
    if (pathStr != null && pathStr.isNotEmpty) {
      final list = (jsonDecode(pathStr) as List)
          .map((e) => LatLng(
              (e['lat'] as num).toDouble(), (e['lng'] as num).toDouble()))
          .toList();
      _path.clear();
      _path.addAll(list);
      _redrawMap();
    }

    // restore start position (optional)
    final sp = p.getString('startPos');
    if (sp != null && sp.contains(',')) {
      final parts = sp.split(',');
      _startPosition = Position(
        latitude: double.tryParse(parts[0]) ?? 0,
        longitude: double.tryParse(parts[1]) ?? 0,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    }

    _beginTimer();
    _beginLocationStream();
  }

  // -------- Start / Stop --------
  Future<void> _onStart() async {
    if (_isTracking) return;

    // 1) Service + permission
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _showSnack('Please enable location services');
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        _showSnack('Location permission required');
        return;
      }
    }
    if (perm == LocationPermission.deniedForever) {
      _showSnack('Location permissions are permanently denied');
      return;
    }

    // 2) Prime current position
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );
    _currentPosition = pos;
    _startPosition = pos;

    // 3) Resolve start address
    try {
      final placemarks =
          await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        if ((p.street ?? '').isNotEmpty) parts.add(p.street!);
        if ((p.subLocality ?? '').isNotEmpty) parts.add(p.subLocality!);
        if ((p.locality ?? '').isNotEmpty) parts.add(p.locality!);
        if ((p.administrativeArea ?? '').isNotEmpty)
          parts.add(p.administrativeArea!);
        if ((p.postalCode ?? '').isNotEmpty) parts.add(p.postalCode!);
        _addressStart = parts.join(', ');
      }
    } catch (_) {}

    // 4) Initialize state
    setState(() {
      _isTracking = true;
      _startTimeHHmm = _fmtHHmm(DateTime.now());
      _elapsed = Duration.zero;
      _frequencyCount = 0;
      _totalDistanceMeters = 0.0;
      _path
        ..clear()
        ..add(LatLng(pos.latitude, pos.longitude));
      _markers
        ..clear()
        ..add(Marker(
          markerId: const MarkerId('start'),
          position: LatLng(pos.latitude, pos.longitude),
          infoWindow: const InfoWindow(title: 'Start'),
        ));
    });

    _redrawMap();
    _beginTimer();
    _beginLocationStream();
    _saveSession();

    _showSnack('📍 Tracking started');
    // Optional: send "start" to server
    _sendNewLocation(
        globalIDcardNo,
        screenType,
        pos.toString(),
        _startTimeHHmm ?? "",
        "",
        _frequencyCount.toString(),
        _addressStart ?? "",
        "",
        true);
  }

  Future<void> _onStop() async {
    if (!_isTracking) return;

    _timer?.cancel();
    await _positionStream?.cancel();

    final stop = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );

    // Stop address
    try {
      final placemarks =
          await placemarkFromCoordinates(stop.latitude, stop.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        if ((p.street ?? '').isNotEmpty) parts.add(p.street!);
        if ((p.subLocality ?? '').isNotEmpty) parts.add(p.subLocality!);
        if ((p.locality ?? '').isNotEmpty) parts.add(p.locality!);
        if ((p.administrativeArea ?? '').isNotEmpty)
          parts.add(p.administrativeArea!);
        if ((p.postalCode ?? '').isNotEmpty) parts.add(p.postalCode!);
        _addressStop = parts.join(', ');
      }
    } catch (_) {}

    _endTimeHHmm = _fmtHHmm(DateTime.now());

    // Add final point to path
    if (_path.isEmpty ||
        (_path.last.latitude != stop.latitude ||
            _path.last.longitude != stop.longitude)) {
      _path.add(LatLng(stop.latitude, stop.longitude));
    }

    // Mark stop on map
    _markers.removeWhere((m) => m.markerId.value == 'stop');
    _markers.add(Marker(
      markerId: const MarkerId('stop'),
      position: LatLng(stop.latitude, stop.longitude),
      infoWindow: const InfoWindow(title: 'Stop'),
    ));
    _redrawMap();

    final km = (_totalDistanceMeters / 1000).toStringAsFixed(2);
    _showSnack("🏁 Distance: $km km • ⏱️ ${_elapsed.inMinutes} min");

    setState(() => _isTracking = false);
    await _sendNewLocation(
        globalIDcardNo,
        screenType,
        stop.toString(),
        "",
        _endTimeHHmm ?? "",
        _frequencyCount.toString(),
        "",
        _addressStop ?? "",
        false);

    await _clearSession();
  }

  // -------- Timer & Stream --------
  void _beginTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      setState(() {
        _elapsed += const Duration(seconds: 1);
        if (_elapsed.inSeconds % 900 == 0) _frequencyCount++; // every 15 mins
      });
      _saveSession();
    });
  }

  void _beginLocationStream() {
    // High frequency & high accuracy for realistic path
    late LocationSettings settings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1, // meters
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "SKL HR App - OnDuty tracking active",
          notificationTitle: "OnDuty Location",
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      );
    }

    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onNewPosition, onError: (e) {
      _showSnack("Location error: $e");
    });
  }

  // -------- Live Distance (point → point with filters) --------
  void _onNewPosition(Position pos) {
    if (!_isTracking) return;

    final newPt = LatLng(pos.latitude, pos.longitude);

    // --- First point ---
    if (_path.isEmpty) {
      _path.add(newPt);
      _currentPosition = pos;
      _redrawMap();
      _saveSession();
      print("📍 First point recorded: ${pos.latitude}, ${pos.longitude}");
      return;
    }

    // --- Previous point ---
    final last = _path.last;
    final meters = Geolocator.distanceBetween(
      last.latitude,
      last.longitude,
      newPt.latitude,
      newPt.longitude,
    );

    // --- Time difference (seconds) ---
    int dt = 1;
    if (pos.timestamp != null && _currentPosition?.timestamp != null) {
      dt = pos.timestamp!
          .difference(_currentPosition!.timestamp!)
          .inSeconds
          .abs();
      if (dt == 0) dt = 1;
    }

    // --- Speed (m/s) ---
    final speedMs = meters / dt;

    // --- Dynamic thresholds ---
    double accuracyLimit;
    double movedThreshold;

    if (speedMs < 2) {
      // Walking
      accuracyLimit = 20; // GPS drift can be ±15-20m
      movedThreshold = 3; // minimum 3 meters
    } else if (speedMs < 15) {
      // Bike
      accuracyLimit = 25;
      movedThreshold = 5;
    } else {
      // Car
      accuracyLimit = 50;
      movedThreshold = 10;
    }

    // --- Filters ---
    final isAccurate = pos.accuracy <= accuracyLimit;
    final movedEnough = meters >= movedThreshold;
    final reasonableSpeed = speedMs <= 35; // ~126 km/h
    final notJump = meters <= 200; // ignore big jumps

    // --- Accept / Reject ---
    if (isAccurate && movedEnough && reasonableSpeed && notJump) {
      _path.add(newPt);
      _totalDistanceMeters += meters;
      _currentPosition = pos;

      if (_path.length % 2 == 0) _redrawMap();
      _saveSession();

      print("✅ Accepted Move → "
          "Dist: ${meters.toStringAsFixed(1)} m, "
          "Speed: ${(speedMs * 3.6).toStringAsFixed(1)} km/h, "
          "Acc: ${pos.accuracy} m");
    } else {
      print("❌ Ignored Drift → "
          "Dist: ${meters.toStringAsFixed(1)} m, "
          "Speed: ${(speedMs * 3.6).toStringAsFixed(1)} km/h, "
          "Acc: ${pos.accuracy} m");
    }
  }

  void _redrawMap() {
    if (!_showMap || _path.isEmpty) return;

    _polylines
      ..clear()
      ..add(Polyline(
          polylineId: const PolylineId('route'),
          points: List<LatLng>.from(_path),
          width: 6,
          color: Colors.pink));

    // Camera follow
    final last = _path.last;
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(last),
    );

    setState(() {}); // refresh widgets
  }

  // -------- API --------
  Future<void> _sendNewLocation(
    String idCardNo,
    String type,
    String coordinate,
    String startTime,
    String endTime,
    String frequency,
    String sAddress,
    String eAddress,
    bool start,
  ) async {
    final url = "$ipAddress/api/sendNewLocation";
    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          "IDCARDNO": idCardNo,
          "TYPE": type,
          "COORDINATE": coordinate,
          "STIME": startTime,
          "ENDTIME": endTime,
          "STARTADDRESS": sAddress,
          "ENDLOCATION": eAddress,
          "FREQUENCY": frequency,
          "DISTANCE": _totalDistanceMeters
              .toStringAsFixed(2), // keep meters; or send km by converting
          "DURATION": _elapsed.inSeconds.toString(),
        }),
      );

      final Map<String, dynamic> data = json.decode(res.body);
      if ((data["status"] ?? false) == true) {
        _showSnack("${data["message"]}");
      } else {
        if (start) {
          setState(() {
            _isTracking = false;
            _path.clear();
            _totalDistanceMeters = 0.0;
          });
          await _clearSession();
        }
        _showDialog("Alert", "${data["message"] ?? "Please try again"}");
      }
    } catch (_) {
      _showDialog("Connection Error", "Please try again later");
    }
  }

  void _showDialog(String title, String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  // -------- UI --------
  Future<bool> _onBack() async {
    if (_isTracking) {
      _showSnack('Tracking is active. Please stop tracking first.');
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onBack,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.grey[100],
        appBar: CustomAppBar(onMenuPressed: () {}, barTitle: "Update Location"),
        drawer: const CustomDrawer(
            stkTransferCheck: false, brhTransferCheck: false),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                children: [
                  if (_showMap) _buildMapCard(),
                  const SizedBox(height: 16),
                  _buildActionCard(
                    icon: Icons.location_on,
                    title: "Start Location",
                    subtitle: _isTracking
                        ? "Tracking already running"
                        : "Tap to Start your OnDuty",
                    address: _addressStart,
                    color: _primaryColor,
                    onTap: _onStart,
                    enabled: !_isTracking,
                  ),
                  const SizedBox(height: 16),
                  _buildActionCard(
                    icon: Icons.flag,
                    title: "Reached Location",
                    subtitle: "Tap to Stop and submit this session",
                    address: _addressStop,
                    color: _accentColor,
                    onTap: _onStop,
                    enabled: true,
                  ),
                  if (_isTracking) ...[
                    const SizedBox(height: 12),
                    _buildStats(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapCard() {
    final start =
        _path.isNotEmpty ? _path.first : const LatLng(11.1075, 77.3398);
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        height: 260,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: start, zoom: 15),
            onMapCreated: (c) => _mapController = c,
            polylines: _polylines,
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            compassEnabled: true,
            zoomControlsEnabled: true,
            tiltGesturesEnabled: false,
          ),
        ),
      ),
    );
  }

  Widget _buildStats() {
    final km = (_totalDistanceMeters / 1000).toStringAsFixed(2);
    final mins = _elapsed.inMinutes;
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.timer),
            const SizedBox(width: 8),
            Text("Time: $mins min"),
            const Spacer(),
            const Icon(Icons.social_distance),
            const SizedBox(width: 8),
            Text("Distance: $km km"),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    String? address,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Card(
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                    backgroundColor: color.withOpacity(0.15),
                    child: Icon(icon, color: color)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(subtitle,
                  style: const TextStyle(fontSize: 14, color: Colors.black54)),
              if ((address ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.place, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                      child:
                          Text(address!, style: const TextStyle(fontSize: 14))),
                ]),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: enabled ? onTap : null,
                  icon: const Icon(Icons.touch_app, color: Colors.white),
                  label: const Text("Tap to Continue",
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
