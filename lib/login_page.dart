import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'main.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController(text: 'admin');
  final TextEditingController _passwordController = TextEditingController(text: '123456');
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUser = prefs.getString('LAST_USER') ?? '';
      final savedPass = prefs.getString('LAST_PASS') ?? '';
      if (savedUser.isNotEmpty || savedPass.isNotEmpty) {
        setState(() {
          _usernameController.text = savedUser;
          _passwordController.text = savedPass;
        });
      }
    } catch (e) {
      debugPrint('Error loading saved credentials: $e');
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/login'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "username": _usernameController.text.trim(),
          "password": _passwordController.text,
        }),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['success'] == true) {
          // Save credentials for next time
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('LAST_USER', _usernameController.text.trim());
            await prefs.setString('LAST_PASS', _passwordController.text);
            
            final userData = result['user'] ?? {};
            final dynamic rawWrCode = userData['wrCode'];
            final dynamic rawBrnCode = userData['brnCode'];
            
            // Robust parsing of int or string values
            final int wrCode = int.tryParse(rawWrCode?.toString() ?? '0') ?? 0;
            final int brnCode = int.tryParse(rawBrnCode?.toString() ?? '0') ?? 0;
            
            await prefs.setInt('LOGGED_WR_CODE', wrCode);
            await prefs.setInt('LOGGED_BRN_CODE', brnCode);
          } catch (e) {
            debugPrint('Error saving credentials: $e');
          }

          // Success! Navigate to dashboard
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const InvoiceDashboard()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Login failed. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        final errorMsg = json.decode(response.body)['error'] ?? 'Invalid username or password';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection failed. Verify server IP & port under Settings. Error: $e'),
          backgroundColor: Colors.red[800],
        ),
      );
    }
  }

  void _showConfigDialog() {
    final TextEditingController apiIpCtrl = TextEditingController(text: AppConfig.apiIp);
    final TextEditingController apiPortCtrl = TextEditingController(text: AppConfig.apiPort);
    final TextEditingController dbServerCtrl = TextEditingController(text: AppConfig.dbServer);
    final TextEditingController dbNameCtrl = TextEditingController(text: AppConfig.dbName);
    final TextEditingController dbPortCtrl = TextEditingController(text: AppConfig.dbPort);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '⚙️ PRODUCTION CONFIG',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E293B)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 12),
                const SizedBox(height: 12),
                
                const Text('API Server IP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B))),
                const SizedBox(height: 6),
                TextField(
                  controller: apiIpCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. 192.168.1.116',
                    prefixIcon: const Icon(Icons.router_rounded, size: 18),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFFAF9F6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),

                const Text('API Service Port', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B))),
                const SizedBox(height: 6),
                TextField(
                  controller: apiPortCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'e.g. 3005',
                    prefixIcon: const Icon(Icons.hub_rounded, size: 18),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFFAF9F6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),

                const Text('SQL Database Server IP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B))),
                const SizedBox(height: 6),
                TextField(
                  controller: dbServerCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. 192.168.1.250',
                    prefixIcon: const Icon(Icons.storage_rounded, size: 18),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFFAF9F6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),

                const Text('Database Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B))),
                const SizedBox(height: 6),
                TextField(
                  controller: dbNameCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. eazysoftdb',
                    prefixIcon: const Icon(Icons.folder_shared_rounded, size: 18),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFFAF9F6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),

                const Text('Database Port', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B))),
                const SizedBox(height: 6),
                TextField(
                  controller: dbPortCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'e.g. 1433',
                    prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFFAF9F6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    onPressed: () async {
                      await AppConfig.save(
                        ip: apiIpCtrl.text.trim(),
                        port: apiPortCtrl.text.trim(),
                        server: dbServerCtrl.text.trim(),
                        name: dbNameCtrl.text.trim(),
                        dPort: dbPortCtrl.text.trim(),
                      );
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Configuration saved successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Save Production Config', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Luxury Dark Theme Background
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top Settings Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings_suggest_rounded, color: Colors.white70, size: 28),
                          onPressed: _showConfigDialog,
                          tooltip: 'Server Configuration',
                        ),
                      ],
                    ),

                    // Logo & Brand Section
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5).withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.3), width: 2),
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            color: Color(0xFF6366F1),
                            size: 52,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'EazyMob',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Supplier Invoicing Terminal',
                          style: TextStyle(
                            color: const Color(0xFF94A3B8),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // Card Form Container
                    Form(
                      key: _formKey,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 25,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sign In',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Username Input
                            TextFormField(
                              controller: _usernameController,
                              style: const TextStyle(color: Color(0xFF1E293B)),
                              decoration: InputDecoration(
                                labelText: 'Username',
                                labelStyle: const TextStyle(color: Color(0xFF64748B)),
                                prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFF4F46E5)),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                              ),
                              validator: (val) => val == null || val.trim().isEmpty ? 'Please enter username' : null,
                            ),
                            const SizedBox(height: 16),

                            // Password Input
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              style: const TextStyle(color: Color(0xFF1E293B)),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                labelStyle: const TextStyle(color: Color(0xFF64748B)),
                                prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF4F46E5)),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    color: const Color(0xFF64748B),
                                  ),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                              ),
                              validator: (val) => val == null || val.isEmpty ? 'Please enter password' : null,
                            ),
                            const SizedBox(height: 24),

                            // Sign In Button
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4F46E5),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                      )
                                    : const Text(
                                        'Login To Terminal',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Version / Footer Section
                    Text(
                      'v1.0.0-production',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
