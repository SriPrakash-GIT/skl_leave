import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'globalVariable.dart';

class AdminTrackingPage extends StatefulWidget {
  const AdminTrackingPage({super.key});

  @override
  State<AdminTrackingPage> createState() => _AdminTrackingPageState();
}

class _AdminTrackingPageState extends State<AdminTrackingPage> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetchEmployeeLocations();
    // auto refresh every 10 sec
    _timer = Timer.periodic(Duration(seconds: 10), (t) {
      _fetchEmployeeLocations();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _fetchEmployeeLocations() async {
    String url = "$ipAddress/api/getAdminTrackEmpLocations";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        Set<Marker> newMarkers = {};
        for (var emp in data) {
          double lat = double.parse(emp["LATITUDE"].toString());
          double lng = double.parse(emp["LONGITUDE"].toString());
          String name = emp["IDCARDNO"];

          newMarkers.add(
            Marker(
              markerId: MarkerId(name),
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(
                title: name,
                snippet: "Last update: ${emp["STIME"] ?? ''}",
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure,
              ),
            ),
          );
        }

        setState(() {
          _markers = newMarkers;
        });
      }
    } catch (e) {
      print("Error fetching live locations: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Live Employee Tracking")),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(11.0, 77.0), // Default center
          zoom: 12,
        ),
        markers: _markers,
        onMapCreated: (controller) => _mapController = controller,
      ),
    );
  }
}
