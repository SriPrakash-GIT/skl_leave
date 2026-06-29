import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminOnDutyPage extends StatefulWidget {
  const AdminOnDutyPage({super.key});

  @override
  State<AdminOnDutyPage> createState() => _AdminOnDutyPageState();
}

class _AdminOnDutyPageState extends State<AdminOnDutyPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _active = [];
  List<Map<String, dynamic>> _completed = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  String? _error;
  String _currentTab = 'active'; // 'active' | 'completed'
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentTab = _tabController.index == 0 ? 'active' : 'completed';
        _applySearch(_searchController.text);
      });
    });
    _fetchOnDuty();
    _searchController.addListener(() => _applySearch(_searchController.text));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchOnDuty() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('onduty')
          .get();

      final all = snap.docs.map((doc) {
        final d = Map<String, dynamic>.from(doc.data());
        d['OD_ID'] = doc.id;
        return d;
      }).toList();

      // Sort newest first
      all.sort((a, b) {
        DateTime dateA, dateB;
        try { dateA = (a['CREATED_AT'] as Timestamp).toDate(); }
        catch (_) { dateA = DateTime(0); }
        try { dateB = (b['CREATED_AT'] as Timestamp).toDate(); }
        catch (_) { dateB = DateTime(0); }
        return dateB.compareTo(dateA);
      });

      setState(() {
        _active    = all.where((e) => e['ACTIVE'] == 'T').toList();
        _completed = all.where((e) => e['ACTIVE'] != 'T').toList();
        _filtered  = _currentTab == 'active' ? _active : _completed;
      });
    } on FirebaseException catch (e) {
      setState(() => _error = 'Database error: ${e.message}');
    } catch (e) {
      setState(() => _error = 'Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _applySearch(String q) {
    final source = _currentTab == 'active' ? _active : _completed;
    final lower = q.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? source
          : source.where((e) =>
              (e['IDCARDNO'] ?? '').toString().toLowerCase().contains(lower) ||
              (e['SITE_NAME'] ?? '').toString().toLowerCase().contains(lower) ||
              (e['PURPOSE'] ?? '').toString().toLowerCase().contains(lower))
              .toList();
    });
  }

  Future<void> _cancelOnDuty(Map<String, dynamic> od) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel On Duty'),
        content: Text(
            'Cancel on duty for ${od['IDCARDNO']} at ${od['SITE_NAME']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('onduty')
          .doc(od['OD_ID'])
          .update({
        'STATUS': 'Cancelled',
        'ACTIVE': 'F',
        'REJECT': 'Y',
        'UPDATED_AT': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('On Duty cancelled'),
            backgroundColor: Colors.orange),
      );
      _fetchOnDuty();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showDetail(Map<String, dynamic> od) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              // Header
              Row(children: [
                CircleAvatar(
                  backgroundColor: Colors.teal.shade50,
                  radius: 26,
                  child: Icon(Icons.work, color: Colors.teal.shade700, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(od['SITE_NAME'] ?? 'On Duty',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('ID: ${od['IDCARDNO'] ?? ''}',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.grey)),
                    ]),
                ),
                _statusChip(od['STATUS'] ?? 'Active'),
              ]),
              const SizedBox(height: 20),
              _detailRow(Icons.calendar_today, 'Date', od['PDATE'] ?? ''),
              _detailRow(Icons.task_alt, 'Purpose', od['PURPOSE'] ?? ''),
              _detailRow(Icons.place, 'Start Address', od['START_ADDR'] ?? ''),
              _detailRow(Icons.flag, 'End Address', od['END_ADDR'] ?? '-'),
              _detailRow(Icons.straighten, 'Distance',
                  '${((double.tryParse(od['DISTANCE']?.toString() ?? '0') ?? 0) / 1000).toStringAsFixed(2)} km'),
              _detailRow(Icons.timer, 'Duration',
                  _formatDuration(int.tryParse(od['DURATION']?.toString() ?? '0') ?? 0)),
              if ((od['REMARKS'] ?? '').toString().isNotEmpty)
                _detailRow(Icons.notes, 'Remarks', od['REMARKS']),
              const SizedBox(height: 20),
              if (od['ACTIVE'] == 'T')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _cancelOnDuty(od);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.cancel, color: Colors.white),
                    label: Text('Cancel On Duty',
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: Colors.teal.shade600),
        const SizedBox(width: 10),
        SizedBox(width: 90,
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey.shade600))),
        Expanded(
            child: Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text('On Duty Monitor',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade700, Colors.green.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _fetchOnDuty),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(text: 'Active (${_active.length})'),
            Tab(text: 'Completed (${_completed.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off, size: 60, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: GoogleFonts.poppins(color: Colors.grey)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _fetchOnDuty,
                          child: const Text('Retry')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Stats row
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(children: [
                        _miniStat('Active', '${_active.length}', Colors.teal),
                        const SizedBox(width: 8),
                        _miniStat('Completed', '${_completed.length}',
                            Colors.green),
                        const SizedBox(width: 8),
                        _miniStat('Total',
                            '${_active.length + _completed.length}',
                            Colors.indigo),
                      ]),
                    ),
                    // Search
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by ID, site or purpose...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        ),
                      ),
                    ),
                    // List
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _fetchOnDuty,
                        child: _filtered.isEmpty
                            ? Center(
                                child: Text('No records found',
                                    style: GoogleFonts.poppins(
                                        color: Colors.grey)))
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                itemCount: _filtered.length,
                                itemBuilder: (context, i) {
                                  final od = _filtered[i];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    elevation: 3,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    child: InkWell(
                                      onTap: () => _showDetail(od),
                                      borderRadius: BorderRadius.circular(14),
                                      child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Row(children: [
                                          CircleAvatar(
                                            backgroundColor:
                                                Colors.teal.shade50,
                                            child: Icon(Icons.work,
                                                color: Colors.teal.shade600,
                                                size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                    od['SITE_NAME'] ??
                                                        'On Duty',
                                                    style: GoogleFonts.poppins(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13)),
                                                Text(
                                                    'ID: ${od['IDCARDNO'] ?? ''} • ${od['PDATE'] ?? ''}',
                                                    style: GoogleFonts.poppins(
                                                        fontSize: 11,
                                                        color: Colors.grey)),
                                                Text(
                                                    od['PURPOSE'] ?? '',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: GoogleFonts.poppins(
                                                        fontSize: 11,
                                                        color: Colors.grey
                                                            .shade600)),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              _statusChip(
                                                  od['STATUS'] ?? 'Active'),
                                              const SizedBox(height: 4),
                                              Text(
                                                _formatDuration(int.tryParse(
                                                        od['DURATION']
                                                                ?.toString() ??
                                                            '0') ??
                                                    0),
                                                style: GoogleFonts.poppins(
                                                    fontSize: 11,
                                                    color:
                                                        Colors.teal.shade700,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.chevron_right,
                                              color: Colors.grey),
                                        ]),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.2))),
        child: Column(children: [
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style:
                  GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade600)),
        ]),
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'active': color = Colors.teal; break;
      case 'completed': color = Colors.green; break;
      case 'cancelled': color = Colors.red; break;
      default: color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Text(status,
          style: GoogleFonts.poppins(
              fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds == 0) return '--';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}