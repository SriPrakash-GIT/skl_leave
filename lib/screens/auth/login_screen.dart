import 'dart:convert';
import 'package:git_leave/utils/global_variables.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:git_leave/screens/home/home_screen.dart';
import 'package:git_leave/screens/auth/register_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:git_leave/services/notification_service.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  static Future<void> clearLoginData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('employeeId');
    await prefs.remove('password');
  }

  @override
  State<LoginPage> createState() => _LoginPageState();
}

String _adminPassword = '123456';
String _ipAddress = '';
String _port = '';
String _version = '';

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _showAdminPasswordDialog = false;

  final ipController = TextEditingController();
  final portController = TextEditingController();
  final versionController = TextEditingController();
  final serverPassWord = TextEditingController();
  final serverConPassWord = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
    _loadServerSettings();
  }

  // Load saved login credentials
  Future<void> _loadRememberedCredentials() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _emailController.text = prefs.getString('employeeId') ?? '';
      _passwordController.text = prefs.getString('password') ?? '';
    });
  }

  // Load saved server config
  Future<void> _loadServerSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipAddress = prefs.getString('server_ip') ?? ip;
      _port = prefs.getString('server_port') ?? port;
      _version = prefs.getString('server_version') ?? version;

      ipController.text = _ipAddress;
      portController.text = _port;
      versionController.text = _version;
      serverPassWord.text = _adminPassword;
      serverConPassWord.text = _adminPassword;

      if (_ipAddress.isNotEmpty && _port.isNotEmpty) {
        ipAddress = 'http://$_ipAddress:$_port';
        debugPrint("Loaded server IP: $ipAddress");
      }
    });
  }

  // Save server config locally
  Future<void> _saveServerSettings(String ip1, String port1, String version1,
      String newPwd, String conPwd) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', ip1);
    await prefs.setString('server_port', port1);
    await prefs.setString('server_version', version1);
    await prefs.setString('server_NewPwd', newPwd);
    await prefs.setString('server_comPwd', conPwd);

    setState(() {
      _ipAddress = ip1;
      _port = port1;
      _version = version1;
      ipAddress = 'http://$_ipAddress:$_port';
    });

    debugPrint("Server settings saved: $ipAddress");
  }

  Future<void> _login() async {
  if (_formKey.currentState!.validate()) {
    setState(() => _isLoading = true);
    try {
      await _fetchCheckPassword(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

Future<void> _fetchCheckPassword(String idcardno, String password) async {
  if (idcardno.isEmpty || password.isEmpty) {
    _showErrorDialog("Error", "Employee ID and password are required.");
    return;
  }

  try {
    final employeeSnap = await FirebaseFirestore.instance
        .collection('employees')
        .doc(idcardno)
        .get();

    if (!employeeSnap.exists) {
      _showErrorDialog("Login Failed", "Invalid Employee ID or Password.");
      return;
    }

    final employee = employeeSnap.data() as Map<String, dynamic>;
    final String storedPassword = employee['password'] ?? '';

    if (password != storedPassword) {
      _showErrorDialog("Login Failed", "Invalid Employee ID or Password.");
      return;
    }

    // ✅ Step 1 — always fetch fresh token first, wait for it
    await NotificationService.initFcmToken();
    debugPrint("fcmToken after init: $fcmToken");

    // ✅ Step 2 — save token to Firestore under 'fcmToken' field
    // (this is the field your server reads)
    await NotificationService.saveTokenForUser(idcardno);

    // ✅ Step 3 — update other device info separately
    await FirebaseFirestore.instance
        .collection('employees')
        .doc(idcardno)
        .update({
      'deviceId':    deviceId ?? '',
      'deviceType':  deviceType ?? '',
      'lastLogin':   FieldValue.serverTimestamp(),
      'mvr':         'V001',
     
    });

    globalIDcardNo = idcardno;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('employeeId', idcardno);
    await prefs.setString('password', password);

    debugPrint("Login Success: ${employee['name']}");

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
    }

  } on FirebaseException catch (e) {
    debugPrint("Firestore error: ${e.code} - ${e.message}");
    _showErrorDialog("Connection Error", "Database error: ${e.message}");
  } catch (e) {
    debugPrint("Unexpected error: $e");
    _showErrorDialog("Error", e.toString());
  }
}
  // Admin authentication
  Future<void> sendAuthPassword(String authPass) async {
    var md5Hash = md5.convert(utf8.encode(authPass)).toString();
    String url = "$ipAddress/api/adminLog/$md5Hash";
    debugPrint(url);

    try {
      final response = await http.get(Uri.parse(url));
      final Map<String, dynamic> data = json.decode(response.body);

      if (data["status"] == true) {
        setState(() {
          _showAdminPasswordDialog = false;
          _adminPasswordController.clear();
          _adminPassword = authPass;
        });
        _showServerSettingsDialog();
        _loadServerSettings();
      } else {
        _showErrorDialog("Admin Login Failed", data["message"]);
      }
    } catch (e) {
      if (_adminPasswordController.text == _adminPassword) {
        setState(() {
          _showAdminPasswordDialog = false;
          _adminPasswordController.clear();
        });
        _showServerSettingsDialog();
        _loadServerSettings();
      } else {
        Fluttertoast.showToast(
          msg: "Please Check the Network Connection",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.CENTER,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        _adminPasswordController.clear();
      }
    }
  }

  // Change admin password API
  Future<void> sendNewChangePassword(String newPass) async {
    var md5Hash = md5.convert(utf8.encode(newPass)).toString();
    String url = "$ipAddress/api/changeAdminPass/$md5Hash";
    try {
      final response = await http.get(Uri.parse(url));
      final Map<String, dynamic> data = json.decode(response.body);
      if (data["status"] == true) {
        setState(() => _adminPassword = newPass);
      }
    } catch (e) {
      debugPrint("Change password error: $e");
    }
  }

  void _showErrorDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() => setState(() => _showAdminPasswordDialog = true);

  void _onRegisterClicked() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterPage()));
  }

  // Server settings dialog (unchanged)
  void _showServerSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.transparent,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Server Configuration',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange)),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                        color: Colors.grey,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  TextFormField(
                    controller: ipController,
                    decoration: InputDecoration(
                      labelText: 'Server IP',
                      hintText: 'e.g.192.168.1.100',
                      prefixIcon:
                          const Icon(Icons.dns, color: Colors.deepOrange),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    keyboardType: TextInputType.url,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter server IP';
                      }
                      final ipRegex =
                          RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
                      if (!ipRegex.hasMatch(value)) {
                        return 'Enter valid IP address';
                      }
                      return null;
                    },
                    onChanged: (value) => _ipAddress = value.trim(),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: portController,
                    decoration: InputDecoration(
                      labelText: 'Port',
                      hintText: '8080',
                      prefixIcon:
                          const Icon(Icons.numbers, color: Colors.deepOrange),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter port number';
                      }
                      if (int.tryParse(value) == null) {
                        return 'Enter valid port number';
                      }
                      final port = int.parse(value);
                      if (port < 1 || port > 65535) {
                        return 'Port must be 1-65535';
                      }
                      return null;
                    },
                    onChanged: (value) => _port = value.trim(),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: versionController,
                    decoration: InputDecoration(
                      labelText: 'Version',
                      labelStyle: TextStyle(),
                      prefixIcon: Icon(Icons.code, color: Colors.deepOrange),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          width: 2,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: serverPassWord,
                    obscureText: _isPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: TextStyle(),
                      prefixIcon:
                          Icon(Icons.lock_outline, color: Colors.deepOrange),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          width: 2,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: serverConPassWord,
                    obscureText: _isPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      labelStyle: TextStyle(),
                      prefixIcon:
                          Icon(Icons.lock_outline, color: Colors.deepOrange),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.deepOrange,
                          width: 2,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('CANCEL')),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                        ),
                        onPressed: () {
                          if (ipController.text.isNotEmpty &&
                              portController.text.isNotEmpty &&
                              versionController.text.isNotEmpty &&
                              serverPassWord.text.isNotEmpty &&
                              serverConPassWord.text.isNotEmpty) {
                            sendNewChangePassword(serverConPassWord.text);
                            _saveServerSettings(
                                ipController.text,
                                portController.text,
                                versionController.text,
                                serverPassWord.text,
                                serverConPassWord.text);
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Server settings saved successfully!'),
                                  backgroundColor: Colors.green),
                            );
                          }
                        },
                        child: const Text('SAVE'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Define a modern primary palette (indigo + teal)
    final primaryColor = const Color(0xFF1E3A8A); // deep indigo
    final secondaryColor = const Color(0xFF0F766E); // rich teal

    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            child: SizedBox(
              height: size.height,
              child: Stack(
                children: [
                  Container(
                    height: size.height * 0.4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, secondaryColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 60),
                        Padding(
                          padding: const EdgeInsets.only(top: 20, bottom: 40),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome Back',
                                style: GoogleFonts.poppins(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Glad to see you again!',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.white
                                      .withAlpha((0.9 * 255).round()),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Card(
                          elevation: 8,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  Image.asset(
                                    'assets/icon/ris_logo.png',
                                    width: 180,
                                    height: 120,
                                  ),
                                  const SizedBox(height: 2),
                                  TextFormField(
                                    controller: _emailController,
                                    decoration: InputDecoration(
                                      labelText: 'Employee ID',
                                      labelStyle:
                                          TextStyle(color: primaryColor),
                                      prefixIcon: Icon(Icons.person_outline,
                                          color: primaryColor),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                            color: Colors.grey.shade300),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                            color: primaryColor, width: 2),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter your Employee ID';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: !_isPasswordVisible,
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      labelStyle:
                                          TextStyle(color: primaryColor),
                                      prefixIcon: Icon(Icons.lock_outline,
                                          color: primaryColor),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _isPasswordVisible
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                          color: Colors.grey.shade600,
                                        ),
                                        onPressed: () {
                                          setState(() => _isPasswordVisible =
                                              !_isPasswordVisible);
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                            color: Colors.grey.shade300),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                            color: primaryColor, width: 2),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter your password';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        debugPrint(
                                            "====== LOGIN BUTTON CLICKED ======");
                                        _login();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryColor,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        elevation: 0,
                                      ),
                                      child: _isLoading
                                          ? const CircularProgressIndicator(
                                              color: Colors.white)
                                          : Text('LOGIN',
                                              style: GoogleFonts.poppins(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white)),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pushNamed(
                                          context, '/adminLogin');
                                    },
                                    child: const Text('Admin Login →'),
                                  ),
                                  const SizedBox(height: 10),
                                  Center(
                                    child: TextButton(
                                      onPressed: _onRegisterClicked,
                                      child: RichText(
                                        text: TextSpan(
                                          text: "Don't have an account? ",
                                          style: GoogleFonts.poppins(
                                              color: Colors.grey.shade600),
                                          children: [
                                            TextSpan(
                                              text: 'Register',
                                              style: GoogleFonts.poppins(
                                                  color: secondaryColor,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
