import 'package:git_leave/utils/global_variables.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class LeaveStatusPage extends StatefulWidget {
  const LeaveStatusPage({super.key});

  @override
  State<LeaveStatusPage> createState() => _LeaveStatusPageState();
}

class _LeaveStatusPageState extends State<LeaveStatusPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allLeaves = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchLeaves();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

 // Replace _fetchLeaves() with this:
Future<void> _fetchLeaves() async {
  setState(() {
    _isLoading = true;
    _error = null;
  });

  try {
    // Step 1: Get employee ID
    final prefs = await SharedPreferences.getInstance();
    final idcardno = prefs.getString('employeeId') ?? globalIDcardNo;

    if (idcardno.isEmpty) {
      setState(() {
        _error = 'Session expired. Please login again.';
        _isLoading = false;
      });
      return;
    }

    // Step 2: Query Firestore — same as .where('IDCARDNO', '==', idcardno)
    final snap = await FirebaseFirestore.instance
        .collection('leaves')
        .where('IDCARDNO', isEqualTo: idcardno)
        .get();

    // Step 3: Map docs to list
    final List<Map<String, dynamic>> data = snap.docs.map((doc) {
      final d = doc.data();
      d['LEAVE_ID'] = doc.id;

      // Convert Firestore Timestamp to readable string for CREATED_AT
      if (d['CREATED_AT'] != null && d['CREATED_AT'] is Timestamp) {
        d['CREATED_AT'] = (d['CREATED_AT'] as Timestamp).toDate();
      }
      return d;
    }).toList();

    // Step 4: Sort newest first — same as API sort logic
    data.sort((a, b) {
      final dateA = a['CREATED_AT'] is DateTime
          ? a['CREATED_AT'] as DateTime
          : DateTime(0);
      final dateB = b['CREATED_AT'] is DateTime
          ? b['CREATED_AT'] as DateTime
          : DateTime(0);
      return dateB.compareTo(dateA);
    });

    setState(() {
      _allLeaves = data;
      _isLoading = false;
    });

  } on FirebaseException catch (e) {
    debugPrint("Firestore error: ${e.code} - ${e.message}");
    setState(() {
      _error = 'Database error: ${e.message}';
      _isLoading = false;
    });
  } catch (e) {
    debugPrint("Unexpected error: $e");
    setState(() {
      _error = 'Error: ${e.toString()}';
      _isLoading = false;
    });
  }
}

  List<Map<String, dynamic>> _filtered(String status) {
    if (status == 'All') return _allLeaves;
    return _allLeaves
        .where((l) =>
            (l['STATUS'] ?? '').toString().toLowerCase() ==
            status.toLowerCase())
        .toList();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'pending':
        return Icons.hourglass_top;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          'My Leave Status',
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade800, Colors.green.shade400],
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchLeaves,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          labelStyle:
              GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Rejected'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off,
                          size: 60, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: GoogleFonts.poppins(color: Colors.grey)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _fetchLeaves,
                          child: const Text('Retry')),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: ['All', 'Pending', 'Approved', 'Rejected']
                      .map((status) => _buildList(_filtered(status)))
                      .toList(),
                ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> leaves) {
    if (leaves.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 60, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No leaves found',
                style:
                    GoogleFonts.poppins(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchLeaves,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: leaves.length,
        itemBuilder: (context, index) {
          final leave = leaves[index];
          final status = leave['STATUS'] ?? 'Pending';
          final color = _statusColor(status);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: color.withOpacity(0.3), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          leave['LEAVE_TYPE'] ?? 'Leave',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: color.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_statusIcon(status), size: 14, color: color),
                            const SizedBox(width: 4),
                            Text(status,
                                style: GoogleFonts.poppins(
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _infoChip(Icons.calendar_today,
                          '${leave['FROM_DATE'] ?? ''} → ${leave['TO_DATE'] ?? ''}'),
                      const SizedBox(width: 8),
                      _infoChip(Icons.access_time,
                          '${leave['TOTAL_DAYS'] ?? '1'} day(s)'),
                    ],
                  ),
                  if ((leave['REASON'] ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notes, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            leave['REASON'],
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: Colors.grey.shade700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if ((leave['ADMIN_REMARKS'] ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: color.withOpacity(0.2)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.admin_panel_settings,
                              size: 14, color: color),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Admin: ${leave['ADMIN_REMARKS']}',
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: color,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 11, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}
