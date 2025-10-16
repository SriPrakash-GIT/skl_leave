import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:skl_leave/register.dart';
import 'globalVariable.dart';
import 'home.dart';
import 'main.dart';
import 'notificationtoken.dart';

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

String globalIDcardNo = "";
String _adminPassword = '123456';
String _ipAddress = '';
String _port = '';
String _version = '';
String _NewPwd = '';
String _comPwd = '';

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _rememberMe = true;
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
      _NewPwd = prefs.getString('server_NewPwd') ?? '';
      _comPwd = prefs.getString('server_comPwd') ?? '';

      // Populate controllers
      ipController.text = _ipAddress;
      portController.text = _port;
      versionController.text = _version;
      serverPassWord.text = _adminPassword;
      serverConPassWord.text = _adminPassword;

      if (_ipAddress.isNotEmpty && _port.isNotEmpty && _version.isNotEmpty) {
        ipAddress = 'http://$_ipAddress:$_port/$_version';
        print("Loaded server IP: $ipAddress");
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
      _NewPwd = newPwd;
      _comPwd = conPwd;
      ipAddress = 'http://$_ipAddress:$_port/$_version';
    });

    print("Server settings saved: $ipAddress");
  }

  // Login API call
  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        var bytes = utf8.encode(_passwordController.text);
        var digest = md5.convert(bytes);
        globalIDcardNo = _emailController.text;

        await fetchCheckPassword(
            _emailController.text, digest.toString(), deviceId!, fcmToken!);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  // Fetch login API
  Future<void> fetchCheckPassword(String userid, String hashedPassword,
      String deviceId, String fcmToken) async {
    String url = "$ipAddress/api/LoginData";
    print(url);
    try {
      final response = await http.post(Uri.parse(url),
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: jsonEncode({
            "idcardno": userid,
            "deviceId": deviceId,
            "password": hashedPassword,
            "deviceToken": fcmToken,
            "mvr": "V001"
          }));

      final Map<String, dynamic> data = json.decode(response.body);

      if (data["status"] == true) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('employeeId', _emailController.text);
        await prefs.setString('password', _passwordController.text);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );
      } else {
        _showErrorDialog("Login Failed", data["message"]);
      }
    } catch (e) {
      _showErrorDialog("Connection Error", "Please ReOpen this Page");
      print(e);
    }
  }

  // Admin authentication
  Future<void> sendAuthPassword(String authPass) async {
    var md5Hash = md5.convert(utf8.encode(authPass)).toString();
    String url = "$ipAddress/api/adminLog/$md5Hash";
    print(url);

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
      // fallback: allow default password
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
    } catch (e) {}
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

  // Server settings dialog
  void _showServerSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        // controllers already have latest values from _loadServerSettings()
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
    final theme = Theme.of(context);
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
                        colors: [
                          theme.primaryColor.withOpacity(0.8),
                          theme.primaryColor,
                        ],
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
                        Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: Icon(Icons.settings, color: Colors.white),
                            onPressed: _showSettingsDialog,
                          ),
                        ),
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
                                  color: Colors.white.withOpacity(0.9),
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
                                    'assets/icon/logo.jpeg',
                                    width: 180,
                                    height: 120,
                                  ),
                                  const SizedBox(height: 2),
                                  TextFormField(
                                    controller: _emailController,
                                    decoration: InputDecoration(
                                      labelText: 'Employee ID',
                                      labelStyle:
                                          TextStyle(color: theme.primaryColor),
                                      prefixIcon: Icon(Icons.person_outline,
                                          color: theme.primaryColor),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                            color: Colors.grey.shade300),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                            color: theme.primaryColor,
                                            width: 2),
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
                                          TextStyle(color: theme.primaryColor),
                                      prefixIcon: Icon(Icons.lock_outline,
                                          color: theme.primaryColor),
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
                                            color: theme.primaryColor,
                                            width: 2),
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
                                      onPressed: _login,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: theme.primaryColor,
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
                                                  color: Colors.pink.shade600,
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
          if (_showAdminPasswordDialog)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Admin Authentication',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: _adminPasswordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Admin Password',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock),
                          ),
                        ),
                        SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () {
                                  setState(
                                      () => _showAdminPasswordDialog = false);
                                  _adminPasswordController.clear();
                                },
                                child: Text('CANCEL'),
                              ),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepOrange,
                                ),
                                onPressed: () {
                                  sendAuthPassword(
                                      _adminPasswordController.text.toString());
                                },
                                child: Text('VERIFY'),
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
        ],
      ),
    );
  }
}
