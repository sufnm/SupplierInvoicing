import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class InvoiceDetailPage extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final String baseUrl;

  const InvoiceDetailPage({
    super.key,
    required this.invoice,
    required this.baseUrl,
  });

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  List<dynamic> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('${widget.baseUrl}/api/sales/history/${widget.invoice['INVOICE_NO']}'));
      if (response.statusCode == 200) {
        setState(() {
          _items = json.decode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Error fetching history items: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String formattedDate = widget.invoice['CURDATE'] != null 
        ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(widget.invoice['CURDATE']))
        : 'N/A';
    final double netAmount = double.parse(widget.invoice['NET_AMOUNT']?.toString() ?? '0.0');

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 750),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildInvoiceDocument(formattedDate, netAmount),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE4E4E7)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.01),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                )
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: Color(0xFF18181B)),
                SizedBox(width: 6),
                Text(
                  'Back to History',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF18181B),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Text(
          'INVOICE DETAIL',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: Colors.indigo[700],
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceDocument(String formattedDate, double netAmount) {
    final String reference = (widget.invoice['REF_NO'] != null && widget.invoice['REF_NO'].toString().isNotEmpty)
        ? widget.invoice['REF_NO'].toString()
        : 'N/A';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stripe Top Accent
          Container(
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF4F46E5),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Overview Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Purchase Invoice',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF18181B)),
                    ),
                    Text(
                      '#${widget.invoice['INVOICE_NO']}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFF4F4F5)),
                const SizedBox(height: 16),

                // SUPPLIER, REFERENCE, DATE
                LayoutBuilder(
                  builder: (context, constraints) {
                    bool isNarrow = constraints.maxWidth < 550;
                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMetaField(
                            icon: Icons.business_rounded,
                            label: 'SUPPLIER',
                            value: widget.invoice['ENAME'] ?? 'Unknown Supplier',
                            subValue: 'Acc Code: ${widget.invoice['ACCODE']}',
                          ),
                          const SizedBox(height: 12),
                          _buildMetaField(
                            icon: Icons.tag_rounded,
                            label: 'REFERENCE',
                            value: reference,
                          ),
                          const SizedBox(height: 12),
                          _buildMetaField(
                            icon: Icons.calendar_month_rounded,
                            label: 'DATE',
                            value: formattedDate,
                          ),
                        ],
                      );
                    } else {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildMetaField(
                              icon: Icons.business_rounded,
                              label: 'SUPPLIER',
                              value: widget.invoice['ENAME'] ?? 'Unknown Supplier',
                              subValue: 'Acc Code: ${widget.invoice['ACCODE']}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetaField(
                              icon: Icons.tag_rounded,
                              label: 'REFERENCE',
                              value: reference,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetaField(
                              icon: Icons.calendar_month_rounded,
                              label: 'DATE',
                              value: formattedDate,
                            ),
                          ),
                        ],
                      );
                    }
                  }
                ),
                const SizedBox(height: 20),
                const Divider(height: 1, color: Color(0xFFF4F4F5)),
                const SizedBox(height: 20),

                // ITEMS AND DETAILS Section
                const Text(
                  'ITEMS AND DETAILS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Color(0xFF71717A),
                  ),
                ),
                const SizedBox(height: 16),

                // Items Column Headers
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: Text('ITEM DESCRIPTION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF71717A)))),
                      Expanded(child: Text('QTY', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF71717A)))),
                      Expanded(flex: 2, child: Text('PRICE', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF71717A)))),
                      Expanded(flex: 2, child: Text('TOTAL', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF71717A)))),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFF4F4F5)),
                const SizedBox(height: 10),

                // Items List
                _isLoading
                    ? const Center(child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
                      ))
                    : _items.isEmpty
                        ? const Center(child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text('No items listed in this invoice', style: TextStyle(color: Color(0xFF71717A), fontSize: 12)),
                          ))
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _items.length,
                            separatorBuilder: (context, index) => const Divider(height: 12, color: Color(0xFFF4F4F5)),
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              final double price = double.parse(item['price']?.toString() ?? '0.0');
                              final double total = double.parse(item['TOTAL']?.toString() ?? '0.0');
                              final rawUnit = item['UNIT']?.toString() ?? 'PCS';
                              final String unitString = RegExp(r'^\d+$').hasMatch(rawUnit.trim()) ? 'PCS' : rawUnit;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 4,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['DESCRIPTION'] ?? 'N/A',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF18181B)),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Barcode: ${item['BARCODE']}',
                                            style: const TextStyle(color: Color(0xFF71717A), fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        '${item['QTY']} $unitString',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF18181B)),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'SAR ${price.toStringAsFixed(2)}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11.5, color: Color(0xFF18181B)),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'SAR ${total.toStringAsFixed(2)}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF18181B)),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                const SizedBox(height: 20),
                const Divider(height: 1, color: Color(0xFFF4F4F5)),
                const SizedBox(height: 20),

                // NET TOTAL
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'NET TOTAL',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF18181B), letterSpacing: 0.5),
                    ),
                    Text(
                      'SAR ${netAmount.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF4F46E5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaField({
    required IconData icon,
    required String label,
    required String value,
    String? subValue,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF4F46E5)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF71717A), letterSpacing: 0.5),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF18181B)),
              ),
              if (subValue != null) ...[
                const SizedBox(height: 1),
                Text(
                  subValue,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF71717A)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
