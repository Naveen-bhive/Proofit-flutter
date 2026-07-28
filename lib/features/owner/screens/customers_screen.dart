import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/customer_model.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import '../controllers/owner_controller.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(ownerControllerProvider.notifier).loadCustomers());
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  String? _validatePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final phone = digits.length == 12 && digits.startsWith('91') ? digits.substring(2) : digits;
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      return 'Enter a valid 10-digit Indian mobile number';
    }
    return null;
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length == 12 && digits.startsWith('91') ? digits.substring(2) : digits;
  }

  void _showAddEdit({CustomerModel? customer}) {
    final nameCtrl  = TextEditingController(text: customer?.name  ?? '');
    final phoneCtrl = TextEditingController(text: customer?.phone ?? '');
    final addrCtrl  = TextEditingController(text: customer?.address ?? '');
    final cityCtrl  = TextEditingController(text: customer?.city  ?? '');
    final notesCtrl = TextEditingController(text: customer?.notes ?? '');
    final isEdit    = customer != null;
    String? formError;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: AppColors.dark2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(isEdit ? 'Edit Customer' : 'Add Customer',
              style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (isEdit) IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
              onPressed: () { Navigator.pop(sheetCtx); _confirmDelete(customer); }),
          ]),
          const SizedBox(height: 16),
          TextFormField(controller: nameCtrl, style: const TextStyle(color: AppColors.white),
            decoration: const InputDecoration(labelText: 'Customer Name *', prefixIcon: Icon(Icons.person_outline, color: AppColors.muted))),
          const SizedBox(height: 12),
          TextFormField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: AppColors.white),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: const InputDecoration(
              labelText: 'Phone Number *',
              hintText: '10-digit mobile number',
              prefixText: '+91 ',
              prefixStyle: TextStyle(color: AppColors.silver),
            ),
          ),
          if (formError != null) ...[
            const SizedBox(height: 12),
            Text(formError!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          TextFormField(controller: addrCtrl, style: const TextStyle(color: AppColors.white),
            decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.muted))),
          const SizedBox(height: 12),
          TextFormField(controller: cityCtrl, style: const TextStyle(color: AppColors.white),
            decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.location_city_outlined, color: AppColors.muted))),
          const SizedBox(height: 12),
          TextFormField(controller: notesCtrl, style: const TextStyle(color: AppColors.white), maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)')),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final phoneErr = _validatePhone(phoneCtrl.text);
              if (name.isEmpty) {
                setSheet(() => formError = 'Customer name is required');
                return;
              }
              if (phoneErr != null) {
                setSheet(() => formError = phoneErr);
                return;
              }
              final phone = _normalizePhone(phoneCtrl.text);
              Navigator.pop(sheetCtx);
              if (isEdit) {
                await ref.read(ownerControllerProvider.notifier).editCustomer(
                  customer.id,
                  name,
                  phone,
                  addrCtrl.text.trim(),
                  notesCtrl.text.trim(),
                );
              } else {
                final id = await ref.read(ownerControllerProvider.notifier).addCustomer(
                  name,
                  phone,
                  addrCtrl.text.trim(),
                  notesCtrl.text.trim(),
                );
                if (id == null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Customer limit reached. Upgrade your plan.'),
                    backgroundColor: AppColors.red));
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(isEdit ? 'Save Changes' : 'Add Customer',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
          const SizedBox(height: 20),
        ]),
      )),
    );
  }

  Future<void> _confirmDelete(CustomerModel customer) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.dark2,
      title: const Text('Delete Customer', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
      content: Text('Delete ${customer.name}? This cannot be undone.', style: const TextStyle(color: AppColors.silver)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: AppColors.silver))),
        TextButton(onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700))),
      ]));
    if (ok == true) {
      await ref.read(ownerControllerProvider.notifier).deleteCustomer(customer.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer deleted'), backgroundColor: AppColors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state       = ref.watch(ownerControllerProvider);
    final customers   = state.customers;
    final limit       = state.customerLimit;
    final limitText   = limit == -1 ? 'Unlimited' : '${customers.length}/$limit';

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 8),
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(100)),
              child: Text(limitText, style: const TextStyle(color: AppColors.brand, fontSize: 12, fontWeight: FontWeight.w700))))),
          IconButton(icon: const Icon(Icons.person_add_outlined, color: AppColors.brand), onPressed: () => _showAddEdit()),
        ],
      ),
      body: Column(children: [
        // Search
        Padding(padding: const EdgeInsets.all(16), child: TextFormField(
          controller: _searchCtrl,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            hintText: 'Search customers...',
            prefixIcon: const Icon(Icons.search_outlined, color: AppColors.muted),
            suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear, color: AppColors.muted), onPressed: () { _searchCtrl.clear(); setState(() {}); ref.read(ownerControllerProvider.notifier).loadCustomers(); })
              : null),
          onChanged: (v) {
            setState(() {});
          })),

        // List
        Expanded(child: state.isLoading
          ? const StaffListShimmer()
          : customers.isEmpty
            ? EmptyState(type: EmptyType.staff, title: 'No customers yet',
                subtitle: 'Add your first customer to start assigning jobs',
                actionLabel: 'Add Customer', onAction: () => _showAddEdit())
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: customers.length,
                itemBuilder: (_, i) {
                  final c = customers[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                    child: Material(
                      color: AppColors.dark2,
                      child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(radius: 22, backgroundColor: AppColors.brand.withValues(alpha: 0.15),
                        child: Text(c.initials, style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700, fontSize: 16))),
                      title: Text(c.name, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.phone, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                        if (c.displayAddress.isNotEmpty)
                          Text(c.displayAddress, style: const TextStyle(color: AppColors.muted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                      trailing: const Icon(Icons.edit_outlined, color: AppColors.muted, size: 20),
                      onTap: () => _showAddEdit(customer: c),
                    ),
                    ),
                  );
                })),
      ]),
    );
  }
}