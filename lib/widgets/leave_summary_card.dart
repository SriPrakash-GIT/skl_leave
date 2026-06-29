import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LeaveSummaryCard extends StatefulWidget {
  const LeaveSummaryCard({super.key});

  @override
  State<LeaveSummaryCard> createState() => _LeaveSummaryCardState();
}

class _LeaveSummaryCardState extends State<LeaveSummaryCard> {
  String? _employeeId;

  @override
  void initState() {
    super.initState();
    _loadEmployeeId();
  }

  Future<void> _loadEmployeeId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('employeeId');
    setState(() => _employeeId = id);
  }

  @override
  Widget build(BuildContext context) {
    if (_employeeId == null) {
      return _buildErrorCard('Please log in again');
    }

    // REAL-TIME LISTENER: This rebuilds whenever data changes
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('leaves')
          .where('IDCARDNO', isEqualTo: _employeeId!)
          .where('STATUS', isEqualTo: 'Approved')
          .snapshots(), // ← THIS MAKES IT REAL-TIME
      builder: (context, snapshot) {
        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingCard();
        }

        // Error
        if (snapshot.hasError) {
          return _buildErrorCard('Could not load leave summary');
        }

        // Calculate values
        int totalTaken = 0, lopDays = 0;

        for (final doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final days =
              (data['TOTAL_DAYS'] ?? data['days'] ?? 1) as dynamic;
          final numDays = (days is int)
              ? days
              : int.tryParse(days.toString()) ?? 1;
          final leaveType =
              (data['LEAVE_TYPE'] ?? data['leave_type'] ?? '')
                  .toString()
                  .toLowerCase();

          if (leaveType.contains('lop') || leaveType.contains('loss')) {
            lopDays += numDays;
          } else {
            totalTaken += numDays;
          }
        }

        int totalBalance = (12 - totalTaken).clamp(0, 999);

        // DISPLAY UPDATED VALUES
        return Card(
          elevation: 4,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statTile(
                  label: 'Taken',
                  value: totalTaken.toString(),
                  color: Colors.blue.shade700,
                  icon: Icons.event_busy,
                ),
                _divider(),
                _statTile(
                  label: 'Balance',
                  value: totalBalance.toString(),
                  color: Colors.green.shade700,
                  icon: Icons.event_available,
                ),
                _divider(),
                _statTile(
                  label: 'Loss of Pay',
                  value: lopDays.toString(),
                  color: lopDays > 0
                      ? Colors.red.shade600
                      : Colors.grey.shade500,
                  icon: Icons.money_off,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingCard() {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: const SizedBox(
        height: 72,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(height: 48, width: 1, color: Colors.grey.shade300);
  }

  Widget _statTile({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}