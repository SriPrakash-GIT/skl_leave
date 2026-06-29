import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:git_leave/screens/auth/login_screen.dart';

class CustomDrawer extends StatefulWidget {
  final bool stkTransferCheck;
  final bool brhTransferCheck;
  final bool isAdmin;

  const CustomDrawer({
    super.key,
    required this.stkTransferCheck,
    required this.brhTransferCheck,
    this.isAdmin = false,
  });

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  String _empName = '';
  String _empId   = '';
  bool _loading   = true;

  // ── YOUR EXISTING LOGIC — UNTOUCHED ─────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadEmployeeInfo();
  }

  Future<void> _loadEmployeeInfo() async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final idcardno = prefs.getString('employeeId') ?? '';
      if (idcardno.isEmpty) {
        setState(() { _empId = ''; _empName = 'Unknown Employee'; _loading = false; });
        return;
      }
      final doc = await FirebaseFirestore.instance
          .collection('employees').doc(idcardno).get();
      setState(() {
        _empId   = idcardno;
        _empName = doc.exists ? (doc.data()?['name'] ?? idcardno) : idcardno;
        _loading = false;
      });
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _empId   = prefs.getString('employeeId') ?? '';
        _empName = _empId.isNotEmpty ? _empId : 'Employee';
        _loading = false;
      });
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
  // ────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                _buildDrawerItem(
                  context,
                  condition: true,
                  icon: Icons.home_rounded,
                  iconColor: Colors.grey.shade700,
                  iconBg: Colors.grey.shade100,
                  title: 'Home',
                  route: '/home',
                ),

                _sectionHeader('Leave Management'),

                _buildDrawerItem(
                  context,
                  condition: true,
                  icon: Icons.event_available_rounded,
                  iconColor: const Color(0xFF1E5FA8),
                  iconBg: const Color(0xFFE6F1FB),
                  title: 'Apply Leave',
                  route: '/applyLeave',
                ),

                _buildDrawerItem(
                  context,
                  condition: true,
                  icon: Icons.assignment_turned_in_rounded,
                  iconColor: const Color(0xFF3B6D11),
                  iconBg: const Color(0xFFEAF3DE),
                  title: 'My Leave Status',
                  route: '/leaveStatus',
                ),

                _buildDrawerItem(
                  context,
                  condition: widget.isAdmin,  // ← your existing condition
                  icon: Icons.admin_panel_settings_rounded,
                  iconColor: const Color(0xFF3C3489),
                  iconBg: const Color(0xFFEEEDFE),
                  title: 'Leave Requests',
                  subtitle: 'Admin Panel',
                  route: '/adminLeave',
                  badge: 'ADMIN',
                  badgeColor: const Color(0xFF3C3489),
                  badgeBg: const Color(0xFFEEEDFE),
                ),

                _sectionHeader('On Duty'),

                _buildDrawerItem(
                  context,
                  condition: true,
                  icon: Icons.work_history_rounded,
                  iconColor: const Color(0xFF0F6E56),
                  iconBg: const Color(0xFFE1F5EE),
                  title: 'On Duty Report',
                  subtitle: 'Track site visits',
                  route: '/onDuty',
                ),

                if (widget.isAdmin) ...[   // ← your existing condition
                  _sectionHeader('Admin Settings'),
                  _buildDrawerItem(
                    context,
                    condition: true,
                    icon: Icons.settings_rounded,
                    iconColor: const Color(0xFF3C3489),
                    iconBg: const Color(0xFFEEEDFE),
                    title: 'Admin Preferences',
                    subtitle: 'Notifications & permissions',
                    route: '/adminPreferences',
                    badge: 'SETTINGS',
                    badgeColor: const Color(0xFF085041),
                    badgeBg: const Color(0xFFE1F5EE),
                  ),
                ],
              ],
            ),
          ),

          _buildLogoutButton(context),  // ← your existing logout logic
        ],
      ),
    );
  }

  // ── HEADER ───────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      color: const Color(0xFF1A3A6E),
      padding: const EdgeInsets.fromLTRB(18, 48, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo row
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Image.asset(
                    'assets/icon/ris_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'GIT Leave App',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          Divider(color: Colors.white.withOpacity(0.2), height: 1),
          const SizedBox(height: 14),

          // Profile row
          Row(
            children: [
              // Avatar circle
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                      )
                    : Center(
                        child: Text(
                          _initials(_empName),  // ← your existing logic
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),

              // Name + ID
              Expanded(
                child: _loading
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _empName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.badge_outlined,
                                size: 11,
                                color: Colors.white.withOpacity(0.6)),
                              const SizedBox(width: 4),
                              Text(
                                _empId,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 11,
                                ),
                              ),
                              if (widget.isAdmin) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD97706),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text(
                                    'ADMIN',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── SECTION HEADER ───────────────────────────────────────────────────────
  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
      child: Text(
        title.toUpperCase(),  // ← your existing logic
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade400,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // ── DRAWER ITEM ──────────────────────────────────────────────────────────
  Widget _buildDrawerItem(
    BuildContext context, {
    required bool condition,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String route,
    String? subtitle,
    bool removeAll = false,
    String? badge,
    Color? badgeColor,
    Color? badgeBg,
  }) {
    if (!condition) return const SizedBox.shrink();  // ← your existing logic

    return InkWell(
      onTap: () {
        // ── YOUR EXISTING NAVIGATION LOGIC — UNTOUCHED ──────────────────
        Navigator.pop(context);
        if (removeAll) {
          Navigator.pushNamedAndRemoveUntil(
              context, route, (Route<dynamic> r) => false);
        } else {
          Navigator.pushNamed(context, route);
        }
        // ────────────────────────────────────────────────────────────────
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // Icon box
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),

              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeBg ?? Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 9,
                                color: badgeColor ?? Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Chevron
              Icon(Icons.chevron_right,
                color: Colors.grey.shade300, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── LOGOUT ───────────────────────────────────────────────────────────────
  Widget _buildLogoutButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade100, width: 1),
        ),
      ),
      child: GestureDetector(
        onTap: () async {
          // ── YOUR EXISTING LOGOUT LOGIC — UNTOUCHED ────────────────────
          await LoginPage.clearLoginData();
          Navigator.pop(context);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
          Fluttertoast.showToast(
            msg: "Logged out successfully!",
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.redAccent,
            textColor: Colors.white,
            fontSize: 16.0,
          );
          // ────────────────────────────────────────────────────────────
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFFCEBEB),
            border: Border.all(
              color: const Color(0xFFF09595), width: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded,
                color: Color(0xFFA32D2D), size: 18),
              SizedBox(width: 8),
              Text(
                'Logout',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFFA32D2D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}