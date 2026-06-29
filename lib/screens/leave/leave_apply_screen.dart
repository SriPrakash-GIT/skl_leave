import 'package:git_leave/utils/global_variables.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';        


class LeaveApplyPage extends StatefulWidget {
  const LeaveApplyPage({super.key});

  @override
  State<LeaveApplyPage> createState() => _LeaveApplyPageState();
}

class _LeaveApplyPageState extends State<LeaveApplyPage> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  String _leaveType = 'Casual Leave';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _isLoading = false;
  bool _isHalfDay = false;

  final List<String> _leaveTypes = [
    'Casual Leave',
    'Sick Leave',
    'Earned Leave',
    'Maternity Leave',
    'Loss of Pay',
    'Compensatory Off',
  ];

  int get _totalDays {
    if (_fromDate == null || _toDate == null) return 0;
    if (_isHalfDay) return 1; // visually show 0.5 but store as 1
    return _toDate!.difference(_fromDate!).inDays + 1;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: Colors.blue.shade800,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
          if (_toDate != null && _toDate!.isBefore(_fromDate!)) {
            _toDate = _fromDate;
          }
        } else {
          _toDate = picked;
        }
      });
    }
  }

  Future<void> _submitLeave() async {
  if (!_formKey.currentState!.validate()) return;
  if (_fromDate == null || _toDate == null) {
    Fluttertoast.showToast(
      msg: "Please select leave dates",
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    // Create a new doc reference (auto-generated ID)
    final leaveRef = FirebaseFirestore.instance.collection('leaves').doc();

    await leaveRef.set({
      'LEAVE_ID':    leaveRef.id,
      'IDCARDNO':    globalIDcardNo,
      'LEAVE_TYPE':  _leaveType,
      'FROM_DATE':   _fromDate!.toIso8601String().split('T').first,
      'TO_DATE':     _toDate!.toIso8601String().split('T').first,
      'TOTAL_DAYS':  _isHalfDay ? '0.5' : _totalDays.toString(),
      'IS_HALF_DAY': _isHalfDay ? '1' : '0',
      'REASON':      _reasonController.text.trim(),
      'STATUS':      'Pending',
      'ADMIN_REMARKS': '',
      'CREATED_AT':  FieldValue.serverTimestamp(),
      'UPDATED_AT':  FieldValue.serverTimestamp(),
    });

    Fluttertoast.showToast(
      msg: "Leave applied successfully!",
      backgroundColor: Colors.green,
      textColor: Colors.white,
      toastLength: Toast.LENGTH_LONG,
    );

    // Reset form
    _formKey.currentState!.reset();
    setState(() {
      _fromDate  = null;
      _toDate    = null;
      _isHalfDay = false;
      _leaveType = 'Casual Leave';
      _reasonController.clear();
    });

  } on FirebaseException catch (e) {
    debugPrint("Firestore error: ${e.code} - ${e.message}");
    Fluttertoast.showToast(
      msg: "Database error: ${e.message}",
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
  } catch (e) {
    debugPrint("Unexpected error: $e");
    Fluttertoast.showToast(
      msg: "Error: ${e.toString()}",
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  String _fmt(DateTime? d) =>
      d == null ? 'Select Date' : '${d.day}/${d.month}/${d.year}';

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          'Apply Leave',
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade800, Colors.green.shade400],
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Summary card
              if (_fromDate != null && _toDate != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade700, Colors.blue.shade900],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _summaryItem('Leave Type', _leaveType.split(' ').first),
                      _summaryItem(
                          'Duration',
                          _isHalfDay
                              ? '0.5 Day'
                              : '$_totalDays Day${_totalDays > 1 ? 's' : ''}'),
                      _summaryItem('Status', 'Pending'),
                    ],
                  ),
                ),

              _sectionCard(
                title: 'Leave Details',
                icon: Icons.event_note,
                children: [
                  // Leave type dropdown
                  DropdownButtonFormField<String>(
                    value: _leaveType,
                    decoration: _inputDecoration('Leave Type', Icons.category),
                    items: _leaveTypes
                        .map((t) =>
                            DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _leaveType = v!),
                  ),
                  const SizedBox(height: 14),

                  // Half day toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Half Day',
                        style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: Text('Apply for half day leave',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.grey)),
                    value: _isHalfDay,
                    activeColor: Colors.blue.shade800,
                    onChanged: (v) {
                      setState(() {
                        _isHalfDay = v;
                        if (v && _fromDate != null) _toDate = _fromDate;
                      });
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Date pickers
                  Row(
                    children: [
                      Expanded(
                        child: _dateTile(
                          label: 'From Date',
                          value: _fmt(_fromDate),
                          icon: Icons.calendar_today,
                          onTap: () => _pickDate(isFrom: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _dateTile(
                          label: 'To Date',
                          value: _fmt(_toDate),
                          icon: Icons.calendar_month,
                          onTap: _isHalfDay
                              ? null
                              : () => _pickDate(isFrom: false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              _sectionCard(
                title: 'Reason',
                icon: Icons.message_outlined,
                children: [
                  TextFormField(
                    controller: _reasonController,
                    maxLines: 4,
                    decoration: _inputDecoration(
                        'Explain your reason for leave...', Icons.edit_note),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Please provide a reason'
                            : null,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _isLoading ? null : _submitLeave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade800,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(
                  _isLoading ? 'Submitting...' : 'Submit Leave Request',
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
      ],
    );
  }

  Widget _sectionCard(
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: Colors.blue.shade800, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _dateTile(
      {required String label,
      required String value,
      required IconData icon,
      VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: onTap == null
              ? Colors.grey.shade100
              : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: onTap == null
                ? Colors.grey.shade300
                : Colors.blue.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Row(children: [
              Icon(icon, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text(value,
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.blue.shade700),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue.shade800, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }
}
