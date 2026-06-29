import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:git_leave/utils/global_variables.dart';


  class RegisterPage extends StatefulWidget {
    const RegisterPage({super.key});

    @override
    State<RegisterPage> createState() => _RegisterPageState();
  }

  class _RegisterPageState extends State<RegisterPage> {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController _passwordController = TextEditingController();

    String userId = '';
    String empName = '';
    String dob = '';
    String doj = '';
    String password = '';
    String confirmPassword = '';

    bool _obscurePassword = true;
    bool _obscureConfirmPassword = true;
    bool _isLoading = false;

    // ── Date picker ──────────────────────────────────────────────────────────────
    Future<void> _selectDate(BuildContext context, bool isDob) async {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Colors.teal,
                onPrimary: Colors.white,
                onSurface: Colors.teal,
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(foregroundColor: Colors.teal),
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked != null) {
        setState(() {
          final formatted =
              "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
          if (isDob) {
            dob = formatted;
          } else {
            doj = formatted;
          }
        });
      }
    }

    // ── API call ─────────────────────────────────────────────────────────────────
   // Replace only the _sendRegisterRequest method in register_screen.dart

Future<void> _sendRegisterRequest() async {
  if (dob.isEmpty || doj.isEmpty) {
    _showSnackBar(
      dob.isEmpty
          ? 'Please select Date of Birth'
          : 'Please select Date of Joining',
      isError: true,
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    // Step 1: Validate employee exists in master list
    final masterSnap = await FirebaseFirestore.instance
        .collection('Emp_Details')
        .doc(userId)
        .get();

    if (!masterSnap.exists) {
      _showSnackBar('Employee ID is not valid', isError: true);
      return;
    }

    // Step 2: Check for duplicate registration
    final employeeSnap = await FirebaseFirestore.instance
        .collection('employees')
        .doc(userId)
        .get();

    if (employeeSnap.exists) {
      _showSnackBar('Employee ID already registered', isError: true);
      return;
    }

    // Step 3: Save new employee record
    await FirebaseFirestore.instance
        .collection('employees')
        .doc(userId)
        .set({
      'idcardno': userId,
      'name': empName,
      'password': password,       // plain text, matching login check
      'deviceId': deviceId ?? '',
      'deviceType': deviceType,
      'dob': dob,
      'doj': doj,
      'email': '',
      'phone': '',
      'unitname': '',
      'type': deviceType,
      'mobno': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'active': true,
    });

    if (!mounted) return;
    _showSnackBar('Registration successful. Please login.', isError: false);
    Navigator.pop(context);

  } on FirebaseException catch (e) {
    debugPrint("Firestore error: ${e.code} - ${e.message}");
    _showErrorDialog("Connection Error", "Database error: ${e.message}");
  } catch (e) {
    debugPrint("Unexpected error: $e");
    _showErrorDialog("Connection Error",
        "Could not reach the server. Please check your connection and try again.");
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

    // ── Helpers ──────────────────────────────────────────────────────────────────
    void _showSnackBar(String message, {required bool isError}) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: isError ? Colors.red[700] : Colors.teal[700],
        ),
      );
    }

    void _showErrorDialog(String title, String content) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }

    // ── Build ────────────────────────────────────────────────────────────────────
    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: Colors.blue.shade50,
        appBar: AppBar(
          title: const Text(
            "Employee Registration",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          centerTitle: true,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade800, Colors.green.shade300],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: SingleChildScrollView(
              child: Card(
                color: Colors.white,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                shadowColor: Colors.teal.withValues(alpha: 0.2),
                child: Container(
                  width: MediaQuery.of(context).size.width > 500 ? 500 : null,
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Header ────────────────────────────────────────────
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.teal[50],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.person_add_alt_1,
                                size: 32, color: Colors.teal[700]),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            'Create Account',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal[800],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Fields ────────────────────────────────────────────
                        _buildTextField(
                          label: 'Employee ID',
                          icon: Icons.badge_outlined,
                          onSaved: (v) => userId = v!.trim(),
                          validator: (v) => v!.trim().isEmpty
                              ? 'Please enter Employee ID'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          label: 'Employee Name',
                          icon: Icons.person_outline,
                          onSaved: (v) => empName = v!.trim(),
                          validator: (v) => v!.trim().isEmpty
                              ? 'Please enter your name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _buildDateField(
                          label: 'Date of Birth',
                          icon: Icons.cake_outlined,
                          date: dob,
                          onTap: () => _selectDate(context, true),
                        ),
                        const SizedBox(height: 12),
                        _buildDateField(
                          label: 'Date of Joining',
                          icon: Icons.work_outline,
                          date: doj,
                          onTap: () => _selectDate(context, false),
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _passwordController,
                          label: 'Password',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePassword,
                          suffixIcon: _visibilityButton(
                            obscure: _obscurePassword,
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                          onSaved: (v) => password = v!,
                          validator: (v) => v!.length < 6
                              ? 'Password must be at least 6 characters'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          label: 'Confirm Password',
                          icon: Icons.lock_outline,
                          obscureText: _obscureConfirmPassword,
                          suffixIcon: _visibilityButton(
                            obscure: _obscureConfirmPassword,
                            onPressed: () => setState(() =>
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword),
                          ),
                          onSaved: (v) => confirmPassword = v!,
                          validator: (v) {
                            if (v!.isEmpty) return 'Please confirm your password';
                            if (v != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        // ── Submit ────────────────────────────────────────────
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.teal[700],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 3,
                            shadowColor: Colors.teal.withValues(alpha: 0.3),
                          ),
                          onPressed: _isLoading
                              ? null
                              : () {
                                  if (_formKey.currentState!.validate()) {
                                    _formKey.currentState!.save();
                                    _sendRegisterRequest();
                                  }
                                },
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'REGISTER',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("Already have an account?"),
                            const SizedBox(width: 10),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text(
                                'Login',
                                style: TextStyle(color: Color(0xFFDE3163)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ── Reusable widgets ─────────────────────────────────────────────────────────
    Widget _buildTextField({
      required String label,
      required IconData icon,
      TextEditingController? controller,
      bool obscureText = false,
      Widget? suffixIcon,
      required FormFieldSetter<String> onSaved,
      required FormFieldValidator<String> validator,
    }) {
      return TextFormField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.teal[800]),
          prefixIcon: Icon(icon, color: Colors.teal[600]),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.teal[200]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.teal[400]!, width: 1.5),
          ),
          filled: true,
          fillColor: Colors.teal[50]!.withValues(alpha: 0.3),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
        style: TextStyle(color: Colors.teal[900]),
        validator: validator,
        onSaved: onSaved,
      );
    }

    Widget _buildDateField({
      required String label,
      required IconData icon,
      required String date,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: Colors.teal[800]),
            prefixIcon: Icon(icon, color: Colors.teal[600]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.teal[200]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.teal[400]!, width: 1.5),
            ),
            filled: true,
            fillColor: Colors.teal[50]!.withValues(alpha: 0.3),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                date.isEmpty ? 'Select $label' : date,
                style: TextStyle(
                  color: date.isEmpty ? Colors.grey[600] : Colors.teal[900],
                ),
              ),
              Icon(Icons.arrow_drop_down, color: Colors.teal[600]),
            ],
          ),
        ),
      );
    }

    IconButton _visibilityButton(
            {required bool obscure, required VoidCallback onPressed}) =>
        IconButton(
          icon: Icon(
            obscure ? Icons.visibility : Icons.visibility_off,
            color: Colors.grey,
          ),
          onPressed: onPressed,
        );

    @override
    void dispose() {
      _passwordController.dispose();
      super.dispose();
    }
  }