import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// Replace with your actual imports
import 'login.dart';
import 'custom/appBar.dart';
import 'custom/sideBar.dart';
import 'globalVariable.dart';
import 'mini_map_overlay.dart';
import 'background_service.dart';

class ReachedWorkPage extends StatefulWidget {
  @override
  _ReachedWorkPageState createState() => _ReachedWorkPageState();
}

// PiP channel
class PipManager {
  static const MethodChannel _channel = MethodChannel('com.sklhr/pip');

  static Future<void> enterPipMode() async {
    try {
      await _channel.invokeMethod('enterPiP');
    } on PlatformException catch (e) {
      print("Failed to enter PiP mode: ${e.message}");
    }
  }
}

class _ReachedWorkPageState extends State<ReachedWorkPage>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  GoogleMapController? _mapController;

  final Color _primaryColor = Colors.orange.shade600;
  final Color _accentColor = Colors.purple.shade900;
  final Color _darkColor = const Color(0xFF2D3336);

  bool _isTracking = false;
  bool _hasError = false;
  bool _showMap = true;
  bool _isInPipMode = false;
  bool _startButtonProcessing = false;
  bool _stopButtonProcessing = false;
  bool _startButtonClicked = false; // NEW: Track if start button was clicked
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  int _frequencyCount = 0;

  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;
  Position? _startPosition;
  String? _addressStart = "";
  String? _addressStop = "";
  String? _startTimeHHmm;
  String? _endTimeHHmm;

  final List<LatLng> _path = [];
  double _totalDistanceMeters = 0.0;

  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isTracking) {
      if (state == AppLifecycleState.paused) {
        _enterPipMode();
      } else if (state == AppLifecycleState.resumed) {
        _exitPipMode();
      }
    }
  }

  Future<void> _enterPipMode() async {
    if (!_isInPipMode) {
      await PipManager.enterPipMode();
      setState(() {
        _isInPipMode = true;
      });
    }
  }

  void _exitPipMode() {
    if (_isInPipMode) {
      setState(() {
        _isInPipMode = false;
      });
    }
  }

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

  // --- Session Persistence ---
  Future<void> _saveSession() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('isTracking', _isTracking);
    await p.setBool(
        'startButtonClicked', _startButtonClicked); // NEW: Save button state
    await p.setString('startTime', _startTimeHHmm ?? '');
    await p.setString('startAddress', _addressStart ?? '');
    await p.setInt('elapsedSeconds', _elapsed.inSeconds);
    await p.setInt('frequencyCount', _frequencyCount);
    await p.setDouble('totalDistance', _totalDistanceMeters);

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
    await p.setBool('isTracking', false);
    await p.setBool('startButtonClicked', false);
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
    print(resume);
    setState(() {
      _isTracking = resume;
      _startButtonClicked = p.getBool('startButtonClicked') ?? resume;
      print(p.getBool('startButtonClicked')); // NEW: Restore button state
      _startTimeHHmm = p.getString('startTime');
      _addressStart = p.getString('startAddress');
      _elapsed = Duration(seconds: p.getInt('elapsedSeconds') ?? 0);
      _frequencyCount = p.getInt('frequencyCount') ?? 0;
      _totalDistanceMeters = p.getDouble('totalDistance') ?? 0.0;
    });

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

    if (resume) {
      _beginTimer();
      _beginLocationStream();
    }
  }

  void _showErrorDialog(String title, String content) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showSuccessDialog(String title, String content) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // --- Start/Stop Tracking ---
  Future<void> _onStart() async {
    print("----------_onStart---------------------------------");
    // NEW: Prevent multiple clicks
    if (_startButtonProcessing || _startButtonClicked) return;

    setState(() {
      _startButtonProcessing = true;
      _startButtonClicked = true; // NEW: Mark button as clicked
    });

    _timer?.cancel();
    await _positionStream?.cancel();
    // await _clearSession();

    setState(() {
      _isTracking = false;
      _elapsed = Duration.zero;
      _frequencyCount = 0;
      _totalDistanceMeters = 0.0;
      _path.clear();
      _markers.clear();
      _polylines.clear();
      _addressStart = "";
      _addressStop = "";
      _startTimeHHmm = null;
      _endTimeHHmm = null;
      _currentPosition = null;
      _startPosition = null;
    });
    // Permission check
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _showErrorDialog("Error", "Please enable location services");
      setState(() => _startButtonProcessing = false);
      return;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied)
      perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      _showErrorDialog("Error", "Location permission required");
      setState(() => _startButtonProcessing = false);
      return;
    }

    // Get current position
    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation);

    // Get address
    String? startAddress;
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
        startAddress = parts.join(', ');
      }
    } catch (_) {}

    // --- API call first ---
    bool apiSuccess = false;
    try {
      final url = "$ipAddress/api/sendNewLocation";
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          "IDCARDNO": globalIDcardNo,
          "TYPE": "Start Location",
          "COORDINATE": pos.toString(),
          "STIME": _fmtHHmm(DateTime.now()),
          "ENDTIME": "",
          "STARTADDRESS": startAddress ?? "",
          "ENDLOCATION": "",
          "FREQUENCY": "0",
          "DISTANCE": "0",
          "DURATION": "0",
        }),
      );

      final data = json.decode(res.body);
      if ((data["status"] ?? false) == true) {
        apiSuccess = true;

        _showSnack("${data["message"]}");
      } else {
        _showErrorDialog("Error", "${data["message"] ?? "Please try again"}");
      }
    } catch (_) {
      _showSnack("Connection Error");
    }

    if (!apiSuccess) {
      setState(() {
        _startButtonProcessing = false;
        _startButtonClicked = false; // NEW: Reset if API fails
      });
      return; // ❌ Do not update UI or start tracking
    }

    // --- Only after API success ---
    _currentPosition = pos;
    _startPosition = pos;

    await _clearSession();

    setState(() {
      _isTracking = true;
      _startTimeHHmm = _fmtHHmm(DateTime.now());
      _addressStart = startAddress; // show only if API success
      _path.add(LatLng(pos.latitude, pos.longitude));
      _markers.add(Marker(
        markerId: const MarkerId('start'),
        position: LatLng(pos.latitude, pos.longitude),
        infoWindow: const InfoWindow(title: 'Start'),
      ));
    });

    _redrawMap();
    _beginTimer();
    _beginLocationStream();
    await _saveSession();
    startBackgroundLocation();

    setState(() => _startButtonProcessing = false);
  }

  Future<void> _onStop() async {
    if (!_isTracking) return;
    setState(() => _stopButtonProcessing = true);
    _timer?.cancel();
    await _positionStream?.cancel();

    // Get current position for stop
    final stop = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );

    // Get stop address
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

    // Add Stop marker
    _markers.removeWhere((m) => m.markerId.value == 'stop');
    _markers.add(Marker(
      markerId: const MarkerId('stop'),
      position: LatLng(stop.latitude, stop.longitude),
      infoWindow: const InfoWindow(title: 'Stop'),
    ));
    _redrawMap();

    bool apiSuccess = false;
    try {
      final url = "$ipAddress/api/sendNewLocation";
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          "IDCARDNO": globalIDcardNo,
          "TYPE": "Update Location",
          "COORDINATE": stop.toString(),
          "STIME": "",
          "ENDTIME": _endTimeHHmm ?? "",
          "STARTADDRESS": "",
          "ENDLOCATION": _addressStop ?? "",
          "FREQUENCY": _frequencyCount.toString(),
          "DISTANCE": _totalDistanceMeters.toStringAsFixed(2),
          "DURATION": _elapsed.inSeconds.toString(),
        }),
      );

      final Map<String, dynamic> data = json.decode(res.body);
      if (data["status"] == true) {
        apiSuccess = true;
        _showSuccessDialog("Success", "${data["message"]}");
      } else {
        _showErrorDialog("Error", "${data["message"] ?? "Please try again"}");
      }
    } catch (_) {
      _showSnack("Connection Error");
    }

    if (apiSuccess) {
      await _clearSession();

      // Reset all in-memory data
      setState(() {
        _isTracking = false;
        _startButtonClicked = false;
        _elapsed = Duration.zero;
        _frequencyCount = 0;
        _totalDistanceMeters = 0.0;
        _path.clear();
        _markers.clear();
        _polylines.clear();
        _addressStart = "";
        _addressStop = "";
        _startTimeHHmm = null;
        _endTimeHHmm = null;
        _currentPosition = null;
        _startPosition = null;
      });

      // Exit PiP / foreground
      _exitPipMode();
      FlutterForegroundTask.stopService();
      FlutterOverlayWindow.closeOverlay();
    }
    setState(() => _stopButtonProcessing = false);
  }

  void _beginTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      setState(() {
        _elapsed += const Duration(seconds: 1);
        if (_elapsed.inSeconds % 900 == 0) _frequencyCount++;
      });
      _saveSession();
    });
  }

  void _beginLocationStream() {
    late LocationSettings settings;

    if (Theme.of(context).platform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 800),
        forceLocationManager: false,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "SKL HR App - OnDuty tracking active",
          notificationTitle: "OnDuty Location",
          notificationIcon: AndroidResource(name: "skl"),
          enableWakeLock: true,
        ),
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        timeLimit: null,
      );
    }

    _positionStream?.cancel();

    _positionStream =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (Position pos) {
        _onNewPosition(pos);
      },
      onError: (e) {
        _showSnack("Location error: $e");
      },
    );
  }

  void _onNewPosition(Position pos) {
    if (!_isTracking) return;

    final newPt = LatLng(pos.latitude, pos.longitude);

    // first point
    if (_path.isEmpty) {
      _path.add(newPt);
      _currentPosition = pos;
      _redrawMap();
      _saveSession();
      return;
    }

    final last = _path.last;
    final meters = Geolocator.distanceBetween(
      last.latitude,
      last.longitude,
      newPt.latitude,
      newPt.longitude,
    );

    // time difference
    int dt = 1;
    if (pos.timestamp != null && _currentPosition?.timestamp != null) {
      dt = pos.timestamp!
          .difference(_currentPosition!.timestamp!)
          .inSeconds
          .abs();
      if (dt == 0) dt = 1;
    }

    final speedMs = meters / dt;
    final speedKmh = speedMs * 3.6;

    final notJump = meters < 200;
    final realisticSpeed = speedKmh < 180;

    if (notJump && realisticSpeed) {
      final smoothed = _smoothPoint(_currentPosition, pos);

      _path.add(smoothed);
      _totalDistanceMeters += meters;
      _currentPosition = pos;

      if (_path.length % 2 == 0) _redrawMap();
      _saveSession();
    }
  }

  LatLng _smoothPoint(Position? prev, Position current) {
    if (prev == null) return LatLng(current.latitude, current.longitude);

    const smoothFactor = 0.6;
    final lat =
        prev.latitude + (current.latitude - prev.latitude) * smoothFactor;
    final lon =
        prev.longitude + (current.longitude - prev.longitude) * smoothFactor;

    return LatLng(lat, lon);
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

    final last = _path.last;
    _mapController?.animateCamera(CameraUpdate.newLatLng(last));

    setState(() {});
  }

  Future<bool> _onBack() async {
    if (_isTracking) {
      _showSnack('Tracking is active. Please stop tracking first.');
      return false;
    }
    return true;
  }

  @override
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onBack,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.grey[100],
        appBar: CustomAppBar(
          onMenuPressed: () {},
          barTitle: "Update Location",
          hasError: _hasError,
        ),
        drawer: const CustomDrawer(
          stkTransferCheck: false,
          brhTransferCheck: false,
        ),
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
                    enabled: !_isTracking &&
                        !_startButtonProcessing &&
                        !_startButtonClicked,
                  ),
                  const SizedBox(height: 16),
                  _buildActionCard(
                    icon: Icons.flag,
                    title: "Reached Location",
                    subtitle: "Tap to Stop and submit this session",
                    address: _addressStop,
                    color: _accentColor,
                    onTap: _onStop,
                    enabled: !_stopButtonProcessing && _isTracking,
                  ),
                  const SizedBox(height: 12),
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
                Row(
                  children: [
                    const Icon(Icons.place, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address ?? "",
                        style: const TextStyle(fontSize: 14),
                        overflow:
                            TextOverflow.ellipsis, // too long text → "..."
                      ),
                    ),
                  ],
                ),
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
