import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';          // ← fixes FirebaseFirestore & FirebaseException
import 'package:git_leave/utils/global_variables.dart';
import 'package:git_leave/screens/admin/admin_dashboard_screen.dart'; // ← keep your existing import

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  // ── fixed: added _showErrorDialog (was missing, _showError was there instead)
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _adminLogin() async {                           // ← fixed: no params, reads from controllers
    if (!_formKey.currentState!.validate()) return;

    final String idcardno  = _idController.text.trim();
    final String password  = _passwordController.text.trim();

    setState(() => _isLoading = true);

    try {
      // Step 1: Fetch employee doc from Firestore
      final employeeSnap = await FirebaseFirestore.instance
          .collection('employees')
          .doc(idcardno)
          .get();

      // Step 2: Check exists
      if (!employeeSnap.exists) {
        _showErrorDialog("Login Failed", "Invalid Admin ID or Password.");
        return;
      }

      final employee = employeeSnap.data() as Map<String, dynamic>;

      // Step 3: Verify password
      final String storedPassword = employee['password'] ?? '';
      if (password != storedPassword) {
        _showErrorDialog("Login Failed", "Invalid Admin ID or Password.");
        return;
      }

      // Step 4: Check isAdmin flag
      final bool isAdmin = employee['isAdmin'] ?? false;
      if (!isAdmin) {
        _showErrorDialog("Access Denied", "Not an admin account.");
        return;
      }

      // Step 5: Store globally
      globalIDcardNo = idcardno;

      // Step 6: Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('adminId', idcardno);
      await prefs.setString('adminPassword', password);
      await prefs.setBool('isAdmin', true);

      debugPrint("Admin Login Success: ${employee['name']}");

      // Step 7: Navigate — uses AdminDashboardScreen from your existing import
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => AdminDashboardPage()),
        );
      }

    } on FirebaseException catch (e) {
      debugPrint("Firestore error: ${e.code} - ${e.message}");
      _showErrorDialog("Connection Error", "Database error: ${e.message}");
    } catch (e) {
      debugPrint("Unexpected error: $e");
      _showErrorDialog("Error", e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.indigo.shade900, Colors.purple.shade700],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.admin_panel_settings,
                        size: 60, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Admin Portal',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Sign in to manage employees',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.8)),
                  ),
                  const SizedBox(height: 40),
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _idController,
                              decoration: InputDecoration(
                                labelText: 'Admin ID',
                                prefixIcon: const Icon(Icons.badge_outlined,
                                    color: Colors.indigo),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                      color: Colors.indigo.shade700, width: 2),
                                ),
                              ),
                              validator: (v) =>
                                  v!.isEmpty ? 'Enter Admin ID' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline,
                                    color: Colors.indigo),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                      color: Colors.indigo.shade700, width: 2),
                                ),
                              ),
                              validator: (v) =>
                                  v!.isEmpty ? 'Enter password' : null,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _adminLogin, // ← fixed: no args needed
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo.shade800,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        color: Colors.white)
                                    : Text(
                                        'SIGN IN',
                                        style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      '← Back to Employee Login',
                      style: GoogleFonts.poppins(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}