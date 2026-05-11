import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'invoice_detail_page.dart';
import 'config.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String get baseUrl => AppConfig.baseUrl;
  List<dynamic> _historyInvoices = [];
  List<dynamic> _filteredInvoices = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/sales/history'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _historyInvoices = data;
          _filteredInvoices = data;
        });
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filterInvoices(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredInvoices = _historyInvoices;
      });
      return;
    }
    final lowercaseQuery = query.toLowerCase();
    setState(() {
      _filteredInvoices = _historyInvoices.where((invoice) {
        final invNo = (invoice['INVOICE_NO'] ?? '').toString().toLowerCase();
        final supplier = (invoice['ENAME'] ?? '').toString().toLowerCase();
        final refNo = (invoice['REF_NO'] ?? '').toString().toLowerCase();
        return invNo.contains(lowercaseQuery) || 
               supplier.contains(lowercaseQuery) || 
               refNo.contains(lowercaseQuery);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            _buildSearchBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))
                  : _filteredInvoices.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          itemCount: _filteredInvoices.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _HistoryInvoiceCard(
                              invoice: _filteredInvoices[index],
                              baseUrl: baseUrl,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          // Back button on the TOP LEFT
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E4E7)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.01),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Color(0xFF18181B)),
                  SizedBox(width: 8),
                  Text(
                    'Back',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF18181B),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          const Text(
            'PURCHASE HISTORY',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: Color(0xFF18181B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4E4E7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: TextFormField(
          controller: _searchController,
          onChanged: _filterInvoices,
          decoration: InputDecoration(
            hintText: 'Search by invoice number, supplier or ref number...',
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4F46E5)),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, color: Color(0xFF71717A)),
                    onPressed: () {
                      _searchController.clear();
                      _filterInvoices('');
                    },
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F4F5),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.receipt_long_rounded, size: 48, color: Colors.grey[400]),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Invoices Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF18181B),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create or save a new supplier invoice to view history.',
            style: TextStyle(color: Color(0xFF71717A)),
          ),
        ],
      ),
    );
  }
}

class _HistoryInvoiceCard extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final String baseUrl;

  const _HistoryInvoiceCard({
    required this.invoice,
    required this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    final String formattedDate = invoice['CURDATE'] != null 
      ? DateFormat('dd MMM yyyy').format(DateTime.parse(invoice['CURDATE']))
      : 'N/A';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFFEEF2FF),
          child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF4F46E5), size: 16),
        ),
        title: Row(
          children: [
            Text(
              'Invoice #${invoice['INVOICE_NO']}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF18181B)),
            ),
            const SizedBox(width: 8),
            if (invoice['REF_NO'] != null && invoice['REF_NO'].toString().isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Ref: ${invoice['REF_NO']}',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                invoice['ENAME'] ?? 'Unknown Supplier',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF4B5563), fontSize: 12),
              ),
              const SizedBox(height: 1),
              Text(
                '$formattedDate • Acc: ${invoice['ACCODE']}',
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF71717A)),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'SAR ${double.parse(invoice['NET_AMOUNT'].toString()).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF4F46E5), fontSize: 14),
                ),
                const SizedBox(height: 2),
                const Text(
                  'View Receipt',
                  style: TextStyle(fontSize: 9.5, color: Color(0xFF71717A), fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF), size: 18),
          ],
        ),
        onTap: () async {
          final result = await Navigator.push<Map<String, dynamic>>(
            context,
            MaterialPageRoute(
              builder: (context) => InvoiceDetailPage(
                invoice: invoice,
                baseUrl: baseUrl,
              ),
            ),
          );
          if (result != null && context.mounted) {
            Navigator.pop(context, result);
          }
        },
      ),
    );
  }
}
