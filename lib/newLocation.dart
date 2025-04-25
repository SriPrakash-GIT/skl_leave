import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:skl_leave/login.dart';
import 'custom/appBar.dart';
import 'custom/sideBar.dart';
import 'package:http/http.dart' as http;
import 'globalVariable.dart';
import 'dart:convert';

class ReachedWorkPage extends StatefulWidget {
  @override
  _ReachedWorkPageState createState() => _ReachedWorkPageState();
}

class _ReachedWorkPageState extends State<ReachedWorkPage> {
  Timer? _timer;
  int _frequencyCount = 0;
  Duration _elapsed = Duration.zero;
  Position? _currentPosition;
  String? _address;
  bool _isTracking = false;
  bool _showMap = false;
  String _formatEndTime(DateTime time) {
    return "${time.hour.toString().padLeft(2, '0')}:"
        "${time.minute.toString().padLeft(2, '0')}:"
        "${time.second.toString().padLeft(2, '0')}";
  }

  String screenType = "Update Location";
  String? endTime;
  String? starNewTime;
  GoogleMapController? _mapController;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Colors
  final Color _primaryColor = Colors.deepPurple.shade300;
  final Color _accentColor = Colors.deepOrange.shade300;
  final Color _darkColor = Color(0xFF2D3436);
  final Color _lightColor = Color(0xFFF5F6Fd);

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
      _showSnackBar(
          'Location permissions are permanently denied. Please enable them in settings.');
      return;
    }

    try {
      setState(() => _isTracking = true);
      _showSnackBar('📍 Location tracking started');
      DateTime starTime = DateTime.now();
      starNewTime = _formatEndTime(starTime);
      // Get current position with high accuracy
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      print(_currentPosition.toString());
      // Get detailed address information
      List<Placemark> placemarks = await placemarkFromCoordinates(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;

        // Build a comprehensive address string with all available components
        List<String> addressComponents = [];

        if (place.street != null && place.street!.isNotEmpty) {
          addressComponents.add(place.street!);
        }
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          addressComponents.add(place.subLocality!);
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          addressComponents.add(place.locality!);
        }

        if (place.administrativeArea != null &&
            place.administrativeArea!.isNotEmpty) {
          addressComponents.add(place.administrativeArea!);
        }
        if (place.postalCode != null && place.postalCode!.isNotEmpty) {
          addressComponents.add(place.postalCode!);
        }
        if (place.country != null && place.country!.isNotEmpty) {
          addressComponents.add(place.country!);
        }

        String formattedAddress = addressComponents.join(', ');

        setState(() {
          _address = formattedAddress;
          _showMap = true;
        });

        print('Full Address: $_address');
        print('Street: ${place.street}');
        print('Landmark: ${place.subLocality}');
        print('Area: ${place.locality}');
        print('City: ${place.name}');
        print('State: ${place.administrativeArea}');
        print('Country: ${place.country}');
        print('Postal Code: ${place.postalCode}');
      }

      // Update map view if controller is available
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            16.0, // Slightly higher zoom level for better detail
          ),
        );
      }

      // Reset and start timer
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
    } catch (e) {
      _showSnackBar('Error getting location: ${e.toString()}');
      setState(() => _isTracking = false);
    }
  }

  void _stopWorkDone() {
    if (!_isTracking) return;
    DateTime stopTime = DateTime.now();
    endTime = _formatEndTime(stopTime);

    _timer?.cancel();
    _timer = null;
    setState(() => _isTracking = false);
    sendNewLocation(
      globalIDcardNo,
      screenType,
      _currentPosition.toString(),
      starNewTime.toString(),
      endTime.toString(),
      _frequencyCount.toString(),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        backgroundColor: _darkColor,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> sendNewLocation(
      String globalIDcardNo,
      String type,
      String coOrdinate,
      String starTime,
      String endTime,
      String frequency) async {
    String url = "$ipAddress/api/sendNewLocation";
    try {
      final response = await http.post(Uri.parse(url),
          headers: <String, String>{
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: jsonEncode({
            "IDCARDNO": globalIDcardNo,
            "TYPE": type.toString(),
            "COORDINATE": coOrdinate,
            "STIME": starTime,
            "ENDTIME": endTime,
            "FREQUENCY": frequency,
          }));
      final responseData = jsonDecode(response.body);
      if (responseData["STATUS"] == true) {
        _showSnackBar('On-duty location was saved successfully.');
      } else {
        _showErrorDialog("Alert", "${responseData["MESSAGE"]}");
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
      backgroundColor: _lightColor,
      appBar: CustomAppBar(
        onMenuPressed: () {},
        barTitle: "Update Location",
      ),
      drawer: const CustomDrawer(
        stkTransferCheck: false,
        brhTransferCheck: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20), // Top padding
                _buildActionCard(
                  icon: Icons.location_pin,
                  title: ' REACHED LOCATION',
                  subtitle: _currentPosition != null
                      ? '${_currentPosition!.latitude.toStringAsFixed(4)}, '
                          '${_currentPosition!.longitude.toStringAsFixed(4)}'
                      : '🧭 Tap here to fetch location',
                  address: _address,
                  color: _primaryColor,
                  onTap: _startReachedTime,
                  isActive: !_isTracking,
                ),
                const SizedBox(height: 30),
                _buildActionCard(
                  icon: Icons.work,
                  title: 'WORK DONE',
                  subtitle: '✅ Close this work session',
                  color: _accentColor,
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

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    String? address,
    required Color color,
    required VoidCallback onTap,
    required bool isActive,
  }) {
    return InkWell(
      onTap: isActive ? onTap : null,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: double.infinity, // Make card take full available width
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.9),
              color.withOpacity(0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 40, color: Colors.white),
            SizedBox(height: 10),
            Text(title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                )),
            if (subtitle != null) ...[
              SizedBox(height: 5),
              Text(subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  )),
            ],
            if (address != null) ...[
              SizedBox(height: 5),
              Text(
                address,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
            if (!isActive) ...[
              SizedBox(height: 10),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Active Session',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
