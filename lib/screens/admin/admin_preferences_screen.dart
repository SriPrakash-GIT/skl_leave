import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminPreferencesPage extends StatefulWidget {
  final String adminId;
  const AdminPreferencesPage({super.key, required this.adminId});

  @override
  State<AdminPreferencesPage> createState() => _AdminPreferencesPageState();
}

class _AdminPreferencesPageState extends State<AdminPreferencesPage> {
  bool _isLoading = true;
  bool _isSaving = false;

  bool _notifyLeave = true;
  bool _notifyOnduty = true;
  bool _notifyPerm = true;
  bool _canApproveLeave = true;
  bool _canApproveOnduty = true;

  String _unitAccess = 'ALL';
  final List<String> _unitOptions = ['ALL', 'Engineering', 'Finance', 'HR', 'Operations'];
  String _theme = 'light';
  String _language = 'en';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
  setState(() => _isLoading = true);
  try {
    final doc = await FirebaseFirestore.instance
        .collection('admin_preferences')
        .doc(widget.adminId)
        .get();

    if (doc.exists) {
      final prefs = doc.data()!;
      setState(() {
        _notifyLeave      = (prefs['notifyLeave']      ?? 'Y') == 'Y';
        _notifyOnduty     = (prefs['notifyOnduty']     ?? 'Y') == 'Y';
        _notifyPerm       = (prefs['notifyPerm']       ?? 'Y') == 'Y';
        _canApproveLeave  = (prefs['canApproveLeave']  ?? 'Y') == 'Y';
        _canApproveOnduty = (prefs['canApproveOnduty'] ?? 'Y') == 'Y';
        _unitAccess       = prefs['unitAccess'] ?? 'ALL';
        _theme            = prefs['theme']      ?? 'light';
        _language         = prefs['language']   ?? 'en';
      });
    }
    // If doc doesn't exist yet, defaults defined in state are used
  } on FirebaseException catch (e) {
    debugPrint('Firestore load prefs error: ${e.code} - ${e.message}');
    _showToast('Error loading preferences', Colors.red);
  } catch (e) {
    debugPrint('Load prefs error: $e');
    _showToast('Error loading preferences', Colors.red);
  }
  if (mounted) setState(() => _isLoading = false);
}

Future<void> _savePreferences() async {
  setState(() => _isSaving = true);
  try {
    await FirebaseFirestore.instance
        .collection('admin_preferences')
        .doc(widget.adminId)
        .set({
      'idcardno'        : widget.adminId,
      'notifyLeave'     : _notifyLeave      ? 'Y' : 'N',
      'notifyOnduty'    : _notifyOnduty     ? 'Y' : 'N',
      'notifyPerm'      : _notifyPerm       ? 'Y' : 'N',
      'canApproveLeave' : _canApproveLeave  ? 'Y' : 'N',
      'canApproveOnduty': _canApproveOnduty ? 'Y' : 'N',
      'unitAccess'      : _unitAccess,
      'theme'           : _theme,
      'language'        : _language,
      'updatedAt'       : FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)); // merge:true so it creates or updates

    _showToast('Preferences saved!', Colors.green);
  } on FirebaseException catch (e) {
    debugPrint('Firestore save prefs error: ${e.code} - ${e.message}');
    _showToast('Error saving preferences', Colors.red);
  } catch (e) {
    debugPrint('Save prefs error: $e');
    _showToast('Error saving preferences', Colors.red);
  }
  if (mounted) setState(() => _isSaving = false);
}

  void _showToast(String msg, Color color) {
    Fluttertoast.showToast(
        msg: msg,
        backgroundColor: color,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text('Admin Preferences',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple.shade800, Colors.indigo.shade400],
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSection(
                    title: 'Notification Preferences',
                    icon: Icons.notifications,
                    color: Colors.blue,
                    children: [
                      _buildSwitch('Leave Requests', 'Notify for new leave requests',
                          _notifyLeave, (v) => setState(() => _notifyLeave = v)),
                      const Divider(),
                      _buildSwitch('On Duty Requests', 'Notify for on duty requests',
                          _notifyOnduty, (v) => setState(() => _notifyOnduty = v)),
                      const Divider(),
                      _buildSwitch('Permission Updates', 'Notify for permission changes',
                          _notifyPerm, (v) => setState(() => _notifyPerm = v)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    title: 'Approval Permissions',
                    icon: Icons.check_circle,
                    color: Colors.green,
                    children: [
                      _buildSwitch('Approve Leave', 'Can approve leave requests',
                          _canApproveLeave, (v) => setState(() => _canApproveLeave = v)),
                      const Divider(),
                      _buildSwitch('Approve On Duty', 'Can approve on duty requests',
                          _canApproveOnduty, (v) => setState(() => _canApproveOnduty = v)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    title: 'Access Control',
                    icon: Icons.security,
                    color: Colors.orange,
                    children: [
                      Text('Unit Access',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _unitAccess,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          prefixIcon: Icon(Icons.domain,
                              color: Colors.orange.shade600),
                        ),
                        items: _unitOptions
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _unitAccess = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    title: 'Display Settings',
                    icon: Icons.display_settings,
                    color: Colors.teal,
                    children: [
                      Text('Theme',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode)),
                          ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                        ],
                        selected: {_theme},
                        onSelectionChanged: (s) => setState(() => _theme = s.first),
                      ),
                      const SizedBox(height: 16),
                      Text('Language',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _language,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          prefixIcon: Icon(Icons.language,
                              color: Colors.teal.shade600),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'en', child: Text('English')),
                          DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                          DropdownMenuItem(value: 'ta', child: Text('Tamil')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _language = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _savePreferences,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade800,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: Text(
                      _isSaving ? 'Saving...' : 'Save Preferences',
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Text(title,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            ]),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSwitch(String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                Text(subtitle,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}