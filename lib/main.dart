import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'history_page.dart';
import 'config.dart';
import 'login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  runApp(const SupplierInvoiceApp());
}

class SupplierInvoiceApp extends StatelessWidget {
  const SupplierInvoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EazyMob',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5), // EasyERP Indigo
          surface: const Color(0xFFFAFAFA),
          onSurface: const Color(0xFF18181B),
          primary: const Color(0xFF4F46E5),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE4E4E7), width: 1),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

class InvoiceDashboard extends StatefulWidget {
  const InvoiceDashboard({super.key});

  @override
  State<InvoiceDashboard> createState() => _InvoiceDashboardState();
}

class _InvoiceDashboardState extends State<InvoiceDashboard> {
  int _activeTab = 0; // 0 for Header, 1 for Items, 2 for Settings
  
  final TextEditingController _invoiceNoController = TextEditingController();
  String? _lastSavedInvoiceNo;
  final TextEditingController _supplierController = TextEditingController();
  final TextEditingController _itemSearchController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  List<dynamic> _searchResults = [];
  List<dynamic> _supplierResults = [];
  Map<String, dynamic>? _selectedSupplier;
  final List<InvoiceItem> _items = [];
  
  // Settings state
  bool _priceIncludeVat = false;
  String _selectedPrinterWidth = '58mm';
  bool _saveNClear = true;

  // Cache variables
  List<dynamic> _cachedSuppliers = [];
  List<dynamic> _cachedItems = [];
  bool _isCacheLoaded = false;
  
  // Scanning state
  bool _isScanningMode = false;
  bool _isProcessingScan = false;
  final MobileScannerController _scannerController = MobileScannerController();
  
  // Voice search state
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  
  String get baseUrl => AppConfig.baseUrl; // Dynamic EasyERP Backend URL from settings

  @override
  void initState() {
    super.initState();
    _loadCache();
    _initSpeech();
  }

  void _initSpeech() async {
    try {
      await _speechToText.initialize(
        onStatus: (status) => debugPrint('Speech Status: $status'),
        onError: (error) => debugPrint('Speech Error: $error'),
      );
    } catch (e) {
      debugPrint('Speech Init Error: $e');
    }
    setState(() {});
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _invoiceNoController.dispose();
    _supplierController.dispose();
    _itemSearchController.dispose();
    super.dispose();
  }

  void _clearScreen() {
    setState(() {
      _items.clear();
      _invoiceNoController.clear();
      _selectedSupplier = null;
      _activeTab = 0;
      _priceIncludeVat = false;
      _lastSavedInvoiceNo = null;
      _loadCache();
    });
  }

  Future<void> _handlePrintAction(double gross, double vat, double net) async {
    if (_lastSavedInvoiceNo == null) {
      // Scenario A: Not saved yet -> Save first, then print, then clear screen!
      final String? savedInvoiceNo = await _saveInvoice(gross, vat, net, showPreview: false);
      if (savedInvoiceNo != null) {
        await _triggerNativePrint(gross, vat, net, savedInvoiceNo: savedInvoiceNo);
        if (_saveNClear) {
          _clearScreen();
        }
      }
    } else {
      // Scenario B: Already saved -> Print and then clear screen!
      await _triggerNativePrint(gross, vat, net, savedInvoiceNo: _lastSavedInvoiceNo);
      if (_saveNClear) {
        _clearScreen();
      }
    }
  }

  Future<void> _loadCache() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch suppliers
      final supplierResponse = await http.get(Uri.parse('$baseUrl/api/suppliers/search?q='));
      if (supplierResponse.statusCode == 200) {
        _cachedSuppliers = json.decode(supplierResponse.body);
      }
      
      // 2. Fetch all items (from our new /api/items/all endpoint)
      final itemResponse = await http.get(Uri.parse('$baseUrl/api/items/all'));
      if (itemResponse.statusCode == 200) {
        _cachedItems = json.decode(itemResponse.body);
      }

      // 3. Fetch default supplier
      final defaultSupplierResponse = await http.get(Uri.parse('$baseUrl/api/suppliers/default'));
      if (defaultSupplierResponse.statusCode == 200) {
        final defaultSupplier = json.decode(defaultSupplierResponse.body);
        setState(() {
          _selectedSupplier = defaultSupplier;
          _supplierController.text = defaultSupplier['ACC_NAME'] ?? '';
        });
      }

      // 4. Fetch default settings (Price Include VAT)
      final defaultSettingsResponse = await http.get(Uri.parse('$baseUrl/api/settings/default'));
      if (defaultSettingsResponse.statusCode == 200) {
        final defaultSettings = json.decode(defaultSettingsResponse.body);
        setState(() {
          _priceIncludeVat = (defaultSettings['PRICE_INCLUDE_VAT'] == 1 || defaultSettings['PRICE_INCLUDE_VAT'] == true);
        });
      }
      
      setState(() {
        _isCacheLoaded = true;
      });
    } catch (e) {
      debugPrint('Error loading cache: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load data: $e'),
            backgroundColor: Colors.red[800],
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: _loadCache,
            ),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadInvoiceIntoEditor(Map<String, dynamic> invoice) async {
    setState(() => _isLoading = true);
    try {
      final String invoiceNo = invoice['INVOICE_NO']?.toString() ?? '';
      final response = await http.get(Uri.parse('$baseUrl/api/sales/history/$invoiceNo'));
      if (response.statusCode == 200) {
        final List<dynamic> itemsData = json.decode(response.body);
        
        setState(() {
          _items.clear();
          
          // 1. Set default supplier (by finding in cash suppliers or inserting)
          final String accNo = invoice['ACCODE']?.toString() ?? '';
          final String accName = invoice['ENAME'] ?? 'Unknown';
          
          final matchedSupplier = _cachedSuppliers.firstWhere(
            (sup) => sup['ACC_NO']?.toString() == accNo,
            orElse: () => null,
          );
          
          if (matchedSupplier != null) {
            _selectedSupplier = matchedSupplier;
            _supplierController.text = matchedSupplier['ACC_NAME'] ?? '';
          } else {
            _selectedSupplier = {'ACC_NO': accNo, 'ACC_NAME': accName};
            _supplierController.text = accName;
          }
          
          // 2. Set Reference Invoice number
          _invoiceNoController.text = invoice['REF_NO']?.toString() ?? '';
          
          // 3. Load items
          for (var item in itemsData) {
            final double rawQty = double.tryParse(item['QTY']?.toString() ?? '1.0') ?? 1.0;
            _items.add(InvoiceItem(
              code: item['BARCODE']?.toString() ?? '',
              description: item['DESCRIPTION'] ?? 'N/A',
              qty: rawQty.round(),
              price: double.tryParse(item['price']?.toString() ?? '0.0') ?? 0.0,
              vatPercent: double.tryParse(item['vat_percent']?.toString() ?? '15.0') ?? 15.0,
            ));
          }
          
          // 4. Switch to active tab 1 (Items) so they see the loaded items!
          _activeTab = 1;
          _lastSavedInvoiceNo = invoiceNo;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invoice #$invoiceNo loaded into entry screen!'),
            backgroundColor: const Color(0xFF4F46E5),
          ),
        );
      } else {
        throw Exception('Failed to load invoice items: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error loading invoice into editor: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load invoice items: $e'),
          backgroundColor: Colors.red[800],
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _searchItems(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = _cachedItems.take(20).toList());
      return;
    }
    debugPrint('Searching for: $query | Cached Items: ${_cachedItems.length}');
    final lowercaseQuery = query.toLowerCase();
    setState(() {
      _searchResults = _cachedItems.where((item) {
        final barcode = (item['BARCODE'] ?? '').toString().toLowerCase();
        final desc = (item['DESCRIPTION'] ?? '').toString().toLowerCase();
        return barcode.contains(lowercaseQuery) || desc.contains(lowercaseQuery);
      }).take(50).toList();
    });
  }

  void _startVoiceSearch() async {
    if (!_isListening) {
      try {
        // 1. Request microphone permission
        var status = await Permission.microphone.status;
        if (!status.isGranted) {
          status = await Permission.microphone.request();
          if (!status.isGranted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Microphone permission is required for voice search'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        }

        // 2. Try initializing the speech-to-text engine
        bool available = await _speechToText.initialize(
          onStatus: (status) => debugPrint('Voice Status: $status'),
          onError: (error) {
            debugPrint('Voice Error: $error');
            if (mounted) {
              setState(() => _isListening = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Voice Engine Error: ${error.errorMsg}. On Sunmi devices, please install "Google Speech Services".'),
                  backgroundColor: Colors.orange[800],
                  duration: const Duration(seconds: 8),
                ),
              );
            }
          },
        );

        if (available) {
          setState(() => _isListening = true);
          _speechToText.listen(
            listenFor: const Duration(seconds: 10),
            pauseFor: const Duration(seconds: 5),
            onResult: (result) {
              final words = result.recognizedWords;
              debugPrint('DART: Recognized words: "$words" | Final: ${result.finalResult}');
              
              Future.microtask(() {
                if (mounted) {
                  setState(() {
                    _itemSearchController.text = words;
                    _isListening = !result.finalResult;
                  });
                  _searchItems(words);
                  
                  if (result.finalResult) {
                    _handleVoiceResult(words);
                  }
                }
              });
            },
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Speech recognition is not available or disabled on this device.\n'
                'Please install "Speech Services by Google" from the Play Store on your Sunmi device.',
              ),
              backgroundColor: Colors.orange[800],
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: 'DISMISS',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('Voice Search Exception: $e');
        final String errorStr = e.toString();
        if (errorStr.contains('recognizerNotAvailable') || errorStr.contains('not available')) {
          _showSpeechEngineMissingDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Voice Search failed: $e'),
              backgroundColor: Colors.red[800],
            ),
          );
        }
      }
    } else {
      setState(() => _isListening = false);
      _speechToText.stop();
    }
  }

  void _handleVoiceResult(String words) async {
    await _searchItems(words);
    if (_searchResults.isNotEmpty) {
      // Check if any result is an exact match for barcode or description
      final exactMatch = _searchResults.firstWhere(
        (item) => (item['BARCODE'] ?? '').toString().toLowerCase() == words.toLowerCase() ||
                  (item['DESCRIPTION'] ?? '').toString().toLowerCase() == words.toLowerCase(),
        orElse: () => null,
      );

      if (exactMatch != null) {
        final barcode = exactMatch['BARCODE']?.toString();
        setState(() => _searchResults = []);
        if (barcode != null) {
          _showItemSearchDialog(initialBarcode: barcode);
        }
      }
    }
  }

  void _showSpeechEngineMissingDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.settings_voice_rounded, color: Color(0xFFD97706), size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'Voice Search Setup',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This Sunmi device is running Sunmi OS, which does not have Google\'s Speech Recognition Engine installed.',
                style: TextStyle(color: Color(0xFF4B5563), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              const Text(
                'HOW TO ENABLE:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0, color: Color(0xFF71717A)),
              ),
              const SizedBox(height: 8),
              _buildDialogStep('1', 'Install "Speech Services by Google" from the Play Store or via APK.'),
              const SizedBox(height: 6),
              _buildDialogStep('2', 'Go to device Settings > Languages & Input > Assist App and select Google.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Dismiss', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDialogStep(String num, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            num,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF374151)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: Color(0xFF374151), height: 1.3),
          ),
        ),
      ],
    );
  }

  Future<void> _searchSuppliers(String query) async {
    if (query.isEmpty) {
      setState(() => _supplierResults = _cachedSuppliers);
      return;
    }
    
    final lowercaseQuery = query.toLowerCase();
    setState(() {
      _supplierResults = _cachedSuppliers.where((sup) {
        final name = (sup['ACC_NAME'] ?? '').toString().toLowerCase();
        final no = (sup['ACC_NO'] ?? '').toString().toLowerCase();
        return name.contains(lowercaseQuery) || no.contains(lowercaseQuery);
      }).toList();
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF4F46E5),
              onPrimary: Colors.white,
              onSurface: Color(0xFF18181B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<String?> _saveInvoice(double gross, double vat, double net, {bool showPreview = true}) async {
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a supplier first'), backgroundColor: Colors.red),
      );
      return null;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item to the invoice'), backgroundColor: Colors.red),
      );
      return null;
    }

    setState(() => _isLoading = true);
    
    int wrCode = 0;
    int brnCode = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      wrCode = prefs.getInt('LOGGED_WR_CODE') ?? 0;
      brnCode = prefs.getInt('LOGGED_BRN_CODE') ?? 0;
    } catch (e) {
      debugPrint('Error reading wrCode/brnCode from SharedPreferences: $e');
    }
    
    final payload = {
      "ACCODE": _selectedSupplier!['ACC_NO'].toString(),
      "ENAME": _selectedSupplier!['ACC_NAME'],
      "G_TOTAL": gross,
      "DISC_AMT": 0,
      "NET_AMOUNT": net,
      "VAT_AMOUNT": vat,
      "VAT_NUMBER": "",
      "PAYMENT_METHOD": "Others", 
      "TRN_TYPE": 2, 
      "REF_INV_NO": _invoiceNoController.text,
      "PRICE_INCLUDE_VAT": _priceIncludeVat,
      "TAXABLE_AMOUNT": gross,
      "wrCode": wrCode,
      "brnCode": brnCode,
      "ROWS": _items.map((item) {
        double itemTotal = item.qty * item.price;
        double itemVat = 0.0;
        if (_priceIncludeVat) {
          double base = itemTotal / (1 + (item.vatPercent / 100));
          itemVat = itemTotal - base;
        } else {
          itemVat = itemTotal * (item.vatPercent / 100);
        }
        return {
          "itemCode": item.code,
          "description": item.description,
          "qty": item.qty,
          "price": item.price,
          "unit": "Pcs",
          "vatPercent": item.vatPercent,
          "vatAmount": itemVat,
          "total": _priceIncludeVat ? itemTotal : (itemTotal + itemVat),
        };
      }).toList(),
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sales/save'),
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final String savedInvoiceNo = result['INVOICE_NO'].toString();
        
        setState(() {
          _lastSavedInvoiceNo = savedInvoiceNo;
        });

        if (showPreview) {
          // Show Invoice Preview
          await _showInvoicePreviewDialog(savedInvoiceNo, payload);
          if (_saveNClear) {
            _clearScreen();
          }
        }
        
        return savedInvoiceNo;
      } else {
        throw Exception('Server error: ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save invoice: $e'), backgroundColor: Colors.red),
      );
      return null;
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showInvoicePreviewDialog(String invoiceNo, Map<String, dynamic> invoiceData) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
            maxWidth: 400,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Gradient
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF059669), Color(0xFF10B981)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('INVOICE SAVED', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                            Text('Invoice #$invoiceNo', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('SUPPLIER', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(invoiceData['ENAME'] ?? 'Unknown', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text('ACC: ${invoiceData['ACCODE']}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('DATE', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(DateFormat('dd MMM yyyy').format(DateTime.now()), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(height: 6),
                              const Text('REFERENCE NO', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(invoiceData['REF_INV_NO'] != null && invoiceData['REF_INV_NO'].toString().isNotEmpty ? invoiceData['REF_INV_NO'].toString() : 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Color(0xFFF1F5F9), height: 1),
                      const SizedBox(height: 8),
                      Row(
                        children: const [
                          Expanded(flex: 3, child: Text('ITEM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                          Expanded(child: Text('QTY', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                          Expanded(flex: 2, child: Text('TOTAL', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 120),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: (invoiceData['ROWS'] as List).length,
                          separatorBuilder: (context, index) => const Divider(height: 12, color: Color(0xFFF8FAFC)),
                          itemBuilder: (context, index) {
                            final row = (invoiceData['ROWS'] as List)[index];
                            return Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(row['description'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      Text(row['itemCode'], style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Text(row['qty'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('SAR ${(row['qty'] * row['price']).toStringAsFixed(2)}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TOTAL AMOUNT (EXCL. VAT)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B))),
                                Text('SAR ${(invoiceData['G_TOTAL'] ?? 0.0).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF1E293B))),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('VAT AMOUNT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B))),
                                Text('SAR ${(invoiceData['VAT_AMOUNT'] ?? 0.0).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF1E293B))),
                              ],
                            ),
                            const Divider(height: 16, color: Color(0xFFE2E8F0)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('NET AMOUNT (INCL. VAT)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Color(0xFF1E293B))),
                                Text('SAR ${(invoiceData['NET_AMOUNT'] ?? 0.0).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF4F46E5))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showItemSearchDialog({String? initialBarcode}) async {
    Map<String, dynamic>? selectedItem;
    final TextEditingController costPriceController = TextEditingController();
    final TextEditingController qtyController = TextEditingController(text: '1');
    final TextEditingController searchController = TextEditingController();
    List<dynamic> dialogResults = _cachedItems.take(20).toList();
    bool dialogLoading = false;

    // Pre-populate if initialBarcode is provided
    if (initialBarcode != null && initialBarcode.isNotEmpty) {
      final matched = _cachedItems.firstWhere(
        (element) => (element['BARCODE'] ?? '').toString().trim() == initialBarcode.trim(),
        orElse: () => null,
      );
      if (matched != null) {
        selectedItem = matched;
        costPriceController.text = (matched['AVG_PUR_PRICE'] ?? 0.0).toString();
      } else {
        selectedItem = {
          'BARCODE': initialBarcode,
          'DESCRIPTION': '',
          'AVG_PUR_PRICE': 0.0,
          'IS_NEW': true,
        };
        costPriceController.text = '0.0';
      }
    }

    final TextEditingController descriptionController = TextEditingController();
    if (selectedItem != null && selectedItem!['IS_NEW'] == true) {
      descriptionController.text = '';
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void search(String q) {
            if (q.isEmpty) {
              setDialogState(() => dialogResults = _cachedItems.take(20).toList());
              return;
            }
            final lowercaseQuery = q.toLowerCase();
            setDialogState(() {
              dialogResults = _cachedItems.where((item) {
                final barcode = (item['BARCODE'] ?? '').toString().toLowerCase();
                final desc = (item['DESCRIPTION'] ?? '').toString().toLowerCase();
                return barcode.contains(lowercaseQuery) || desc.contains(lowercaseQuery);
              }).take(50).toList();
            });
          }

          void addToList() {
            if (selectedItem == null) return;
            
            final double? newPrice = double.tryParse(costPriceController.text);
            final int? qty = int.tryParse(qtyController.text);
            final String description = (selectedItem!['IS_NEW'] == true) 
                ? descriptionController.text 
                : (selectedItem!['DESCRIPTION'] ?? 'N/A');
            
            if (newPrice == null || qty == null || description.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please fill all fields'), backgroundColor: Colors.orange),
              );
              return;
            }

            final double itemVat = double.tryParse(selectedItem!['VAT_PERCENT']?.toString() ?? '15') ?? 15.0;

            setState(() {
              _items.add(InvoiceItem(
                code: selectedItem!['BARCODE']?.toString() ?? 'N/A',
                description: description,
                qty: qty,
                price: newPrice,
                vatPercent: itemVat,
              ));
            });
            
            Navigator.pop(context);
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.95,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.80,
                maxWidth: 450,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 40, offset: const Offset(0, 20)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  children: [
                    // Premium Minimal Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7), width: 1)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SELECT ITEM',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                    color: Colors.indigo[800],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF71717A)),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFF4F4F5),
                              padding: const EdgeInsets.all(6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: selectedItem == null
                          ? Column(
                              children: [
                                // Styled Search Bar with Integrated Scanner Button
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: const Color(0xFFE2E8F0)),
                                          ),
                                          child: TextField(
                                            controller: searchController,
                                            onChanged: search,
                                            decoration: const InputDecoration(
                                              hintText: 'Search by name or barcode...',
                                              hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                                              prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 20),
                                              border: InputBorder.none,
                                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        height: 48,
                                        width: 48,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF4F46E5),
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF4F46E5).withOpacity(0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          onPressed: () async {
                                            // This button is not used in continuous scanning mode but kept for backward compatibility
                                          },
                                          icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 24),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: dialogLoading
                                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))
                                      : dialogResults.isEmpty
                                          ? const Center(child: Text('No items found', style: TextStyle(color: Color(0xFF71717A), fontSize: 13)))
                                          : ListView.separated(
                                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                              itemCount: dialogResults.length,
                                              separatorBuilder: (context, index) => const SizedBox(height: 8),
                                              itemBuilder: (context, index) {
                                                final item = dialogResults[index];
                                                return InkWell(
                                                  onTap: () {
                                                    setDialogState(() {
                                                      selectedItem = item;
                                                      costPriceController.text = (item['AVG_PUR_PRICE'] ?? 0.0).toString();
                                                    });
                                                  },
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      border: Border.all(color: const Color(0xFFF4F4F5)),
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Text(
                                                                item['DESCRIPTION'] ?? 'Unknown',
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
                                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF18181B)),
                                                              ),
                                                              const SizedBox(height: 2),
                                                              Text(
                                                                'Code: ${item['BARCODE']}',
                                                                style: const TextStyle(color: Color(0xFF71717A), fontSize: 11),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Column(
                                                          crossAxisAlignment: CrossAxisAlignment.end,
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              'SAR ${double.tryParse(item['AVG_PUR_PRICE']?.toString() ?? '0.0')?.toStringAsFixed(2) ?? '0.00'}',
                                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF18181B)),
                                                            ),
                                                            const Text(
                                                              'Avg Cost',
                                                              style: TextStyle(color: Color(0xFF71717A), fontSize: 9, fontWeight: FontWeight.w500),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                ),
                              ],
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Add to Invoice & Change Item buttons Row at the top!
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: SizedBox(
                                          height: 44,
                                          child: ElevatedButton.icon(
                                            onPressed: addToList,
                                            icon: const Icon(Icons.add_rounded, size: 16),
                                            label: const Text('Add to Invoice', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF4F46E5),
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              elevation: 0,
                                              padding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 1,
                                        child: SizedBox(
                                          height: 44,
                                          child: OutlinedButton(
                                            onPressed: () => setDialogState(() => selectedItem = null),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(0xFF71717A),
                                              side: const BorderSide(color: Color(0xFFE4E4E7)),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              padding: EdgeInsets.zero,
                                            ),
                                            child: const Text('Back', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Selected Item Info Card
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (selectedItem!['IS_NEW'] == true)
                                          _buildPremiumTextField('Item Description', descriptionController, Icons.description_rounded, autofocus: true)
                                        else ...[
                                          Text(
                                            selectedItem!['DESCRIPTION'] ?? 'Unknown',
                                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF1E293B)),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Barcode: ${selectedItem!['BARCODE']}',
                                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, letterSpacing: 0.5),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: _buildPremiumField('Purchase Price', costPriceController, Icons.payments_rounded),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 2,
                                        child: _buildPremiumField('Quantity', qtyController, Icons.shopping_bag_rounded, autofocus: selectedItem!['IS_NEW'] != true),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

    Widget _buildPremiumField(String label, TextEditingController controller, IconData icon, {bool autofocus = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 1)),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (hasFocus) {
            if (hasFocus) {
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
            }
          },
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: autofocus,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: const Color(0xFF4F46E5), size: 20),
              filled: true,
              fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumTextField(String label, TextEditingController controller, IconData icon, {bool autofocus = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 1)),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (hasFocus) {
            if (hasFocus) {
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
            }
          },
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: const Color(0xFF4F46E5), size: 18),
              hintText: 'Enter $label',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.normal),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _searchResults = [];
          _supplierResults = [];
        });
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: const Color(0xFFFAFAFA),
        body: SafeArea(
          child: Column(
            children: [
              _buildCustomAppBar(),
              _buildTabNavigation(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _activeTab == 0 
                      ? _buildHeaderView() 
                      : (_activeTab == 1 ? _buildItemsView() : _buildSettingsView()),
                ),
              ),
              if (_activeTab != 2) _buildBottomSummary(),
            ],
          ),
        ),
        floatingActionButton: null,
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SUPPLIER INVOICE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.indigo[700],
                ),
              ),
              Row(
                children: [
                  const Text(
                    'Create New Entry',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF18181B),
                    ),
                  ),
                  if (_lastSavedInvoiceNo != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF10B981), width: 1),
                      ),
                      child: Text(
                        '#$_lastSavedInvoiceNo',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF065F46),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'history') {
                Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(builder: (context) => const HistoryPage()),
                ).then((invoice) {
                  if (invoice != null) {
                    _loadInvoiceIntoEditor(invoice);
                  }
                });
              } else if (value == 'clear_cache') {
                _loadCache();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache reloaded successfully!'), backgroundColor: Colors.green),
                );
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'history',
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 20, color: Color(0xFF18181B)),
                    SizedBox(width: 12),
                    Text('Invoice History', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'clear_cache',
                child: Row(
                  children: [
                    Icon(Icons.cached_rounded, size: 20, color: Color(0xFF18181B)),
                    SizedBox(width: 12),
                    Text('Reload Cache', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E4E7)),
              ),
              child: const Icon(Icons.more_vert_rounded, color: Color(0xFF71717A)),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildTabNavigation() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _buildTabItem(0, 'Header', Icons.receipt_long_rounded),
            _buildTabItem(1, 'Items', Icons.grid_view_rounded),
            _buildTabItem(2, 'Settings', Icons.settings_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, String label, IconData icon) {
    bool isActive = _activeTab == index;
    return Expanded(
      child: GestureDetector(
      onTap: () {
        setState(() {
          _activeTab = index;
          _searchResults = [];
          _supplierResults = [];
        });
      },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive 
                ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isActive ? const Color(0xFF4F46E5) : const Color(0xFF71717A)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? const Color(0xFF18181B) : const Color(0xFF71717A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderView() {
    return SingleChildScrollView(
      key: const ValueKey(0),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_lastSavedInvoiceNo != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5), // Emerald green tint
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LAST INVOICE SAVED SUCCESSFULLY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF065F46),
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Generated Invoice No: #$_lastSavedInvoiceNo',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF047857)),
                    onPressed: () {
                      setState(() {
                        _lastSavedInvoiceNo = null;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          _buildFormSection('General Information', [
            _buildInputField('Reference Number', _invoiceNoController, Icons.tag_rounded),
            const SizedBox(height: 16),
            _buildSupplierSearchField(),
            const SizedBox(height: 16),
            _buildDateField('Invoice Date', _selectedDate, Icons.calendar_today_rounded),
          ]),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    onPressed: _clearScreen,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red[700],
                      side: BorderSide(color: Colors.red[200]!),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Clear', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _activeTab = 1;
                        _searchResults = [];
                        _supplierResults = [];
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Proceed to Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsView() {
    return Column(
      key: const ValueKey(1),
      children: [
        if (_isScanningMode)
          _buildScannerPanel(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _buildItemSearchField(),
        ),
        Expanded(
          child: _items.isEmpty 
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    const Text('No items added to invoice', style: TextStyle(color: Color(0xFF71717A))),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _items.length,
                itemBuilder: (context, index) => _buildItemCard(_items[index], index),
              ),
        ),
      ],
    );
  }

  Widget _buildItemCard(InvoiceItem item, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '#${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFF4F46E5),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.description, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(item.code, style: const TextStyle(color: Color(0xFF71717A), fontSize: 10)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _showEditItemDialog(item, index),
                icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF4F46E5)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  setState(() {
                    _items.remove(item);
                  });
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildItemDetail('Qty', item.qty.toString()),
              _buildItemDetail('Cost Price', 'SAR ${item.price.toStringAsFixed(2)}'),
              _buildItemDetail(
                _priceIncludeVat ? 'Net (Incl. VAT)' : 'Subtotal', 
                'SAR ${item.total.toStringAsFixed(2)}'
              ),
              _buildItemDetail(
                'VAT (${item.vatPercent.toStringAsFixed(0)}%)',
                _priceIncludeVat
                    ? 'SAR ${(item.total - (item.total / (1 + (item.vatPercent / 100)))).toStringAsFixed(2)}'
                    : 'SAR ${(item.total * (item.vatPercent / 100)).toStringAsFixed(2)}'
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showEditItemDialog(InvoiceItem item, int itemIndex) async {
    final TextEditingController costPriceController = TextEditingController(text: item.price.toString());
    final TextEditingController qtyController = TextEditingController(text: item.qty.toString());
    final TextEditingController descriptionController = TextEditingController(text: item.description);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void updateItem() {
            final double? newPrice = double.tryParse(costPriceController.text);
            final int? newQty = int.tryParse(qtyController.text);
            final String description = descriptionController.text.trim();

            if (newPrice == null || newQty == null || description.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please fill all fields'), backgroundColor: Colors.orange),
              );
              return;
            }

            setState(() {
              _items[itemIndex] = InvoiceItem(
                code: item.code,
                description: description,
                qty: newQty,
                price: newPrice,
                vatPercent: item.vatPercent,
              );
            });

            Navigator.pop(context);
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Bar (With immediate Save and Back at top!)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: Colors.white,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded, size: 16, color: Color(0xFF71717A)),
                            label: const Text('Back', style: TextStyle(color: Color(0xFF71717A), fontWeight: FontWeight.bold, fontSize: 13)),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                          ),
                          const Text(
                            'Edit Item',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF1E293B)),
                          ),
                          ElevatedButton.icon(
                            onPressed: updateItem,
                            icon: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                            label: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    
                    // Input Form Fields
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Product Info Box
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE0E7FF)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.inventory_2_rounded, color: Color(0xFF4F46E5), size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.code,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: Color(0xFF312E81),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'Selected Product Code',
                                          style: TextStyle(fontSize: 10, color: Color(0xFF4F46E5)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Editable Description Input
                            const Text(
                              'DESCRIPTION',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.8),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: descriptionController,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                hintText: 'Enter Description',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                                ),
                                fillColor: Colors.white,
                                filled: true,
                              ),
                            ),
                            const SizedBox(height: 12),
                            
                            // Side-by-Side Qty and Cost inputs
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'QUANTITY',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.8),
                                      ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: qtyController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                        decoration: InputDecoration(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                                          ),
                                          fillColor: Colors.white,
                                          filled: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'COST PRICE',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.8),
                                      ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: costPriceController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                        decoration: InputDecoration(
                                          prefixText: 'SAR ',
                                          prefixStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                                          ),
                                          fillColor: Colors.white,
                                          filled: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildItemDetail(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 9, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF18181B)),
          ),
        ],
      ),
    );
  }

  Widget _buildFormSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Color(0xFF71717A)),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildSupplierSearchField() {
    final String? selectedAccNo = _selectedSupplier?['ACC_NO']?.toString();
    
    // Check if the selectedAccNo exists in _cachedSuppliers. If not, inject it.
    final bool hasSelected = _cachedSuppliers.any((sup) => sup['ACC_NO']?.toString() == selectedAccNo);
    
    List<dynamic> dropdownItems = List<dynamic>.from(_cachedSuppliers);
    if (selectedAccNo != null && !hasSelected && _selectedSupplier != null) {
      dropdownItems.insert(0, _selectedSupplier!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: selectedAccNo,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Supplier Name',
            prefixIcon: const Icon(Icons.business_rounded, size: 20, color: Color(0xFF4F46E5)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          hint: const Text('Select Supplier...', style: TextStyle(color: Color(0xFF94A3B8))),
          items: dropdownItems.map<DropdownMenuItem<String>>((sup) {
            return DropdownMenuItem<String>(
              value: sup['ACC_NO']?.toString(),
              child: Text(
                '${sup['ACC_NAME'] ?? "Unknown"} (${sup['ACC_NO']})',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF18181B)),
              ),
            );
          }).toList(),
          onChanged: (String? val) {
            if (val != null) {
              final found = dropdownItems.firstWhere((sup) => sup['ACC_NO']?.toString() == val);
              setState(() {
                _selectedSupplier = found;
                _supplierController.text = found['ACC_NAME'] ?? '';
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildItemSearchField() {
    return Column(
      children: [
        TextFormField(
          controller: _itemSearchController,
          decoration: InputDecoration(
            hintText: 'Search items by name or barcode...',
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4F46E5), size: 18),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: _isListening ? Colors.redAccent : const Color(0xFF4F46E5),
                    size: 18,
                  ),
                  onPressed: _startVoiceSearch,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                IconButton(
                  icon: Icon(
                    _isScanningMode ? Icons.qr_code_rounded : Icons.qr_code_scanner_rounded,
                    color: _isScanningMode ? const Color(0xFF10B981) : const Color(0xFF4F46E5),
                    size: 18,
                  ),
                  onPressed: () {
                    setState(() {
                      _isScanningMode = !_isScanningMode;
                      if (_isScanningMode) {
                        _searchResults = [];
                      }
                    });
                  },
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ],
            ),
          ),
          onChanged: _searchItems,
          onFieldSubmitted: (val) {
            if (val.trim().isNotEmpty) {
              if (_searchResults.isNotEmpty) {
                final barcode = _searchResults.first['BARCODE']?.toString();
                setState(() {
                  _searchResults = [];
                  _itemSearchController.clear();
                });
                if (barcode != null) {
                  _showItemSearchDialog(initialBarcode: barcode);
                }
              } else {
                final query = val.trim();
                setState(() {
                  _searchResults = [];
                  _itemSearchController.clear();
                });
                _showItemSearchDialog(initialBarcode: query);
              }
            }
          },
        ),
        if (_itemSearchController.text.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE4E4E7)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)],
            ),
            constraints: const BoxConstraints(maxHeight: 300),
            child: _searchResults.isEmpty 
              ? ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEEF2FF),
                    child: Icon(Icons.add_rounded, color: Color(0xFF4F46E5)),
                  ),
                  title: Text('Add "${_itemSearchController.text}" as new item'),
                  subtitle: const Text('This barcode was not found in the database'),
                  onTap: () {
                    final query = _itemSearchController.text;
                    setState(() => _searchResults = []);
                    _itemSearchController.clear();
                    _showItemSearchDialog(initialBarcode: query);
                  },
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final item = _searchResults[index];
                    return ListTile(
                      title: Text(item['DESCRIPTION'] ?? 'No Description'),
                      subtitle: Text('Barcode: ${item['BARCODE']} | Avg Cost: SAR ${item['AVG_PUR_PRICE']}'),
                      trailing: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF4F46E5)),
                      onTap: () {
                        final barcode = item['BARCODE']?.toString();
                        setState(() {
                          _searchResults = [];
                          _itemSearchController.clear();
                        });
                        if (barcode != null) {
                          _showItemSearchDialog(initialBarcode: barcode);
                        }
                      },
                    );
                  },
                ),
          ),
      ],
    );
  }

  Widget _buildDateField(String label, DateTime date, IconData icon) {
    return GestureDetector(
      onTap: () => _selectDate(context),
      child: AbsorbPointer(
        child: TextFormField(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 20, color: const Color(0xFF4F46E5)),
            hintText: '${date.day}/${date.month}/${date.year}',
          ),
          controller: TextEditingController(text: '${date.day}/${date.month}/${date.year}'),
        ),
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, IconData icon) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
        }
      },
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20, color: const Color(0xFF4F46E5)),
          hintText: 'Enter $label',
        ),
      ),
    );
  }

  Widget _buildBottomSummary() {
    double totalGross = 0.0;
    double totalVat = 0.0;
    double totalNet = 0.0;

    for (var item in _items) {
      double itemTotal = item.qty * item.price;
      double itemVatPercent = item.vatPercent;
      if (_priceIncludeVat) {
        double base = itemTotal / (1 + (itemVatPercent / 100));
        double vat = itemTotal - base;
        totalGross += base;
        totalVat += vat;
        totalNet += itemTotal;
      } else {
        double vat = itemTotal * (itemVatPercent / 100);
        totalGross += itemTotal;
        totalVat += vat;
        totalNet += itemTotal + vat;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE4E4E7))),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryRow('Total Base', 'SAR ${totalGross.toStringAsFixed(2)}'),
              _buildSummaryRow('Total VAT Amt', 'SAR ${totalVat.toStringAsFixed(2)}', valueColor: Colors.indigo[700]),
              _buildSummaryRow('Net Amt', 'SAR ${totalNet.toStringAsFixed(2)}', isBold: true, valueColor: const Color(0xFF4F46E5)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: 20,
                width: 20,
                child: Checkbox(
                  value: _saveNClear,
                  onChanged: (val) {
                    setState(() {
                      _saveNClear = val ?? false;
                    });
                  },
                  activeColor: const Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Save N Clear',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: _items.isEmpty ? null : () => _handlePrintAction(totalGross, totalVat, totalNet),
                    icon: const Icon(Icons.print_rounded, size: 16),
                    label: const Text('Print Receipt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4F46E5),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _saveInvoice(totalGross, totalVat, totalNet),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF18181B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: EdgeInsets.zero,
                    ),
                    child: _isLoading 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Save Invoice', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 10, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
              color: valueColor ?? const Color(0xFF18181B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormSection('VAT Config & Pricing', [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE4E4E7)),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Price Include VAT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text('Calculate tax as inclusive of total item price', style: TextStyle(fontSize: 12)),
                    value: _priceIncludeVat,
                    activeColor: const Color(0xFF4F46E5),
                    onChanged: (bool value) {
                      setState(() {
                        _priceIncludeVat = value;
                      });
                    },
                  ),
                  const Divider(height: 1, color: Color(0xFFE4E4E7)),
                  SwitchListTile(
                    title: const Text('Save N Clear', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text('Automatically clear editor after successful save or print', style: TextStyle(fontSize: 12)),
                    value: _saveNClear,
                    activeColor: const Color(0xFF4F46E5),
                    onChanged: (bool value) {
                      setState(() {
                        _saveNClear = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 24),
          _buildFormSection('Printer Configuration', [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE4E4E7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Receipt Paper Size', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text('Choose formatting width for your invoice printing', style: TextStyle(fontSize: 12, color: Color(0xFF71717A))),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedPrinterWidth,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF4F4F5),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                    items: const [
                      DropdownMenuItem(value: '58mm', child: Text('58mm (Handheld/Sunmi V2)')),
                      DropdownMenuItem(value: '80mm', child: Text('80mm (Desktop Thermal)')),
                      DropdownMenuItem(value: 'A4', child: Text('A4 (Standard Document)')),
                    ],
                    onChanged: (String? val) {
                      if (val != null) {
                        setState(() {
                          _selectedPrinterWidth = val;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                if (_items.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please add some items to print a test invoice!'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                double totalGross = 0.0;
                double totalVat = 0.0;
                double totalNet = 0.0;
                for (var item in _items) {
                  double itemTotal = item.qty * item.price;
                  double itemVatPercent = item.vatPercent;
                  if (_priceIncludeVat) {
                    double base = itemTotal / (1 + (itemVatPercent / 100));
                    double vat = itemTotal - base;
                    totalGross += base;
                    totalVat += vat;
                    totalNet += itemTotal;
                  } else {
                    double vat = itemTotal * (itemVatPercent / 100);
                    totalGross += itemTotal;
                    totalVat += vat;
                    totalNet += itemTotal + vat;
                  }
                }
                _printInvoice(totalGross, totalVat, totalNet);
              },
              icon: const Icon(Icons.print_rounded, size: 18),
              label: const Text('Print Current Invoice', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _printInvoice(double gross, double vat, double net, {String? savedInvoiceNo}) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(16),
                width: _selectedPrinterWidth == '58mm'
                    ? 320
                    : (_selectedPrinterWidth == '80mm' ? 400 : 550),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'PRINT PREVIEW (${_selectedPrinterWidth})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF71717A)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF9F6),
                        border: Border.all(color: const Color(0xFFE4E4E7)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: _selectedPrinterWidth == '58mm'
                          ? _build58mmReceipt(gross, vat, net, savedInvoiceNo: savedInvoiceNo)
                          : (_selectedPrinterWidth == '80mm'
                              ? _build80mmReceipt(gross, vat, net, savedInvoiceNo: savedInvoiceNo)
                              : _buildA4Invoice(gross, vat, net, savedInvoiceNo: savedInvoiceNo)),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _triggerNativePrint(gross, vat, net, savedInvoiceNo: savedInvoiceNo);
                            },
                            icon: const Icon(Icons.print_rounded),
                            label: const Text('Print Now'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _triggerNativePrint(double gross, double vat, double net, {String? savedInvoiceNo}) async {
    final bool isAndroid = defaultTargetPlatform == TargetPlatform.android;
    if (!isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Physical printing is only supported on native Android Sunmi devices.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // 1. Initialize and bind printer service
      await SunmiPrinter.initPrinter();
      await SunmiPrinter.bindingPrinter();

      // 2. Start Printing Transaction
      await SunmiPrinter.startTransactionPrint(true);
      
      // Header
      await SunmiPrinter.printText(
        'EAZYMOB SYSTEMS',
        style: SunmiTextStyle(bold: true, fontSize: 32, align: SunmiPrintAlign.CENTER),
      );
      await SunmiPrinter.printText(
        'Supplier Invoice Receipt',
        style: SunmiTextStyle(fontSize: 24, align: SunmiPrintAlign.CENTER),
      );
      await SunmiPrinter.lineWrap(1);

      // Meta info
      final String invoiceNo = savedInvoiceNo ?? (_invoiceNoController.text.isNotEmpty ? _invoiceNoController.text : "DRAFT");
      await SunmiPrinter.printText('Invoice No: $invoiceNo', style: SunmiTextStyle(fontSize: 20, align: SunmiPrintAlign.LEFT));
      await SunmiPrinter.printText('Date: ${DateFormat('dd/MM/yyyy HH:mm').format(_selectedDate)}', style: SunmiTextStyle(fontSize: 20, align: SunmiPrintAlign.LEFT));
      await SunmiPrinter.printText('Supplier: ${_selectedSupplier?["ACC_NAME"] ?? "Walk-in Supplier"}', style: SunmiTextStyle(fontSize: 20, align: SunmiPrintAlign.LEFT));
      
      await SunmiPrinter.line(); // Dashed divider

      // Columns header
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'ITEM DESC', width: 6, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: 'QTYxPRC', width: 3, style: SunmiTextStyle(align: SunmiPrintAlign.CENTER)),
        SunmiColumn(text: 'TOTAL', width: 3, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
      await SunmiPrinter.line();

      // Items list
      for (var item in _items) {
        double totalPr = item.qty * item.price;
        // Print product name
        await SunmiPrinter.printText(item.description, style: SunmiTextStyle(bold: true, fontSize: 22, align: SunmiPrintAlign.LEFT));
        // Print qty, price, and total in columns
        await SunmiPrinter.printRow(cols: [
          SunmiColumn(text: '  ${item.qty}x${item.price.toStringAsFixed(2)}', width: 8, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
          SunmiColumn(text: 'SAR ${totalPr.toStringAsFixed(2)}', width: 4, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
        ]);
      }

      await SunmiPrinter.line();

      // Totals
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'TOTAL EXCL VAT:', width: 7, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: 'SAR ${gross.toStringAsFixed(2)}', width: 5, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'TOTAL VAT:', width: 7, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: 'SAR ${vat.toStringAsFixed(2)}', width: 5, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);
      
      await SunmiPrinter.line();
      
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(text: 'NET PAYABLE:', width: 6, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: 'SAR ${net.toStringAsFixed(2)}', width: 6, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ]);

      await SunmiPrinter.line();
      await SunmiPrinter.lineWrap(1);

      // Footer
      await SunmiPrinter.printText('*** THANK YOU ***', style: SunmiTextStyle(bold: true, fontSize: 24, align: SunmiPrintAlign.CENTER));
      await SunmiPrinter.lineWrap(3); // Feed paper for easy tear off

      // 3. Commit Printing Transaction
      await SunmiPrinter.exitTransactionPrint(true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt printed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Sunmi Printer Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Printing failed: $e'),
          backgroundColor: Colors.red[800],
        ),
      );
    }
  }

  Widget _build58mmReceipt(double gross, double vat, double net, {String? savedInvoiceNo}) {
    const style = TextStyle(fontFamily: 'Courier', color: Colors.black87, fontSize: 12);
    const styleBold = TextStyle(fontFamily: 'Courier', color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13);
    const styleHeader = TextStyle(fontFamily: 'Courier', color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16);

    return Column(
      children: [
        const Text('EAZYERP SYSTEMS', style: styleHeader),
        const Text('Supplier Invoice Receipt', style: style),
        const SizedBox(height: 8),
        Text('Invoice No: ${savedInvoiceNo ?? (_invoiceNoController.text.isNotEmpty ? _invoiceNoController.text : "DRAFT")}', style: style),
        Text('Date: ${DateFormat('dd/MM/yyyy HH:mm').format(_selectedDate)}', style: style),
        Text('Supplier: ${_selectedSupplier?["ACC_NAME"] ?? "Walk-in Supplier"}', style: style),
        const Text('--------------------------------', style: style),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ITEM DESC', style: styleBold),
            Text('QTYxPRC   TOTAL', style: styleBold),
          ],
        ),
        const Text('--------------------------------', style: style),
        ..._items.map((item) {
          double totalPr = item.qty * item.price;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.description, style: styleBold, maxLines: 1, overflow: TextOverflow.ellipsis),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(' ${item.qty}x${item.price.toStringAsFixed(2)}', style: style),
                    Text('SAR ${totalPr.toStringAsFixed(2)}', style: style),
                  ],
                ),
              ],
            ),
          );
        }),
        const Text('--------------------------------', style: style),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('TOTAL EXCL VAT:', style: style),
            Text('SAR ${gross.toStringAsFixed(2)}', style: style),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('TOTAL VAT:', style: style),
            Text('SAR ${vat.toStringAsFixed(2)}', style: style),
          ],
        ),
        const Text('--------------------------------', style: style),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('NET PAYABLE:', style: styleBold),
            Text('SAR ${net.toStringAsFixed(2)}', style: styleBold),
          ],
        ),
        const Text('--------------------------------', style: style),
        const SizedBox(height: 8),
        const Text('*** THANK YOU ***', style: styleBold),
      ],
    );
  }

  Widget _build80mmReceipt(double gross, double vat, double net, {String? savedInvoiceNo}) {
    const style = TextStyle(fontFamily: 'Courier', color: Colors.black87, fontSize: 13);
    const styleBold = TextStyle(fontFamily: 'Courier', color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14);
    const styleHeader = TextStyle(fontFamily: 'Courier', color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18);

    return Column(
      children: [
        const Text('EAZYERP PURCHASE DEPT', style: styleHeader),
        const Text('Supplier Goods Inward Note', style: style),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Inv No: ${savedInvoiceNo ?? (_invoiceNoController.text.isNotEmpty ? _invoiceNoController.text : "DRAFT")}', style: style),
            Text('Date: ${DateFormat('dd/MM/yyyy HH:mm').format(_selectedDate)}', style: style),
          ],
        ),
        Row(
          children: [
            Text('Supplier: ${_selectedSupplier?["ACC_NAME"] ?? "Walk-in Supplier"} (${_selectedSupplier?["ACC_NO"] ?? "N/A"})', style: style),
          ],
        ),
        const SizedBox(height: 8),
        const Text('------------------------------------------', style: style),
        Row(
          children: const [
            Expanded(flex: 3, child: Text('ITEM DESCRIPTION', style: styleBold)),
            Expanded(child: Text('QTY', textAlign: TextAlign.center, style: styleBold)),
            Expanded(child: Text('PRICE', textAlign: TextAlign.right, style: styleBold)),
            Expanded(child: Text('TOTAL', textAlign: TextAlign.right, style: styleBold)),
          ],
        ),
        const Text('------------------------------------------', style: style),
        ..._items.map((item) {
          double totalPr = item.qty * item.price;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.description, style: styleBold, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('Code: ${item.code} (VAT ${item.vatPercent.toStringAsFixed(0)}%)', style: const TextStyle(fontFamily: 'Courier', fontSize: 11, color: Colors.black54)),
                    ],
                  ),
                ),
                Expanded(child: Text(item.qty.toString(), textAlign: TextAlign.center, style: style)),
                Expanded(child: Text(item.price.toStringAsFixed(2), textAlign: TextAlign.right, style: style)),
                Expanded(child: Text(totalPr.toStringAsFixed(2), textAlign: TextAlign.right, style: style)),
              ],
            ),
          );
        }),
        const Text('------------------------------------------', style: style),
        Align(
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Subtotal (Excl. VAT): SAR ${gross.toStringAsFixed(2)}', style: style),
              Text('Total VAT Amount:     SAR ${vat.toStringAsFixed(2)}', style: style),
              const SizedBox(height: 4),
              Text('Net Amount (Incl. VAT): SAR ${net.toStringAsFixed(2)}', style: styleBold),
            ],
          ),
        ),
        const Text('------------------------------------------', style: style),
        const SizedBox(height: 12),
        const Text('Approved by Inventory Controller', style: style),
      ],
    );
  }

  Widget _buildA4Invoice(double gross, double vat, double net, {String? savedInvoiceNo}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('EAZYERP ENTERPRISES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E3A8A))),
                Text('Tax Registration No: 300055281400003', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ],
            ),
            const Text('TAX INVOICE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF1E3A8A))),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(color: Color(0xFFE2E8F0)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SUPPLIER / BILL FROM:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  Text(_selectedSupplier?["ACC_NAME"] ?? "Walk-in Supplier", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text('Account Number: ${_selectedSupplier?["ACC_NO"] ?? "N/A"}', style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('INVOICE DETAILS:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  Text('Invoice Number: ${savedInvoiceNo ?? (_invoiceNoController.text.isNotEmpty ? _invoiceNoController.text : "DRAFT")}', style: const TextStyle(fontSize: 11)),
                  Text('Invoice Date: ${DateFormat('dd MMM yyyy').format(_selectedDate)}', style: const TextStyle(fontSize: 11)),
                  Text('Method: Cash Purchase', style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1.2),
            3: FlexColumnWidth(1.2),
            4: FlexColumnWidth(1.2),
          },
          border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 1),
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
              children: const [
                Padding(padding: EdgeInsets.all(8.0), child: Text('Item Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                Padding(padding: EdgeInsets.all(8.0), child: Text('Qty', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                Padding(padding: EdgeInsets.all(8.0), child: Text('Unit Price', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                Padding(padding: EdgeInsets.all(8.0), child: Text('VAT %', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                Padding(padding: EdgeInsets.all(8.0), child: Text('Total', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
              ],
            ),
            ..._items.map((item) {
              double totalPr = item.qty * item.price;
              return TableRow(
                children: [
                  Padding(padding: const EdgeInsets.all(8.0), child: Text(item.description, style: const TextStyle(fontSize: 11))),
                  Padding(padding: const EdgeInsets.all(8.0), child: Text(item.qty.toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
                  Padding(padding: const EdgeInsets.all(8.0), child: Text(item.price.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
                  Padding(padding: const EdgeInsets.all(8.0), child: Text('${item.vatPercent.toStringAsFixed(0)}%', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
                  Padding(padding: const EdgeInsets.all(8.0), child: Text(totalPr.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
                ],
              );
            }),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Excl. VAT:', style: TextStyle(fontSize: 11)),
                      Text('SAR ${gross.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total VAT:', style: TextStyle(fontSize: 11)),
                      Text('SAR ${vat.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Net Amount:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      Text('SAR ${net.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
  Widget _buildScannerPanel() {
    final bool isWindows = defaultTargetPlatform == TargetPlatform.windows;
    
    return Container(
      height: isWindows ? 120 : 200,
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF10B981), width: 2),
        boxShadow: [
          BoxShadow(color: const Color(0xFF10B981).withOpacity(0.2), blurRadius: 15),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: isWindows 
          ? _buildWindowsScannerSimulator()
          : Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) async {
                    if (_isProcessingScan) return;
                    
                    final List<Barcode> barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final String? code = barcodes.first.rawValue;
                      if (code != null) {
                        setState(() => _isProcessingScan = true);
                        await _showItemSearchDialog(initialBarcode: code);
                        setState(() => _isProcessingScan = false);
                      }
                    }
                  },
                ),
                // Scanning UI Overlay
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                ),
                const Center(
                  child: Icon(Icons.center_focus_strong_rounded, color: Colors.white54, size: 40),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('ACTIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildWindowsScannerSimulator() {
    final TextEditingController simulatorController = TextEditingController();
    return Container(
      color: const Color(0xFF18181B),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('WINDOWS SCANNER SIMULATOR', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: simulatorController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Enter barcode...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white10,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (val) async {
                    if (val.trim().isNotEmpty && !_isProcessingScan) {
                      setState(() => _isProcessingScan = true);
                      await _showItemSearchDialog(initialBarcode: val.trim());
                      setState(() => _isProcessingScan = false);
                      simulatorController.clear();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () async {
                  final val = simulatorController.text.trim();
                  if (val.isNotEmpty && !_isProcessingScan) {
                    setState(() => _isProcessingScan = true);
                    await _showItemSearchDialog(initialBarcode: val);
                    setState(() => _isProcessingScan = false);
                    simulatorController.clear();
                  }
                },
                icon: const Icon(Icons.send_rounded, color: Color(0xFF10B981)),
                style: IconButton.styleFrom(backgroundColor: Colors.white10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class InvoiceItem {
  final String code;
  final String description;
  final int qty;
  final double price;
  final double vatPercent;

  InvoiceItem({
    required this.code,
    required this.description,
    required this.qty,
    required this.price,
    required this.vatPercent,
  });

  double get total => qty * price;
}

class _ScannerBorder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BorderPainter(),
      child: Container(),
    );
  }
}

class _BorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4F46E5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    const double lineLength = 24;

    // Top Left
    canvas.drawLine(const Offset(0, 0), const Offset(lineLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, lineLength), paint);

    // Top Right
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - lineLength, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, lineLength), paint);

    // Bottom Left
    canvas.drawLine(Offset(0, size.height), Offset(lineLength, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - lineLength), paint);

    // Bottom Right
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - lineLength, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - lineLength), paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _ScanningLineAnimation extends StatefulWidget {
  const _ScanningLineAnimation();

  @override
  State<_ScanningLineAnimation> createState() => _ScanningLineAnimationState();
}

class _ScanningLineAnimationState extends State<_ScanningLineAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 10, end: 250).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Positioned(
          top: _animation.value,
          left: 10,
          right: 10,
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withOpacity(0.8),
                  blurRadius: 4,
                  spreadRadius: 2,
                )
              ],
            ),
          ),
        );
      },
    );
  }
}

