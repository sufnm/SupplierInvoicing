import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'history_page.dart';

void main() {
  runApp(const SupplierInvoiceApp());
}

class SupplierInvoiceApp extends StatelessWidget {
  const SupplierInvoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Supplier Invoice',
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
      home: const InvoiceDashboard(),
    );
  }
}

class InvoiceDashboard extends StatefulWidget {
  const InvoiceDashboard({super.key});

  @override
  State<InvoiceDashboard> createState() => _InvoiceDashboardState();
}

class _InvoiceDashboardState extends State<InvoiceDashboard> {
  int _activeTab = 0; // 0 for Header, 1 for Items
  
  final TextEditingController _invoiceNoController = TextEditingController();
  final TextEditingController _supplierController = TextEditingController();
  final TextEditingController _itemSearchController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  List<dynamic> _searchResults = [];
  List<dynamic> _supplierResults = [];
  Map<String, dynamic>? _selectedSupplier;
  final List<InvoiceItem> _items = [];
  
  // Cache variables
  List<dynamic> _cachedSuppliers = [];
  List<dynamic> _cachedItems = [];
  bool _isCacheLoaded = false;
  
  // Scanning state
  bool _isScanningMode = false;
  bool _isProcessingScan = false;
  final MobileScannerController _scannerController = MobileScannerController();
  
  static const String baseUrl = 'http://localhost:3005'; // EasyERP Backend

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _invoiceNoController.dispose();
    _supplierController.dispose();
    _itemSearchController.dispose();
    super.dispose();
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
      
      setState(() {
        _isCacheLoaded = true;
      });
    } catch (e) {
      debugPrint('Error loading cache: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _searchItems(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = _cachedItems.take(20).toList());
      return;
    }
    
    final lowercaseQuery = query.toLowerCase();
    setState(() {
      _searchResults = _cachedItems.where((item) {
        final barcode = (item['BARCODE'] ?? '').toString().toLowerCase();
        final desc = (item['DESCRIPTION'] ?? '').toString().toLowerCase();
        return barcode.contains(lowercaseQuery) || desc.contains(lowercaseQuery);
      }).take(50).toList();
    });
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

  Future<void> _saveInvoice() async {
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a supplier first'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item to the invoice'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    double gTotal = _items.fold(0, (sum, item) => sum + item.total);
    
    final payload = {
      "ACCODE": _selectedSupplier!['ACC_NO'].toString(),
      "ENAME": _selectedSupplier!['ACC_NAME'],
      "G_TOTAL": gTotal,
      "DISC_AMT": 0,
      "NET_AMOUNT": gTotal,
      "VAT_AMOUNT": 0, // Assuming VAT is handled in grid or zero for now
      "VAT_NUMBER": "",
      "PAYMENT_METHOD": "Others", // Default for purchase
      "TRN_TYPE": 2, // 2 for Credit Purchase
      "REF_INV_NO": _invoiceNoController.text,
      "ROWS": _items.map((item) => {
        "itemCode": item.code,
        "description": item.description,
        "qty": item.qty,
        "price": item.price,
        "unit": "Pcs",
        "vatPercent": 0,
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
        
        // Show Invoice Preview
        await _showInvoicePreviewDialog(savedInvoiceNo, payload);

        // Clear invoice after save and preview
        setState(() {
          _items.clear();
          _supplierController.clear();
          _selectedSupplier = null;
          _invoiceNoController.clear();
          _activeTab = 0;
        });
      } else {
        throw Exception('Server error: ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save invoice: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showInvoicePreviewDialog(String invoiceNo, Map<String, dynamic> invoiceData) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 500,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Gradient
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF10B981)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('INVOICE SAVED', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          Text('Invoice #$invoiceNo', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('SUPPLIER', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(invoiceData['ENAME'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text('ACC: ${invoiceData['ACCODE']}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('DATE', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(DateFormat('dd MMM yyyy').format(DateTime.now()), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 8),
                            const Text('REFERENCE NO', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(invoiceData['REF_INV_NO'] != null && invoiceData['REF_INV_NO'].toString().isNotEmpty ? invoiceData['REF_INV_NO'] : 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 12),
                    Row(
                      children: const [
                        Expanded(flex: 3, child: Text('ITEM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                        Expanded(child: Text('QTY', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('TOTAL', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: (invoiceData['ROWS'] as List).length,
                        separatorBuilder: (context, index) => const Divider(height: 20, color: Color(0xFFF8FAFC)),
                        itemBuilder: (context, index) {
                          final row = (invoiceData['ROWS'] as List)[index];
                          return Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(row['description'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    Text(row['itemCode'], style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Text(row['qty'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text('SAR ${(row['qty'] * row['price']).toStringAsFixed(2)}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('NET AMOUNT', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
                          Text('SAR ${invoiceData['NET_AMOUNT'].toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Color(0xFF0F172A))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                            child: const Text('Close', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                            ),
                            child: const Text('Confirm & Print', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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

            setState(() {
              _items.add(InvoiceItem(
                code: selectedItem!['BARCODE']?.toString() ?? 'N/A',
                description: description,
                qty: qty,
                price: newPrice,
              ));
            });
            
            Navigator.pop(context);
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Container(
              width: 500,
              height: 580,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 40, offset: const Offset(0, 20)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  children: [
                    // Premium Minimal Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                    color: Colors.indigo[700],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Choose a product',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF18181B),
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
                              padding: const EdgeInsets.all(8),
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
                          : Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Selected Item Info Card
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(16),
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
                                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF1E293B)),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Barcode: ${selectedItem!['BARCODE']}',
                                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, letterSpacing: 0.5),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: _buildPremiumField('Purchase Price', costPriceController, Icons.payments_rounded),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: _buildPremiumField('Quantity', qtyController, Icons.shopping_bag_rounded, autofocus: selectedItem!['IS_NEW'] != true),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: addToList,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF18181B),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        elevation: 0,
                                      ),
                                      child: const Text('Add to Invoice', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Center(
                                    child: TextButton(
                                      onPressed: () => setDialogState(() => selectedItem = null),
                                      child: const Text('Change Item', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 13)),
                                    ),
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
        TextField(
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
        TextField(
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
      ],
    );
  }

  void _addItem() {
    _showItemSearchDialog();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _searchResults = [];
          _supplierResults = [];
        });
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        body: SafeArea(
          child: Column(
            children: [
              _buildCustomAppBar(),
              _buildTabNavigation(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _activeTab == 0 ? _buildHeaderView() : _buildItemsView(),
                ),
              ),
              if (_activeTab == 0) _buildBottomSummary(),
            ],
          ),
        ),
        floatingActionButton: _activeTab == 1 
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: 'scan_button',
                  onPressed: () {
                    setState(() {
                      _isScanningMode = !_isScanningMode;
                      if (_isScanningMode) {
                        _searchResults = []; // Clear other search results when scanning
                      }
                    });
                  },
                  backgroundColor: _isScanningMode ? const Color(0xFF10B981) : const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  child: Icon(_isScanningMode ? Icons.stop_rounded : Icons.qr_code_scanner_rounded),
                ),
                const SizedBox(width: 12),
                FloatingActionButton.extended(
                  heroTag: 'add_button',
                  onPressed: _addItem,
                  label: const Text('Add Item', style: TextStyle(fontWeight: FontWeight.bold)),
                  icon: const Icon(Icons.add_rounded),
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  elevation: 4,
                ),
              ],
            )
          : null,
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SUPPLIER INVOICE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.indigo[700],
                ),
              ),
              const Text(
                'Create New Entry',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF18181B),
                ),
              ),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'history') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HistoryPage()),
                );
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _buildTabItem(0, 'Invoice Header', Icons.receipt_long_rounded),
            _buildTabItem(1, 'Items List', Icons.grid_view_rounded),
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
          padding: const EdgeInsets.symmetric(vertical: 12),
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
              Icon(icon, size: 18, color: isActive ? const Color(0xFF4F46E5) : const Color(0xFF71717A)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
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
          _buildFormSection('General Information', [
            _buildInputField('Reference Number', _invoiceNoController, Icons.tag_rounded),
            const SizedBox(height: 16),
            _buildSupplierSearchField(),
            const SizedBox(height: 16),
            _buildDateField('Invoice Date', _selectedDate, Icons.calendar_today_rounded),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: _buildItemSearchField(),
        ),
        Expanded(
          child: _items.isEmpty 
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    const Text('No items added to invoice', style: TextStyle(color: Color(0xFF71717A))),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: _items.length,
                itemBuilder: (context, index) => _buildItemCard(_items[index]),
              ),
        ),
      ],
    );
  }

  Widget _buildItemCard(InvoiceItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.inventory_2_rounded, color: Color(0xFF4F46E5), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.description, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(item.code, style: const TextStyle(color: Color(0xFF71717A), fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _items.remove(item);
                  });
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildItemDetail('Qty', item.qty.toString()),
              _buildItemDetail('Cost Price', 'SAR ${item.price.toStringAsFixed(2)}'),
              _buildItemDetail('Total', 'SAR ${item.total.toStringAsFixed(2)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemDetail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF71717A), fontSize: 11, fontWeight: FontWeight.w500)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF18181B))),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _supplierController,
                  decoration: InputDecoration(
                    labelText: 'Supplier Name',
                    prefixIcon: const Icon(Icons.business_rounded, size: 20, color: Color(0xFF4F46E5)),
                    hintText: 'Search for supplier...',
                    suffixIcon: _supplierResults.isNotEmpty 
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => setState(() => _supplierResults = []),
                        )
                      : null,
                  ),
                  onTap: () => _searchSuppliers(''),
                  onChanged: _searchSuppliers,
                ),
                if (_supplierResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _supplierResults.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF4F4F5)),
                      itemBuilder: (context, index) {
                        final supplier = _supplierResults[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFEEF2FF),
                            radius: 18,
                            child: Text(
                              (supplier['ACC_NAME'] ?? '?')[0].toUpperCase(),
                              style: const TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          title: Text(
                            supplier['ACC_NAME'] ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Text(
                            'Acc No: ${supplier['ACC_NO']}',
                            style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedSupplier = supplier;
                              _supplierController.text = supplier['ACC_NAME'] ?? '';
                              _supplierResults = [];
                            });
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ],
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
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4F46E5)),
            suffixIcon: _isLoading ? const Padding(
              padding: EdgeInsets.all(12.0),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ) : null,
          ),
          onChanged: _searchItems,
        ),
        if (_searchResults.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE4E4E7)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)],
            ),
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final item = _searchResults[index];
                return ListTile(
                  title: Text(item['DESCRIPTION'] ?? 'No Description'),
                  subtitle: Text('Barcode: ${item['BARCODE']} | Avg Cost: SAR ${item['AVG_PUR_PRICE']}'),
                  trailing: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF4F46E5)),
                  onTap: () {
                    setState(() {
                      _items.add(InvoiceItem(
                        code: item['BARCODE']?.toString() ?? 'N/A',
                        description: item['DESCRIPTION'] ?? 'N/A',
                        qty: 1,
                        price: (item['AVG_PUR_PRICE'] as num?)?.toDouble() ?? 0.0,
                      ));
                      _searchResults = [];
                      _itemSearchController.clear();
                    });
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
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF4F46E5)),
        hintText: 'Enter $label',
      ),
    );
  }

  Widget _buildBottomSummary() {
    double total = _items.fold(0, (sum, item) => sum + item.total);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE4E4E7))),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Total Amount', style: TextStyle(color: Color(0xFF71717A), fontWeight: FontWeight.w500)),
                Text(
                  'SAR ${total.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF4F46E5)),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 140,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveInvoice,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF18181B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Save Invoice'),
            ),
          ),
        ],
      ),
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

  InvoiceItem({
    required this.code,
    required this.description,
    required this.qty,
    required this.price,
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

