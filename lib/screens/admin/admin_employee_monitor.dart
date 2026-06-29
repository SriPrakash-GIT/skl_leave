import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminEmployeeMonitorPage extends StatefulWidget {
  const AdminEmployeeMonitorPage({super.key});

  @override
  State<AdminEmployeeMonitorPage> createState() =>
      _AdminEmployeeMonitorPageState();
}

class _AdminEmployeeMonitorPageState extends State<AdminEmployeeMonitorPage> {
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  String? _error;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _employees
          : _employees
              .where((e) =>
                  (e['name'] ?? '').toString().toLowerCase().contains(q) ||
                  (e['idcardno'] ?? '').toString().toLowerCase().contains(q))
              .toList();
    });
  }
  

Future<void> _fetchEmployees() async {
  setState(() { _isLoading = true; _error = null; });
  try {
    // Step 1: Get all active employees
    final empSnap = await FirebaseFirestore.instance
        .collection('employees')
        .where('active', isEqualTo: true)
        .get();

    final List<Map<String, dynamic>> employees = empSnap.docs.map((doc) {
      final d = doc.data();
      return {
        'idcardno': d['idcardno'] ?? '',
        'name': d['name'] ?? '',
        'email': d['email'] ?? '',
      };
    }).toList();

    // Step 2: For each employee, fetch leave balance + recent leaves
    final List<Map<String, dynamic>> result = await Future.wait(
      employees.map((emp) async {
        // Approved leaves → balance calculation
        final approvedSnap = await FirebaseFirestore.instance
            .collection('leaves')
            .where('IDCARDNO', isEqualTo: emp['idcardno'])
            .where('STATUS', isEqualTo: 'Approved')
            .get();

        double elTaken = 0, clTaken = 0, slTaken = 0;
        for (final doc in approvedSnap.docs) {
          final leave = doc.data();
          final leaveType = (leave['LEAVE_TYPE'] ?? '').toString().toLowerCase();
          final days = double.tryParse(leave['TOTAL_DAYS'].toString()) ?? 1.0;
          if (leaveType.contains('earned')) elTaken += days;
          else if (leaveType.contains('casual')) clTaken += days;
          else if (leaveType.contains('sick')) slTaken += days;
        }

        // All leaves → recent history
        final allLeavesSnap = await FirebaseFirestore.instance
            .collection('leaves')
            .where('IDCARDNO', isEqualTo: emp['idcardno'])
            .get();

        final List<Map<String, dynamic>> allLeaves = allLeavesSnap.docs.map((doc) {
          return {...doc.data(), 'LEAVE_ID': doc.id};
        }).toList();

        // Sort by CREATED_AT descending, take last 5
        allLeaves.sort((a, b) {
          DateTime dateA, dateB;
          try { dateA = (a['CREATED_AT'] as Timestamp).toDate(); }
          catch (_) { dateA = DateTime(0); }
          try { dateB = (b['CREATED_AT'] as Timestamp).toDate(); }
          catch (_) { dateB = DateTime(0); }
          return dateB.compareTo(dateA);
        });
        final recentLeaves = allLeaves.take(5).toList();

        return {
          ...emp,
          'cl_total': 12, 'cl_taken': clTaken.toInt(),
          'cl_balance': (12 - clTaken).clamp(0, 12).toInt(),
          'el_total': 12, 'el_taken': elTaken.toInt(),
          'el_balance': (12 - elTaken).clamp(0, 12).toInt(),
          'sl_total': 6,  'sl_taken': slTaken.toInt(),
          'sl_balance': (6  - slTaken).clamp(0, 6).toInt(),
          'recentLeaves': recentLeaves,
        };
      }),
    );

    setState(() {
      _employees = result;
      _filtered = result;
      _isLoading = false;
    });

  } on FirebaseException catch (e) {
    debugPrint("Firestore error: ${e.code} - ${e.message}");
    setState(() { _error = 'Database error: ${e.message}'; _isLoading = false; });
  } catch (e) {
    debugPrint("Unexpected error: $e");
    setState(() { _error = 'Connection error.'; _isLoading = false; });
  }
}

  void _showEmployeeDetail(Map<String, dynamic> emp) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              // Employee header
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.indigo.shade100,
                    child: Icon(Icons.person, size: 30, color: Colors.indigo.shade700),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(emp['name'] ?? 'Employee',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      Text(emp['idcardno'] ?? '',
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Leave balance cards
              Text('Leave Balance',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _balanceCard('Casual', emp['cl_balance'] ?? 0, emp['cl_total'] ?? 12, Colors.blue)),
                  const SizedBox(width: 8),
                  Expanded(child: _balanceCard('Earned', emp['el_balance'] ?? 0, emp['el_total'] ?? 12, Colors.green)),
                  const SizedBox(width: 8),
                  Expanded(child: _balanceCard('Sick', emp['sl_balance'] ?? 0, emp['sl_total'] ?? 6, Colors.orange)),
                ],
              ),
              const SizedBox(height: 20),

              // Recent leaves
              Text('Recent Leaves',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              ...(emp['recentLeaves'] as List<dynamic>? ?? []).map((leave) {
                final l = leave as Map<String, dynamic>;
                final status = l['STATUS'] ?? 'Pending';
                Color statusColor;
                switch (status.toLowerCase()) {
                  case 'approved': statusColor = Colors.green; break;
                  case 'rejected': statusColor = Colors.red; break;
                  default: statusColor = Colors.orange;
                }
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(Icons.event_note, color: statusColor),
                    title: Text(l['LEAVE_TYPE'] ?? '',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(
                        '${l['FROM_DATE'] ?? ''} → ${l['TO_DATE'] ?? ''} • ${l['TOTAL_DAYS'] ?? 1} day(s)',
                        style: GoogleFonts.poppins(fontSize: 11)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: statusColor.withValues(alpha: 0.4))),
                      child: Text(status,
                          style: GoogleFonts.poppins(
                              color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _balanceCard(String type, dynamic balance, dynamic total, Color color) {
    final bal = (balance is num) ? balance.toInt() : int.tryParse(balance.toString()) ?? 0;
    final tot = (total is num) ? total.toInt() : int.tryParse(total.toString()) ?? 0;
    final taken = tot - bal;
    final percent = tot > 0 ? bal / tot : 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Text(type,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text('$bal',
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text('of $tot',
                style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent.toDouble(),
                backgroundColor: color.withValues(alpha: 0.15),
                color: color,
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 4),
            Text('$taken taken',
                style: GoogleFonts.poppins(fontSize: 9, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text('Employee Monitor',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade800, Colors.teal.shade500],
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
              onPressed: _fetchEmployees),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off, size: 60, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(_error!, style: GoogleFonts.poppins(color: Colors.grey)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _fetchEmployees, child: const Text('Retry')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Search bar
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by name or ID...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        ),
                      ),
                    ),
                    // Summary
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text('${_filtered.length} employees',
                              style: GoogleFonts.poppins(
                                  color: Colors.grey.shade600, fontSize: 13)),
                          const Spacer(),
                          Text('Tap to view details',
                              style: GoogleFonts.poppins(
                                  color: Colors.blue, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // List
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _fetchEmployees,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final emp = _filtered[index];
                            final clBal = emp['cl_balance'] ?? 0;
                            final elBal = emp['el_balance'] ?? 0;
                            final slBal = emp['sl_balance'] ?? 0;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              child: InkWell(
                                onTap: () => _showEmployeeDetail(emp),
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Colors.indigo.shade50,
                                        child: Icon(Icons.person,
                                            color: Colors.indigo.shade600),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(emp['name'] ?? 'Employee',
                                                style: GoogleFonts.poppins(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14)),
                                            Text(emp['idcardno'] ?? '',
                                                style: GoogleFonts.poppins(
                                                    fontSize: 12,
                                                    color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                      // Leave balance summary chips
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Row(
                                            children: [
                                              _miniChip('CL', '$clBal', Colors.blue),
                                              const SizedBox(width: 4),
                                              _miniChip('EL', '$elBal', Colors.green),
                                              const SizedBox(width: 4),
                                              _miniChip('SL', '$slBal', Colors.orange),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text('days remaining',
                                              style: GoogleFonts.poppins(
                                                  fontSize: 9,
                                                  color: Colors.grey)),
                                        ],
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.chevron_right,
                                          color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _miniChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: GoogleFonts.poppins(fontSize: 8, color: color)),
        ],
      ),
    );
  }
}