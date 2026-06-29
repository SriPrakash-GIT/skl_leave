import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminLeavePage extends StatefulWidget {
  const AdminLeavePage({super.key});

  @override
  State<AdminLeavePage> createState() => _AdminLeavePageState();
}

class _AdminLeavePageState extends State<AdminLeavePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allRequests = [];
  bool _isLoading = true;
  String? _error;
  String _adminId = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAdminId();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminId() async {
    final prefs = await SharedPreferences.getInstance();
    _adminId = prefs.getString('adminId') ?? '';
    _fetchAllLeaves();
  }

  Future<void> _fetchAllLeaves() async {
    if (mounted) setState(() { _isLoading = true; _error = null; });
    try {
      final db = FirebaseFirestore.instance;

      // Step 1: fetch all leave docs
      final leavesSnap = await db.collection('leaves').get();

      final leaves = leavesSnap.docs.map((doc) {
        final d = Map<String, dynamic>.from(doc.data());
        d['LEAVE_ID'] = doc.id;
        // Normalise CREATED_AT to DateTime for sorting
        if (d['CREATED_AT'] is Timestamp) {
          d['CREATED_AT'] = (d['CREATED_AT'] as Timestamp).toDate();
        }
        return d;
      }).toList();

      // Step 2: sort newest first (mirrors server-side sort)
      leaves.sort((a, b) {
        final dateA = a['CREATED_AT'] is DateTime
            ? a['CREATED_AT'] as DateTime
            : DateTime(0);
        final dateB = b['CREATED_AT'] is DateTime
            ? b['CREATED_AT'] as DateTime
            : DateTime(0);
        return dateB.compareTo(dateA);
      });

      // Step 3: collect unique IDCARDNO values
      final idSet = leaves
          .map((l) => l['IDCARDNO']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      // Step 4: batch-fetch employee names in parallel (mirrors Promise.all)
      final empNames = <String, String>{};
      await Future.wait(idSet.map((id) async {
        try {
          final snap = await db.collection('employees').doc(id).get();
          if (snap.exists) {
            empNames[id] = snap.data()?['name']?.toString() ?? id;
          }
        } catch (_) {}
      }));

      // Step 5: attach EMP_NAME
      for (final l in leaves) {
        final id = l['IDCARDNO']?.toString() ?? '';
        l['EMP_NAME'] = empNames[id] ?? id;
      }

      if (mounted) setState(() { _allRequests = leaves; _isLoading = false; });
    } on FirebaseException catch (e) {
      debugPrint('Firestore leaves error: ${e.code} - ${e.message}');
      if (mounted) setState(() { _error = 'Database error: ${e.message}'; _isLoading = false; });
    } catch (e) {
      debugPrint('Fetch leaves error: $e');
      if (mounted) setState(() { _error = 'Failed to load. Please try again.'; _isLoading = false; });
    }
  }


  Future<void> _updateLeaveStatus(
      String leaveId, String status, String remarks) async {
    if (leaveId.isEmpty) {
      _toast('Invalid leave ID', Colors.red);
      return;
    }
    if (!['Approved', 'Rejected'].contains(status)) {
      _toast('Invalid status', Colors.red);
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('leaves')
          .doc(leaveId)
          .update({
        'STATUS':        status,
        'ADMIN_REMARKS': remarks,
        'ADMIN_ID':      _adminId,
        'UPDATED_AT':    FieldValue.serverTimestamp(),
      });

      _toast(
        'Leave $status successfully!',
        status == 'Approved' ? Colors.green : Colors.red,
      );

      // Refresh list — same behaviour as API flow
      _fetchAllLeaves();
    } on FirebaseException catch (e) {
      debugPrint('Update leave error: ${e.code} - ${e.message}');
      _toast('Database error: ${e.message}', Colors.red);
    } catch (e) {
      debugPrint('Update leave error: $e');
      _toast('Action failed. Please try again.', Colors.red);
    }
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

  void _showActionDialog(Map<String, dynamic> leave, String action) {
    final remarksController = TextEditingController();
    final isApprove = action == 'Approved';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(isApprove ? Icons.check_circle : Icons.cancel,
                color: isApprove ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            Text('$action Leave',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Employee: ${leave['EMP_NAME'] ?? leave['IDCARDNO'] ?? ''}',
              style: GoogleFonts.poppins(fontSize: 14),
            ),
            Text(
              '${leave['LEAVE_TYPE']} • ${leave['TOTAL_DAYS']} day(s)',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey),
            ),
            Text(
              '${leave['FROM_DATE']} → ${leave['TO_DATE']}',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: remarksController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add remarks (optional)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.comment_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isApprove ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _updateLeaveStatus(
                leave['LEAVE_ID']?.toString() ?? '',
                action,
                remarksController.text.trim(),
              );
            },
            child: Text(action.toUpperCase()),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _filtered(String status) => _allRequests
      .where((l) =>
          (l['STATUS'] ?? 'Pending').toString().toLowerCase() ==
          status.toLowerCase())
      .toList();

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      default:         return Colors.orange;
    }
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pendingCount =
        _allRequests.where((l) => l['STATUS'] == 'Pending').length;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Leave Requests',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            if (pendingCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12)),
                child: Text('$pendingCount',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.indigo.shade800, Colors.purple.shade400],
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
              onPressed: _fetchAllLeaves),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorColor: Colors.orange,
          labelStyle:
              GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Pending'),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          color: Colors.orange, shape: BoxShape.circle),
                      child: Text('$pendingCount',
                          style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ]
                ],
              ),
            ),
            const Tab(text: 'Approved'),
            const Tab(text: 'Rejected'),
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
                      Icon(Icons.cloud_off,
                          size: 60, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: GoogleFonts.poppins(color: Colors.grey)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _fetchAllLeaves,
                          child: const Text('Retry')),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: ['Pending', 'Approved', 'Rejected']
                      .map((s) => _buildList(_filtered(s), s))
                      .toList(),
                ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> items, String tab) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined,
                size: 60, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No $tab requests',
                style:
                    GoogleFonts.poppins(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchAllLeaves,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final leave = items[index];
          final status = leave['STATUS'] ?? 'Pending';
          final color = _statusColor(status);
          final isPending = status == 'Pending';

          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: color.withValues(alpha: 0.3), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header row ──────────────────────────────────────────
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.indigo.shade50,
                        child: Icon(Icons.person,
                            color: Colors.indigo.shade700),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              leave['EMP_NAME'] ??
                                  leave['IDCARDNO'] ??
                                  'Employee',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Text(leave['IDCARDNO'] ?? '',
                                style: GoogleFonts.poppins(
                                    fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: color.withValues(alpha: 0.4)),
                        ),
                        child: Text(status,
                            style: GoogleFonts.poppins(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 11)),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // ── Info chips ──────────────────────────────────────────
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _chip(Icons.category_outlined,
                          leave['LEAVE_TYPE'] ?? ''),
                      _chip(
                          Icons.date_range,
                          '${leave['FROM_DATE'] ?? ''} → '
                          '${leave['TO_DATE'] ?? ''}'),
                      _chip(Icons.timer_outlined,
                          '${leave['TOTAL_DAYS'] ?? '1'} day(s)'),
                    ],
                  ),

                  // ── Reason ──────────────────────────────────────────────
                  if ((leave['REASON'] ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('"${leave['REASON']}"',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontStyle: FontStyle.italic)),
                  ],

                  // ── Admin remarks ───────────────────────────────────────
                  if ((leave['ADMIN_REMARKS'] ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Remarks: ${leave['ADMIN_REMARKS']}',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: color)),
                    ),
                  ],

                  // ── Action buttons (Pending only) ───────────────────────
                  if (isPending) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Reject'),
                            onPressed: () =>
                                _showActionDialog(leave, 'Rejected'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Approve'),
                            onPressed: () =>
                                _showActionDialog(leave, 'Approved'),
                          ),
                        ),
                      ],
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

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8)),
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