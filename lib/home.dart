import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'custom/appBar.dart';
import 'custom/sideBar.dart';
import 'distance_display_widget.dart';
import 'globalVariable.dart';
import 'login.dart';

class HomeScreen extends StatefulWidget {
  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<HomeScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  Future<void> _requestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (Platform.isAndroid && permission != LocationPermission.always) {
      // Request "always" permission
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.always) {
      // Permission granted – you can now start monitoring
    } else {
      // Show dialog explaining why background location is needed
    }
  }

  @override
  void initState() {
    super.initState();
    _loadWebView();
  }

  void _loadWebView() {
    final url = '$ipAddress/$globalIDcardNo';
    print(url);
    print("web url");

    // final url="https://google.com";
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            print("Error: ${error.description}");
            print("Error code: ${error.errorCode}");
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
            // _showErrorDialog();
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
  }

  void _showErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: const Text('Could not load the webpage.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // _requestPermissions(); // Request permissions (if needed)
    return Scaffold(
      appBar: CustomAppBar(
        onMenuPressed: () {},
        barTitle: "S.K.L EXPORTS",
      ),
      drawer: const CustomDrawer(
        stkTransferCheck: false,
        brhTransferCheck: false,
      ),
      body: Column(
        children: [
          // const DistanceDisplayWidget(),


          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
                if (_hasError)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Failed to load page',
                          style: TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _hasError = false;
                              _isLoading = true;
                            });
                            _controller.reload();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
