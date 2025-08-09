import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:skl_leave/login.dart';
import 'custom/appBar.dart';
import 'custom/sideBar.dart';
import 'globalVariable.dart';

class ReachedWorkPage extends StatefulWidget {
  @override
  _ReachedWorkPageState createState() => _ReachedWorkPageState();
}

class _ReachedWorkPageState extends State<ReachedWorkPage> {
  Timer? _timer;
  int _frequencyCount = 0;
  Duration _elapsed = Duration.zero;
  Position? _currentPosition;
  String? _address = "";
  String? _address1;
  bool _isTracking = false;
  bool _showMap = false;
  String screenType = "Update Location";
  String? endTime;
  String? starNewTime;
  GoogleMapController? _mapController;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Distance tracking variables
  StreamSubscription<Position>? _positionStream;
  List<LatLng> _path = [];
  double _totalDistanceInMeters = 0.0;

  final Color _primaryColor = Colors.orange.shade600;
  final Color _accentColor = Colors.purple.shade900;
  final Color _darkColor = Color(0xFF2D3336);
  final Color _lightColor = Color(0xFFF5F6Fd);

  String _formatEndTime(DateTime time) {
    return "${time.hour.toString().padLeft(2, '0')}:"
        "${time.minute.toString().padLeft(2, '0')}:"
        "${time.second.toString().padLeft(2, '0')}";
  }

  Future<void> _startReachedTime() async {
    if (_isTracking) return;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('Please enable location services to continue');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('Location permissions are required for this feature');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar('Location permissions are permanently denied.');
      return;
    }

    try {
      setState(() {
        _isTracking = true;
        _path.clear();
        _totalDistanceInMeters = 0.0;
      });

      _showSnackBar('📍 Location tracking started');

      DateTime starTime = DateTime.now();
      starNewTime = _formatEndTime(starTime);
      List<String> value = starNewTime!.split(":");
      starNewTime = value[0] + ":" + value[1];

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        List<String> addressComponents = [];

        if (place.street != null && place.street!.isNotEmpty)
          addressComponents.add(place.street!);
        if (place.subLocality != null && place.subLocality!.isNotEmpty)
          addressComponents.add(place.subLocality!);
        if (place.locality != null && place.locality!.isNotEmpty)
          addressComponents.add(place.locality!);
        if (place.administrativeArea != null &&
            place.administrativeArea!.isNotEmpty)
          addressComponents.add(place.administrativeArea!);
        if (place.postalCode != null && place.postalCode!.isNotEmpty)
          addressComponents.add(place.postalCode!);

        String formattedAddress = addressComponents.join(', ');
        setState(() {
          _address = formattedAddress;
          _showMap = true;
        });
      }

      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            16.0,
          ),
        );
      }

      _timer?.cancel();
      setState(() {
        _frequencyCount = 0;
        _elapsed = Duration.zero;
      });

      _timer = Timer.periodic(Duration(seconds: 1), (timer) {
        setState(() {
          _elapsed += Duration(seconds: 1);
          if (_elapsed.inSeconds % 900 == 0) _frequencyCount++;
        });
      });

      // Start distance tracking
      _positionStream = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      ).listen((Position position) {
        LatLng newPoint = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPosition = position;
          if (_path.isNotEmpty) {
            _totalDistanceInMeters += Geolocator.distanceBetween(
              _path.last.latitude,
              _path.last.longitude,
              newPoint.latitude,
              newPoint.longitude,
            );
          }
          _path.add(newPoint);
        });
      });

      sendNewLocation(
          globalIDcardNo,
          screenType,
          _currentPosition.toString(),
          starNewTime.toString(),
          "",
          _frequencyCount.toString(),
          _address.toString(),
          "",
          true);
    } catch (e) {
      _showSnackBar('Error getting location: ${e.toString()}');
      setState(() => _isTracking = false);
    }
  }

  void _stopWorkDone() async {
    DateTime stopTime = DateTime.now();
    endTime = _formatEndTime(stopTime);
    List<String> value = endTime!.split(":");
    endTime = value[0] + ":" + value[1];

    _timer?.cancel();
    _timer = null;

    _positionStream?.cancel();

    Duration duration = _elapsed;

    try {
      // Fetch latest position
      Position stopPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Get address from coordinates
      List<Placemark> placemarks = await placemarkFromCoordinates(
        stopPosition.latitude,
        stopPosition.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        List<String> addressComponents = [];

        if (place.street != null && place.street!.isNotEmpty)
          addressComponents.add(place.street!);
        if (place.subLocality != null && place.subLocality!.isNotEmpty)
          addressComponents.add(place.subLocality!);
        if (place.locality != null && place.locality!.isNotEmpty)
          addressComponents.add(place.locality!);
        if (place.administrativeArea != null &&
            place.administrativeArea!.isNotEmpty)
          addressComponents.add(place.administrativeArea!);
        if (place.postalCode != null && place.postalCode!.isNotEmpty)
          addressComponents.add(place.postalCode!);

        String formattedAddress = addressComponents.join(', ');
        setState(() {
          _address1 = formattedAddress;
        });
      }

      _showSnackBar(
        "🏁 Total Distance: ${(_totalDistanceInMeters / 1000).toStringAsFixed(2)} km, ⏱️ ${duration.inMinutes} min",
      );

      setState(() => _isTracking = false);

      sendNewLocation(
          globalIDcardNo,
          screenType,
          stopPosition.toString(),
          "",
          endTime.toString(),
          _frequencyCount.toString(),
          "",
          _address1.toString(),
          false);
    } catch (e) {
      _showSnackBar("❌ Error fetching stop location: ${e.toString()}");
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: _darkColor,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> sendNewLocation(
      String globalIDcardNo,
      String type,
      String coOrdinate,
      String starTime,
      String endTime,
      String frequency,
      String sAddress,
      String eAddress,
      bool start) async {
    String url = "$ipAddress/api/sendNewLocation";

    print(globalIDcardNo);
    print("globalIDcardNo ");

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          "IDCARDNO": globalIDcardNo,
          "TYPE": type,
          "COORDINATE": coOrdinate,
          "STIME": starTime,
          "ENDTIME": endTime,
          "STARTADDRESS": sAddress,
          "ENDLOCATION": eAddress,
          "FREQUENCY": frequency,
          "DISTANCE": _totalDistanceInMeters.toStringAsFixed(2),
          "DURATION": _elapsed.inSeconds.toString(),
        }),
      );
      final Map<String, dynamic> responseData = json.decode(response.body);
      if (responseData["status"] == true) {
        _showSnackBar("${responseData["message"]}");
      } else {
        _showErrorDialog("Alert", "${responseData["message"]}");
        if (start) {
          setState(() {
            _isTracking = false;
            _path.clear();
            _totalDistanceInMeters = 0.0;
          });
          _showErrorDialog("Alert", "Please try again");
        }
      }
    } catch (e) {
      _showErrorDialog("Connection Error", "Please try again later");
    }
  }

  void _showErrorDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(
        onMenuPressed: () {},
        barTitle: "Update Location",
      ),
      drawer: const CustomDrawer(
        stkTransferCheck: false,
        brhTransferCheck: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                _buildModernCard(
                  icon: Icons.location_on,
                  title: "Start Location",
                  subtitle: "Tap to Start your OnDuty",
                  address: _address,
                  color: _primaryColor,
                  onTap: _startReachedTime,
                  isActive: !_isTracking,
                ),
                const SizedBox(height: 30),
                _buildModernCard(
                  icon: Icons.done_all,
                  title: "Reached Location",
                  subtitle: "Tap to Stop and submit this session",
                  color: _accentColor,
                  address: _address1,
                  onTap: _stopWorkDone,
                  isActive: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernCard({
    required IconData icon,
    required String title,
    required String subtitle,
    String? address,
    required Color color,
    required VoidCallback onTap,
    bool isActive = true,
  }) {
    return Opacity(
      opacity: isActive ? 1 : 0.5,
      child: Card(
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withOpacity(0.2),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              if (address != null && address.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.place, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: isActive ? onTap : null,
                  icon: const Icon(
                    Icons.touch_app,
                    color: Colors.white,
                  ),
                  label: const Text(
                    "Tap to Continue",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
