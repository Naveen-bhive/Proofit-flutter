import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/customer_model.dart';
import '../../../shared/services/review_service.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import '../controllers/owner_controller.dart';
import '../../../shared/permissions/app_permissions.dart';
import '../../../shared/permissions/permission_session.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(ownerControllerProvider.notifier).loadCustomers());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String? _validatePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final phone = digits.length == 12 && digits.startsWith('91')
        ? digits.substring(2)
        : digits;
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      return 'Enter a valid 10-digit Indian mobile number';
    }
    return null;
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length == 12 && digits.startsWith('91')
        ? digits.substring(2)
        : digits;
  }

  InputDecoration _iconDecoration(IconData icon, String hint, {String? chip}) => InputDecoration(
    hintText: hint,
    fillColor: AppColors.white,
    prefixIcon: Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: AppColors.border))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 20, color: AppColors.silver),
      ]),
    ),
    prefix: chip == null
        ? null
        : Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AppColors.dark4, borderRadius: BorderRadius.circular(6)),
            child: Text(chip, style: const TextStyle(color: AppColors.light, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
  );

  void _showAddEdit({CustomerModel? customer}) {
    final nameCtrl = TextEditingController(text: customer?.name ?? '');
    final phoneCtrl = TextEditingController(text: customer?.phone ?? '');
    final addrCtrl = TextEditingController(text: customer?.address ?? '');
    final cityCtrl = TextEditingController(text: customer?.city ?? '');
    final notesCtrl = TextEditingController(text: customer?.notes ?? '');
    final isEdit = customer != null;
    String? formError;

    Future<void> submit(BuildContext sheetCtx, StateSetter setSheet) async {
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
              cityCtrl.text.trim(),
              notesCtrl.text.trim(),
            );
      } else {
        final id = await ref.read(ownerControllerProvider.notifier).addCustomer(
              name,
              phone,
              addrCtrl.text.trim(),
              cityCtrl.text.trim(),
              notesCtrl.text.trim(),
            );
        if (id == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Customer limit reached. Upgrade your plan.'),
              backgroundColor: AppColors.red));
        } else if (id != null) {
          ReviewService.maybePromptAfterSuccess();
        }
      }
    }

    AppSheet.show(
      context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: AppSheet(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                title: isEdit ? 'Edit Customer' : 'Add Customer',
                subtitle: isEdit ? 'Update details for ProofIt records' : 'Add a new client record to your directory',
                headerAction: isEdit && ref.read(permissionSessionProvider).can(AppPermissions.customersDelete)
                    ? GestureDetector(
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          _confirmDelete(customer);
                        },
                        child: const IconTile(icon: Icons.delete_outline_rounded, color: AppColors.red, size: 40, iconSize: 21),
                      )
                    : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Divider(height: 1, color: AppColors.borderSoft),
                  const SizedBox(height: 18),
                  const FieldLabel('Customer Name', required: true, caps: true),
                  TextFormField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w500),
                    decoration: _iconDecoration(Icons.person_outline_rounded, 'e.g. Acme Logistics or John Doe'),
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel('Phone Number', required: true, caps: true),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w500),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: _iconDecoration(Icons.phone_outlined, '10-digit mobile number', chip: '+91'),
                  ),
                  if (formError != null) ...[
                    const SizedBox(height: 10),
                    Text(formError!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
                  ],
                  const SizedBox(height: 16),
                  const FieldLabel('Address', caps: true),
                  TextFormField(
                    controller: addrCtrl,
                    style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w500),
                    decoration: _iconDecoration(Icons.location_on_outlined, 'Street, area'),
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel('City', caps: true),
                  TextFormField(
                    controller: cityCtrl,
                    style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w500),
                    decoration: _iconDecoration(Icons.apartment_rounded, 'City'),
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel('Notes', caps: true, hint: 'Optional'),
                  TextFormField(
                    controller: notesCtrl,
                    style: const TextStyle(color: AppColors.text),
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      fillColor: AppColors.white,
                      hintText: 'Add internal notes about this customer...',
                    ),
                  ),
                ]),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 12 + MediaQuery.of(ctx).padding.bottom),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderSoft))),
              child: PrimaryButton(
                label: isEdit ? 'Save Changes' : 'Add Customer',
                icon: isEdit ? Icons.check_rounded : Icons.add_rounded,
                onPressed: () => submit(sheetCtx, setSheet),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(CustomerModel customer) async {
    final ok = await showConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Delete Customer',
      message: '',
      confirmLabel: 'Delete',
      detail: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.dark3,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(
            child: Text('${customer.name} · ${customer.phone}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.light, fontSize: 12.5, fontWeight: FontWeight.w500)),
          ),
        ]),
      ),
      richMessage: TextSpan(children: [
        const TextSpan(text: 'Are you sure you want to delete '),
        TextSpan(text: customer.name, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
        const TextSpan(text: '? This action cannot be undone and will permanently remove all linked records.'),
      ]),
    );
    if (ok) {
      await ref
          .read(ownerControllerProvider.notifier)
          .deleteCustomer(customer.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Customer deleted'),
            backgroundColor: AppColors.green));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    final customers = state.customers;
    final limit = state.customerLimit;
    final countText = limit == -1 ? 'Active (${customers.length})' : 'Active (${customers.length}/$limit)';
    final searching = _searchCtrl.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          PageHeader(
            title: 'Customers',
            actions: [
              if (ref.watch(permissionSessionProvider).can(AppPermissions.customersCreate))
                RoundAddButton(onTap: () => _showAddEdit(), size: 42),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: SearchBox(
              controller: _searchCtrl,
              hint: 'Search customers...',
              trailing: searching
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.muted, size: 20),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                        ref.read(ownerControllerProvider.notifier).loadCustomers();
                      })
                  : null,
              onChanged: (v) {
                setState(() {});
                ref.read(ownerControllerProvider.notifier).loadCustomers(search: v.trim());
              },
            ),
          ),
          if (customers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(children: [
                Text('REGISTERED DIRECTORY', style: AppTextStyles.label.copyWith(fontSize: 11.5)),
                const Spacer(),
                Text(countText, style: const TextStyle(color: AppColors.brand, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
            ),
          Expanded(
            child: state.isLoading
                ? const StaffListShimmer()
                : customers.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 110),
                        SoftEmptyState(
                          icon: Icons.groups_outlined,
                          title: searching ? 'No matches' : 'No customers yet',
                          subtitle: searching
                              ? 'Try a different name or phone number.'
                              : 'Add your first customer to start assigning jobs and managing client details.',
                        ),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: customers.length,
                        itemBuilder: (_, i) => _customerCard(customers[i]),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _customerCard(CustomerModel c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        radius: 18,
        padding: const EdgeInsets.all(16),
        onTap: ref.read(permissionSessionProvider).can(AppPermissions.customersEdit)
            ? () => _showAddEdit(customer: c)
            : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.brandBorder),
            ),
            child: Center(
              child: Text(c.initials,
                  style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700, fontSize: 17)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.h3.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.phone_outlined, size: 14, color: AppColors.muted),
                const SizedBox(width: 5),
                Text(c.phone, style: const TextStyle(color: AppColors.light, fontSize: 13)),
              ]),
              if (c.displayAddress.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: AppColors.muted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(c.displayAddress, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.silver, fontSize: 12.5)),
                  ),
                ]),
              ],
            ]),
          ),
          const Icon(Icons.edit_outlined, color: AppColors.muted, size: 19),
        ]),
      ),
    );
  }
}
