import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../login.dart';

class CustomDrawer extends StatelessWidget {
  final bool stkTransferCheck;
  final bool brhTransferCheck;

  const CustomDrawer({
    super.key,
    required this.stkTransferCheck,
    required this.brhTransferCheck,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          DrawerHeader(
            padding: EdgeInsets.zero,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade800, Colors.green.shade300],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Image.asset(
                'assets/icon/logo.jpeg',
                height: 80,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                _buildDrawerItem(
                  context,
                  condition: true,
                  icon: Icons.home,
                  title: 'Home',
                  route: '/home',
                ),
                _buildDrawerItem(
                  context,
                  condition: true,
                  icon: Icons.location_on_rounded,
                  title: 'Update Location',
                  route: '/newLocation',
                ),
              ],
            ),
          ),
          const Divider(thickness: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.logout),
              label: const Text("Logout", style: TextStyle(fontSize: 16)),
              onPressed: () async {
                await LoginPage.clearLoginData();
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                );
                Fluttertoast.showToast(
                  msg: "Logged out successfully!..",
                  toastLength: Toast.LENGTH_LONG,
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.redAccent,
                  textColor: Colors.white,
                  fontSize: 16.0,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context,
      {required bool condition,
      required IconData icon,
      required String title,
      required String route}) {
    if (!condition) return const SizedBox.shrink();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 25),
      leading: Icon(icon, color: Colors.blue.shade900),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          color: Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
      hoverColor: Colors.cyan.withOpacity(0.1),
      onTap: () {
        Navigator.pop(context);
        Navigator.pushNamed(context, route);
      },
    );
  }
}
