import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:git_leave/screens/admin/admin_leave_screen.dart';
import 'package:git_leave/screens/admin/admin_employee_monitor.dart';
import 'package:git_leave/screens/admin/admin_preferences_screen.dart';
import 'package:git_leave/screens/admin/admin_onduty_screen.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  String adminName = '';
  String adminId = '';
  int pendingLeaves = 0;
  int totalEmployees = 0;
  int approvedToday = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAdminInfo();
    _fetchStats();
  }

  Future<void> _loadAdminInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      adminName = prefs.getString('adminName') ?? 'Admin';
      adminId   = prefs.getString('adminId')   ?? '';
    });
  }

  Future<void> _fetchStats() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final db = FirebaseFirestore.instance;

      // Run all three queries in parallel — same as Promise.all() in the API
      final results = await Future.wait([
        db.collection('leaves')
            .where('STATUS', isEqualTo: 'Pending')
            .get(),
        db.collection('employees')
            .where('active', isEqualTo: true)
            .get(),
        db.collection('leaves')
            .where('STATUS', isEqualTo: 'Approved')
            .get(),
      ]);

      final pendingSnap  = results[0];
      final empSnap      = results[1];
      final approvedSnap = results[2];

      // approvedToday: count docs whose UPDATED_AT >= today 00:00:00
      final todayMidnight = DateTime.now()
          .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);

      int todayCount = 0;
      for (final doc in approvedSnap.docs) {
        final raw = doc.data()['UPDATED_AT'];
        DateTime? updatedAt;
        if (raw is Timestamp) {
          updatedAt = raw.toDate();
        } else if (raw is DateTime) {
          updatedAt = raw;
        }
        if (updatedAt != null && !updatedAt.isBefore(todayMidnight)) {
          todayCount++;
        }
      }

      if (mounted) {
        setState(() {
          pendingLeaves  = pendingSnap.size;
          totalEmployees = empSnap.size;
          approvedToday  = todayCount;
        });
      }
    } on FirebaseException catch (e) {
      debugPrint('Firestore stats error: ${e.code} - ${e.message}');
    } catch (e) {
      debugPrint('Stats error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('adminId');
    await prefs.remove('adminName');
    await prefs.remove('isAdmin');
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/');
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admin Dashboard',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            Text(adminName,
                style:
                    GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
          ],
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.indigo.shade900, Colors.purple.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchStats,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Welcome card ──────────────────────────────────────────────
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.indigo.shade700,
                        Colors.purple.shade500,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.admin_panel_settings,
                          color: Colors.white, size: 40),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Welcome back,',
                              style: GoogleFonts.poppins(
                                  color: Colors.white70, fontSize: 13)),
                          Text(adminName,
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          Text('ID: $adminId',
                              style: GoogleFonts.poppins(
                                  color: Colors.white60, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Stats row ─────────────────────────────────────────────────
              Text('Overview',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.grey.shade700)),
              const SizedBox(height: 10),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      children: [
                        Expanded(
                          child: _statCard('Pending\nLeaves',
                              '$pendingLeaves', Icons.pending_actions,
                              Colors.orange),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statCard('Total\nEmployees',
                              '$totalEmployees', Icons.people, Colors.blue),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statCard('Approved\nToday',
                              '$approvedToday', Icons.check_circle,
                              Colors.green),
                        ),
                      ],
                    ),
              const SizedBox(height: 24),

              // ── Quick Actions ─────────────────────────────────────────────
              Text('Quick Actions',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.grey.shade700)),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _actionCard(
                    icon: Icons.assignment_turned_in,
                    label: 'Leave Requests',
                    subtitle: '$pendingLeaves pending',
                    color: Colors.orange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminLeavePage()),
                    ).then((_) => _fetchStats()),
                  ),
                  _actionCard(
                    icon: Icons.people_alt,
                    label: 'Employee Monitor',
                    subtitle: 'Leave balance & history',
                    color: Colors.blue,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminEmployeeMonitorPage()),
                    ),
                  ),
                  _actionCard(
                    icon: Icons.settings,
                    label: 'Preferences',
                    subtitle: 'Admin settings',
                    color: Colors.purple,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              AdminPreferencesPage(adminId: adminId)),
                    ),
                  ),
                  _actionCard(
                    icon: Icons.directions_car,
                    label: 'On Duty',
                    subtitle: 'Live & history',
                    color: Colors.teal,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminOnDutyPage()),
                    )
                    .then((_) => _fetchStats()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ──────────────────────────────────────────────────────────────────

  Widget _statCard(
      String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 10, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

 Widget _actionCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // was 16
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 26),              // was 30
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,             // prevent wrap
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, fontSize: 12)),  // was 13
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,             // prevent wrap
                  style: GoogleFonts.poppins(
                      fontSize: 9, color: Colors.grey.shade500)),   // was 10
            ],
          ),
        ),
      ),
    );
  }
}