import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../widgets/ui_kit.dart';
import 'app_permissions.dart';

/// Grouped, per-action permission picker.
///
/// [grantable] limits what can be toggled (a delegating staff member may only
/// grant what they hold); other actions are shown locked. Turning an action on
/// also turns on its prerequisites, and turning one off clears what depends on it.
class PermissionEditor extends StatelessWidget {
  final Set<String> selected;
  final Set<String> grantable;
  final ValueChanged<Set<String>> onChanged;
  final bool Function(String feature) featureEnabled;
  final bool enabled;

  const PermissionEditor({
    super.key,
    required this.selected,
    required this.grantable,
    required this.onChanged,
    required this.featureEnabled,
    this.enabled = true,
  });

  bool _canToggle(String id) => enabled && grantable.contains(id);

  void _toggle(String id, bool on) {
    if (!_canToggle(id)) return;
    onChanged(on
        ? AppPermissions.normalize({...selected, id}).toSet()
        : AppPermissions.withoutPermission(selected, id));
  }

  void _toggleGroup(PermissionGroup group, bool on) {
    var next = {...selected};
    for (final a in group.actions.where((a) => _canToggle(a.id))) {
      next = on ? AppPermissions.normalize({...next, a.id}).toSet() : AppPermissions.withoutPermission(next, a.id);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final groups = [
      for (final g in AppPermissions.groups)
        // Hide features the plan doesn't include, unless already granted.
        if (g.planFeature == null || featureEnabled(g.planFeature!) || g.actions.any((a) => selected.contains(a.id))) g,
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 640 ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final g in groups) SizedBox(width: width, child: _groupCard(g)),
      ]);
    });
  }

  Widget _groupCard(PermissionGroup group) {
    final toggleable = group.actions.where((a) => _canToggle(a.id)).toList();
    final onCount = group.actions.where((a) => selected.contains(a.id)).length;
    final allOn = toggleable.isNotEmpty && toggleable.every((a) => selected.contains(a.id));
    return SurfaceCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(group.label, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 14.5)),
              const SizedBox(height: 2),
              Text(group.description, style: const TextStyle(color: AppColors.silver, fontSize: 12)),
            ]),
          ),
          if (onCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SoftBadge(label: '$onCount/${group.actions.length}', color: AppColors.brand, fontSize: 11),
            ),
          Switch.adaptive(
            value: allOn,
            activeTrackColor: AppColors.brand,
            onChanged: toggleable.isEmpty ? null : (v) => _toggleGroup(group, v),
          ),
        ]),
        const Divider(height: 14, color: AppColors.borderSoft),
        for (final a in group.actions) _actionRow(a),
      ]),
    );
  }

  Widget _actionRow(PermissionAction action) {
    final locked = !grantable.contains(action.id);
    final on = selected.contains(action.id);
    return InkWell(
      onTap: _canToggle(action.id) ? () => _toggle(action.id, !on) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Checkbox(
            value: on,
            activeColor: AppColors.brand,
            onChanged: _canToggle(action.id) ? (v) => _toggle(action.id, v == true) : null,
          ),
          Expanded(
            child: Text(action.label,
                style: TextStyle(color: locked ? AppColors.muted : AppColors.text, fontSize: 13.5)),
          ),
          if (locked)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Tooltip(
                message: "You can't grant access you don't have",
                child: Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.muted),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Bottom sheet wrapping [PermissionEditor]. [onSave] returns an error message,
/// or null on success (which closes the sheet with the saved set).
class PermissionEditorSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Set<String> initial;
  final Set<String> grantable;
  final bool Function(String feature) featureEnabled;
  final Future<String?> Function(Set<String> permissions) onSave;
  final String saveLabel;

  const PermissionEditorSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.initial,
    required this.grantable,
    required this.featureEnabled,
    required this.onSave,
    this.saveLabel = 'Save permissions',
  });

  static Future<Set<String>?> show(
    BuildContext context, {
    required String title,
    String? subtitle,
    required Set<String> initial,
    required Set<String> grantable,
    required bool Function(String feature) featureEnabled,
    required Future<String?> Function(Set<String> permissions) onSave,
    String saveLabel = 'Save permissions',
  }) {
    return AppSheet.show<Set<String>>(context, builder: (_) => PermissionEditorSheet(
      title: title,
      subtitle: subtitle,
      initial: initial,
      grantable: grantable,
      featureEnabled: featureEnabled,
      onSave: onSave,
      saveLabel: saveLabel,
    ));
  }

  @override
  State<PermissionEditorSheet> createState() => _PermissionEditorSheetState();
}

class _PermissionEditorSheetState extends State<PermissionEditorSheet> {
  late Set<String> _selected = {...widget.initial};
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    final error = await widget.onSave(_selected);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, _selected);
    } else {
      setState(() { _saving = false; _error = error; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AppSheet(
        title: widget.title,
        subtitle: widget.subtitle ??
            'Choose which owner features this member can use. Owner-only areas such as billing are never shared.',
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: SingleChildScrollView(
              child: PermissionEditor(
                selected: _selected,
                grantable: widget.grantable,
                featureEnabled: widget.featureEnabled,
                enabled: !_saving,
                onChanged: (next) => setState(() => _selected = next),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            label: widget.saveLabel,
            icon: Icons.verified_user_outlined,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ]),
      ),
    );
  }
}
