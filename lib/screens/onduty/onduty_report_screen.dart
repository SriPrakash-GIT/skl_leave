import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';        // ← add
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:git_leave/utils/global_variables.dart';
import 'package:git_leave/screens/auth/login_screen.dart';


class OnDutyReportPage extends StatefulWidget {
  const OnDutyReportPage({super.key});

  @override
  State<OnDutyReportPage> createState() => _OnDutyReportPageState();
}

class _OnDutyReportPageState extends State<OnDutyReportPage> {
  final _formKey = GlobalKey<FormState>();
  final _purposeController = TextEditingController();
  final _siteNameController = TextEditingController();
  final _remarkController = TextEditingController();

  bool _isTracking = false;
  bool _isSubmitting = false;
  bool _isStarting = false;

  Position? _currentPosition;
  Position? _startPosition;
  String _startAddress = '';
  String _currentAddress = '';
  String? _startTime;
  String? _endTime;
  String? _activeOdId;            

  Timer? _timer;
  Duration _elapsed = Duration.zero;

  GoogleMapController? _mapController;
  final List<LatLng> _path = [];
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  StreamSubscription<Position>? _positionStream;
  double _totalDistanceMeters = 0.0;
  Position? _lastTrackedPosition;

  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
    _fetchHistory();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel();
    _mapController?.dispose();
    _purposeController.dispose();
    _siteNameController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  String _fmtHHmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String get _elapsedStr {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes.remainder(60);
    final s = _elapsed.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final tracking = prefs.getBool('od_isTracking') ?? false;
    if (!tracking) return;

    setState(() {
      _isTracking = true;
      _startTime = prefs.getString('od_startTime');
      _startAddress = prefs.getString('od_startAddress') ?? '';
      _elapsed = Duration(seconds: prefs.getInt('od_elapsedSeconds') ?? 0);
      _siteNameController.text = prefs.getString('od_siteName') ?? '';
      _purposeController.text = prefs.getString('od_purpose') ?? '';
      _totalDistanceMeters = prefs.getDouble('od_distance') ?? 0.0;
      _activeOdId = prefs.getString('od_activeId');   // ← restore doc ID
    });

    _beginTimer();
    _beginLocationStream();
  }

  Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('od_isTracking', _isTracking);
    await prefs.setString('od_startTime', _startTime ?? '');
    await prefs.setString('od_startAddress', _startAddress);
    await prefs.setInt('od_elapsedSeconds', _elapsed.inSeconds);
    await prefs.setString('od_siteName', _siteNameController.text);
    await prefs.setString('od_purpose', _purposeController.text);
    await prefs.setDouble('od_distance', _totalDistanceMeters);
    if (_activeOdId != null) {
      await prefs.setString('od_activeId', _activeOdId!);  // ← save doc ID
    }
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [
      'od_isTracking', 'od_startTime', 'od_startAddress',
      'od_elapsedSeconds', 'od_siteName', 'od_purpose',
      'od_distance', 'od_activeId',
    ]) {
      await prefs.remove(k);
    }
  }

  // ── FETCH HISTORY — replaces GET /api/onDutyHistory/:idcardno ──
  Future<void> _fetchHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('onduty')
          .where('IDCARDNO', isEqualTo: globalIDcardNo)
          .get();

      final data = snap.docs.map((doc) {
        final d = doc.data();
        d['OD_ID'] = doc.id;
        // Convert Timestamp for sorting
        if (d['CREATED_AT'] is Timestamp) {
          d['CREATED_AT'] = (d['CREATED_AT'] as Timestamp).toDate();
        }
        return d;
      }).toList();

      // Sort newest first — same as API sort logic
      data.sort((a, b) {
        final dateA = a['CREATED_AT'] is DateTime
            ? a['CREATED_AT'] as DateTime
            : DateTime(0);
        final dateB = b['CREATED_AT'] is DateTime
            ? b['CREATED_AT'] as DateTime
            : DateTime(0);
        return dateB.compareTo(dateA);
      });

      if (mounted) setState(() => _history = data);
    } on FirebaseException catch (e) {
      debugPrint("Firestore history error: ${e.code} - ${e.message}");
    } catch (e) {
      debugPrint("History error: $e");
    }
    if (mounted) setState(() => _loadingHistory = false);
  }

  Future<String> _getAddress(Position pos) async {
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
        return parts.join(', ');
      }
    } catch (_) {}
    return '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
  }

  // ── START ON DUTY — replaces POST /api/applyOnduty ──
  Future<void> _startOnDuty() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isStarting = true);

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _toast('Please enable location services', Colors.red);
      setState(() => _isStarting = false);
      return;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied)
      perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      _toast('Location permission required', Colors.red);
      setState(() => _isStarting = false);
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation);
    final addr = await _getAddress(pos);

    try {
      // Create new onduty doc — same as applyOnduty API logic
      final odRef = FirebaseFirestore.instance.collection('onduty').doc();
      await odRef.set({
        'OD_ID':          odRef.id,
        'IDCARDNO':       globalIDcardNo,
        'PDATE':          DateTime.now().toIso8601String().split('T').first,
        'SITE_NAME':      _siteNameController.text.trim(),
        'PURPOSE':        _purposeController.text.trim(),
        'REASON':         _purposeController.text.trim(),
        'ONDUTYLOCATION': _siteNameController.text.trim(),
        'START_ADDR':     addr,
        'END_ADDR':       '',
        'TYPE':           'On Duty',
        'DISTANCE':       '0',
        'DURATION':       '0',
        'TIME_TAKEN':     '0',
        'REMARKS':        '',
        'STATUS':         'Active',
        'APPROVE':        'N',
        'REJECT':         'N',
        'ACTIVE':         'T',
        'CREATED_AT':     FieldValue.serverTimestamp(),
      });

      _activeOdId = odRef.id;     // ← save doc ID for stop
      _startPosition = pos;
      _startAddress = addr;
      _startTime = _fmtHHmm(DateTime.now());

      setState(() {
        _isTracking = true;
        _path.add(LatLng(pos.latitude, pos.longitude));
        _markers.add(Marker(
          markerId: const MarkerId('start'),
          position: LatLng(pos.latitude, pos.longitude),
          infoWindow: const InfoWindow(title: 'Start'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen),
        ));
      });

      _beginTimer();
      _beginLocationStream();
      await _saveSession();
      _toast('On Duty started successfully!', Colors.green);

    } on FirebaseException catch (e) {
      debugPrint("Firestore start error: ${e.code} - ${e.message}");
      // Allow offline start
      _startPosition = pos;
      _startAddress = addr;
      _startTime = _fmtHHmm(DateTime.now());
      setState(() {
        _isTracking = true;
        _path.add(LatLng(pos.latitude, pos.longitude));
      });
      _beginTimer();
      _beginLocationStream();
      await _saveSession();
      _toast('Started offline. Will sync when connected.', Colors.orange);
    } catch (e) {
      debugPrint("Start error: $e");
      _toast('Error starting on duty: $e', Colors.red);
    }

    setState(() => _isStarting = false);
  }

  // ── STOP ON DUTY — replaces POST /api/onDutyStop ──
  Future<void> _stopOnDuty() async {
    setState(() => _isSubmitting = true);
    _timer?.cancel();
    await _positionStream?.cancel();

    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation);
    final addr = await _getAddress(pos);
    _endTime = _fmtHHmm(DateTime.now());

    debugPrint('DEBUG: globalIDcardNo = $globalIDcardNo');
    debugPrint('DEBUG: activeOdId = $_activeOdId');

    if (globalIDcardNo.isEmpty) {
      _toast('Error: Employee ID not found. Please login again.', Colors.red);
      setState(() => _isSubmitting = false);
      return;
    }

    try {
      String? docId = _activeOdId;

      // If no saved doc ID, find active record — same as API query
      if (docId == null || docId.isEmpty) {
        final odSnap = await FirebaseFirestore.instance
            .collection('onduty')
            .where('IDCARDNO', isEqualTo: globalIDcardNo)
            .where('ACTIVE', isEqualTo: 'T')
            .limit(1)
            .get();

        if (odSnap.docs.isEmpty) {
          _toast('No active on-duty record found.', Colors.red);
          setState(() => _isSubmitting = false);
          return;
        }
        docId = odSnap.docs.first.id;
      }

      // Update doc — same as onDutyStop API logic
      await FirebaseFirestore.instance
          .collection('onduty')
          .doc(docId)
          .update({
            'END_LAT':    pos.latitude,
            'END_LNG':    pos.longitude,
            'END_ADDR':   addr,
            'END_TIME':   _endTime,
            'DURATION':   _elapsed.inSeconds.toString(),
            'DISTANCE':   _totalDistanceMeters.toStringAsFixed(2),
            'REMARKS':    _remarkController.text.trim(),
            'STATUS':     'Completed',
            'ACTIVE':     'F',
            'UPDATED_AT': FieldValue.serverTimestamp(),
          });

      _toast('On Duty completed and saved!', Colors.green);

    } on FirebaseException catch (e) {
      debugPrint("Firestore stop error: ${e.code} - ${e.message}");
      _toast('Database error: ${e.message}', Colors.orange);
    } catch (e) {
      debugPrint("Stop error: $e");
      _toast('Saved locally. Will sync when connected.', Colors.orange);
    }

    await _clearSession();
    setState(() {
      _isTracking = false;
      _isSubmitting = false;
      _elapsed = Duration.zero;
      _totalDistanceMeters = 0.0;
      _path.clear();
      _markers.clear();
      _polylines.clear();
      _startPosition = null;
      _startAddress = '';
      _startTime = null;
      _endTime = null;
      _lastTrackedPosition = null;
      _activeOdId = null;
    });

    _fetchHistory();
  }

  void _beginTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsed += const Duration(seconds: 1));
        if (_elapsed.inSeconds % 60 == 0) _saveSession();
      }
    });
  }

  void _beginLocationStream() {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      if (!_isTracking) return;
      final newPt = LatLng(pos.latitude, pos.longitude);

      if (_lastTrackedPosition != null) {
        final dist = Geolocator.distanceBetween(
          _lastTrackedPosition!.latitude,
          _lastTrackedPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        if (dist < 5) return;
        _totalDistanceMeters += dist;
      }

      _lastTrackedPosition = pos;
      _path.add(newPt);
      _polylines
        ..clear()
        ..add(Polyline(
          polylineId: const PolylineId('onduty'),
          points: List<LatLng>.from(_path),
          width: 5,
          color: Colors.blue,
        ));

      _mapController?.animateCamera(CameraUpdate.newLatLng(newPt));
      if (mounted) setState(() {});
    });
  }

  void _toast(String msg, Color color) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: color,
      textColor: Colors.white,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
    );
  }

  // ── BUILD & WIDGETS unchanged below ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text('On Duty Report',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade700, Colors.green.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isTracking)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal.shade700, Colors.teal.shade900],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.circle,
                            color: Colors.greenAccent, size: 10),
                        const SizedBox(width: 6),
                        Text('ON DUTY - LIVE TRACKING',
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _statItem('Duration', _elapsedStr),
                        _statItem('Distance',
                            '${(_totalDistanceMeters / 1000).toStringAsFixed(2)} km'),
                        _statItem('Start', _startTime ?? '--:--'),
                      ],
                    ),
                  ],
                ),
              ),

            if (_isTracking && _path.isNotEmpty)
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                margin: const EdgeInsets.only(bottom: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 220,
                    child: GoogleMap(
                      initialCameraPosition:
                          CameraPosition(target: _path.last, zoom: 15),
                      onMapCreated: (c) => _mapController = c,
                      polylines: _polylines,
                      markers: _markers,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                    ),
                  ),
                ),
              ),

            if (!_isTracking)
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.work_outline, color: Colors.teal.shade700),
                          const SizedBox(width: 8),
                          Text('On Duty Details',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                        ]),
                        const Divider(height: 20),
                        TextFormField(
                          controller: _siteNameController,
                          decoration: _inputDeco(
                              'Site / Customer Name', Icons.location_city),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter site name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _purposeController,
                          decoration:
                              _inputDeco('Purpose of Visit', Icons.task_alt),
                          maxLines: 2,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter purpose'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isStarting ? null : _startOnDuty,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal.shade700,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _isStarting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.play_arrow),
                            label: Text(
                                _isStarting ? 'Starting...' : 'Start On Duty',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            if (_isTracking)
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.notes, color: Colors.teal.shade700),
                        const SizedBox(width: 8),
                        Text('Add Remarks & Complete',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                      ]),
                      const Divider(height: 20),
                      if (_startAddress.isNotEmpty) ...[
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.place,
                                  size: 16, color: Colors.grey),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text('Started from: $_startAddress',
                                      style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: Colors.grey.shade700))),
                            ]),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _remarkController,
                        maxLines: 3,
                        decoration: _inputDeco(
                            'Work done / remarks...', Icons.edit_note),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _stopOnDuty,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.stop),
                          label: Text(
                              _isSubmitting
                                  ? 'Submitting...'
                                  : 'Complete On Duty',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            Row(children: [
              Icon(Icons.history, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text('On Duty History',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.grey.shade800)),
            ]),
            const SizedBox(height: 10),
            _loadingHistory
                ? const Center(child: CircularProgressIndicator())
                : _history.isEmpty
                    ? Center(
                        child: Text('No history yet',
                            style:
                                GoogleFonts.poppins(color: Colors.grey)))
                    : Column(
                        children: _history
                            .take(10)
                            .map((item) => _historyCard(item))
                            .toList(),
                      ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(children: [
      Text(label,
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11)),
      const SizedBox(height: 4),
      Text(value,
          style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14)),
    ]);
  }

  Widget _historyCard(Map<String, dynamic> item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.teal.shade50,
          child:
              Icon(Icons.work, color: Colors.teal.shade700, size: 20),
        ),
        title: Text(item['SITE_NAME'] ?? 'On Duty',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item['PDATE'] ?? '',
                style:
                    GoogleFonts.poppins(fontSize: 11, color: Colors.grey)),
            Text(
              '${item['STATUS'] ?? 'Active'}'
              ' | ${((double.tryParse(item['DISTANCE']?.toString() ?? '0') ?? 0) / 1000).toStringAsFixed(2)} km',
              style:
                  GoogleFonts.poppins(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        trailing: Text(
          _formatDuration(
              int.tryParse(item['DURATION']?.toString() ?? '0') ?? 0),
          style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.teal.shade700,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.teal.shade600),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.teal.shade700, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }
}