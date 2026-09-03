import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';

class EnterpriseRequestScreen extends ConsumerStatefulWidget {
  const EnterpriseRequestScreen({super.key});
  @override ConsumerState<EnterpriseRequestScreen> createState() => _EnterpriseRequestScreenState();
}

class _EnterpriseRequestScreenState extends ConsumerState<EnterpriseRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _company = TextEditingController(), _contact = TextEditingController(), _email = TextEditingController(), _phone = TextEditingController(), _country = TextEditingController(), _staff = TextEditingController(), _users = TextEditingController(), _requirements = TextEditingController(), _features = TextEditingController(), _message = TextEditingController();
  String _billing = 'monthly'; bool _loading = true, _submitting = false; Map<String, dynamic>? _request;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final res = await ref.read(apiServiceProvider).get('/enterprise-requests/mine'); if (res.data['success'] == true && res.data['data'] != null) _request = Map<String, dynamic>.from(res.data['data']); } catch (_) {} if (mounted) setState(() => _loading = false); }
  @override void dispose() { for (final c in [_company,_contact,_email,_phone,_country,_staff,_users,_requirements,_features,_message]) { c.dispose(); } super.dispose(); }
  Future<void> _submit() async { if (!_formKey.currentState!.validate()) return; setState(() => _submitting = true); try { final res = await ref.read(apiServiceProvider).post('/enterprise-requests', data: {'organisationName': _company.text.trim(), 'contactName': _contact.text.trim(), 'email': _email.text.trim(), 'phone': _phone.text.trim(), 'country': _country.text.trim(), 'requiredStaffCount': int.parse(_staff.text), 'expectedUsers': int.parse(_users.text), 'businessRequirements': _requirements.text.trim(), 'requiredFeatures': _features.text.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList(), 'preferredBillingCycle': _billing, 'additionalMessage': _message.text.trim()}); if (res.data['success'] == true) { setState(() => _request = Map<String,dynamic>.from(res.data['data'])); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your enterprise plan request has been submitted. Our team will review it and contact you shortly.'), backgroundColor: AppColors.green)); } } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit request: $e'), backgroundColor: AppColors.red)); } finally { if (mounted) setState(() => _submitting = false); } }
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.dark, appBar: AppBar(title: const Text('Request Enterprise Plan')), body: _loading ? const Center(child: CircularProgressIndicator(color: AppColors.brand)) : _request != null ? _status() : Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(16), children: [const Text('Tell us about your organisation and requirements. Our team will prepare a custom plan.', style: TextStyle(color: AppColors.silver, height: 1.4)), const SizedBox(height: 20), ...[_field(_company,'Organisation/company name', minLength: 2),_field(_contact,'Contact person name', minLength: 2),_field(_email,'Email', email: true),_field(_phone,'Phone number', phone: true),_field(_country,'Country/location', minLength: 2),_field(_staff,'Required staff count', number: true),_field(_users,'Expected number of users', number: true),_field(_requirements,'Business requirements', minLength: 10, lines: 3),_field(_features,'Required features (comma separated)', minLength: 2),DropdownButtonFormField(value: _billing, dropdownColor: AppColors.dark2, style: const TextStyle(color: AppColors.white), decoration: const InputDecoration(labelText: 'Preferred billing cycle'), items: const [DropdownMenuItem(value: 'monthly', child: Text('Monthly')),DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),DropdownMenuItem(value: 'yearly', child: Text('Yearly')),DropdownMenuItem(value: 'custom', child: Text('Custom'))], onChanged: (v) => setState(() => _billing = v!)),_field(_message,'Additional message', required: false, lines: 3)], const SizedBox(height: 24), ElevatedButton(onPressed: _submitting ? null : _submit, style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand, minimumSize: const Size.fromHeight(52)), child: Text(_submitting ? 'Submitting…' : 'Submit Enterprise Request')), const SizedBox(height: 32)]))); 
  Widget _field(TextEditingController c, String label, {bool required = true, bool number = false, bool email = false, bool phone = false, int minLength = 2, int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      maxLines: lines,
      keyboardType: number || phone ? TextInputType.number : email ? TextInputType.emailAddress : TextInputType.text,
      inputFormatters: number || phone ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(phone ? 10 : 6)] : null,
      style: const TextStyle(color: AppColors.white),
      decoration: InputDecoration(labelText: '$label${required ? ' *' : ''}'),
      validator: (v) {
        final value = v?.trim() ?? '';
        if (required && value.isEmpty) return '$label is required';
        if (number && (int.tryParse(value) == null || int.parse(value) < 1)) return 'Enter a whole number of at least 1';
        if (phone && !RegExp(r'^[6-9]\d{9}$').hasMatch(value)) return 'Enter a valid 10-digit Indian mobile number';
        if (email && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) return 'Enter a valid email address';
        if (required && !number && !phone && !email && value.length < minLength) return 'Enter at least $minLength characters';
        return null;
      },
    ),
  );
  Widget _status() { final s = _request!['status']?.toString() ?? 'pending'; final rejected = s == 'rejected'; return Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(rejected ? Icons.cancel_outlined : s == 'active' ? Icons.verified_outlined : Icons.hourglass_top_rounded, color: rejected ? AppColors.red : s == 'active' ? AppColors.green : AppColors.yellow, size: 48), const SizedBox(height: 16), Text(rejected ? 'Request rejected' : s == 'active' ? 'Enterprise plan active' : 'Pending approval', style: const TextStyle(color: AppColors.white, fontSize: 22, fontWeight: FontWeight.w700)), const SizedBox(height: 8), Text(rejected ? (_request!['rejectionReason'] ?? 'Please contact support for more details.') : s == 'active' ? 'Your Enterprise plan is active. View it in Subscription.' : 'Your enterprise plan request has been submitted. Our team will review it and contact you shortly.', style: const TextStyle(color: AppColors.silver, height: 1.4))])); }
}
