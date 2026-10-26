import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// Building blocks shared by the redesigned owner and staff screens.

/// White circular back button with a soft drop shadow.
class CircleBackButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  const CircleBackButton({super.key, this.onTap, this.icon = Icons.chevron_left_rounded});

  /// Pops when there is a screen to return to; otherwise (screen opened from
  /// a notification or deep link) goes to the owner/staff home instead of
  /// silently doing nothing.
  static void goBack(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final path = router.routerDelegate.currentConfiguration.uri.path;
    router.go(path.startsWith('/owner') ? '/owner' : '/staff');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => goBack(context),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.borderSoft),
          boxShadow: AppColors.cardShadow,
        ),
        child: Icon(icon, color: AppColors.text, size: 24),
      ),
    );
  }
}

/// Small round/square icon button used in page headers (bell, settings, refresh).
class HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool tinted;
  final bool round;
  final int? badge;
  final Color? color;
  const HeaderIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tinted = false,
    this.round = true,
    this.badge,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? (tinted ? AppColors.brand : AppColors.text);
    return GestureDetector(
      onTap: onTap,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: tinted ? AppColors.brandSoft : AppColors.white,
            shape: round ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: round ? null : BorderRadius.circular(12),
            border: Border.all(color: tinted ? AppColors.brandBorder : AppColors.borderSoft),
            boxShadow: AppColors.cardShadow,
          ),
          child: Icon(icon, color: fg, size: 20),
        ),
        if (badge != null && badge! > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.white, width: 1.5),
              ),
              child: Center(
                child: Text(badge! > 9 ? '9+' : '$badge',
                    style: const TextStyle(color: AppColors.white, fontSize: 8.5, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Primary circular "+" action used on Jobs / Customers / Staff headers.
class RoundAddButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final double size;
  const RoundAddButton({super.key, this.onTap, this.icon = Icons.add_rounded, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.brand,
          shape: BoxShape.circle,
          boxShadow: AppColors.glow(AppColors.brand),
        ),
        child: Icon(icon, color: AppColors.white, size: size * 0.62),
      ),
    );
  }
}

/// Header row: optional circular back button, Poppins title, trailing actions.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget? titleTrailing;
  final EdgeInsetsGeometry padding;
  final double titleSize;
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = true,
    this.onBack,
    this.actions = const [],
    this.titleTrailing,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
    this.titleSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(children: [
        if (showBack) ...[
          CircleBackButton(onTap: onBack),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Flexible(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.pageTitle.copyWith(fontSize: titleSize)),
              ),
              if (titleTrailing != null) ...[const SizedBox(width: 10), titleTrailing!],
            ]),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: const TextStyle(color: AppColors.silver, fontSize: 12.5)),
              ),
          ]),
        ),
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          actions[i],
        ],
      ]),
    );
  }
}

/// White rounded card with hairline border and soft shadow.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;
  final bool shadow;
  final Gradient? gradient;
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color,
    this.borderColor,
    this.radius = 18,
    this.onTap,
    this.shadow = true,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? AppColors.white) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppColors.border),
        boxShadow: shadow ? AppColors.cardShadow : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
    return box;
  }
}

/// Pill-shaped filter chip: selected = filled brand, otherwise white with border.
class PillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final int? count;
  final IconData? icon;
  final bool dot;
  final Color selectedColor;
  final EdgeInsetsGeometry padding;
  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.count,
    this.icon,
    this.dot = false,
    this.selectedColor = AppColors.brand,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.white : AppColors.light;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: padding,
        decoration: BoxDecoration(
          color: selected ? selectedColor : AppColors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: selected ? selectedColor : AppColors.border),
          boxShadow: selected ? AppColors.glow(selectedColor) : AppColors.softShadow,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
          Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ],
          if (dot) ...[
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: selected ? AppColors.white : AppColors.brand, shape: BoxShape.circle),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Horizontally scrollable row of [PillChip]s.
class PillChipBar extends StatelessWidget {
  final List<Widget> chips;
  final EdgeInsetsGeometry padding;
  const PillChipBar({super.key, required this.chips, this.padding = const EdgeInsets.symmetric(horizontal: 16)});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      clipBehavior: Clip.none,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          for (var i = 0; i < chips.length; i++) ...[if (i > 0) const SizedBox(width: 8), chips[i]],
        ]),
      ),
    );
  }
}

/// Tinted rounded badge such as "High", "Pending", "Completed".
class SoftBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool dot;
  final IconData? icon;
  final double fontSize;
  final bool uppercase;
  final Color? background;
  const SoftBadge({
    super.key,
    required this.label,
    required this.color,
    this.dot = false,
    this.icon,
    this.fontSize = 12,
    this.uppercase = false,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ],
        if (icon != null) ...[Icon(icon, size: fontSize + 2, color: color), const SizedBox(width: 4)],
        Text(uppercase ? label.toUpperCase() : label,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: uppercase ? 0.6 : 0,
            )),
      ]),
    );
  }
}

/// Rounded-square tinted icon container.
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final double radius;
  final Color? background;
  const IconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
    this.iconSize = 20,
    this.radius = 12,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}

/// Uppercase grey section label, optionally with a trailing widget.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final bool rule;
  const SectionLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 18, 4, 10), this.rule = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(children: [
        Text(text.toUpperCase(), style: AppTextStyles.label.copyWith(color: AppColors.muted)),
        if (rule) ...[
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: AppColors.border)),
        ] else
          const Spacer(),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Avatar circle with initials and optional online dot.
class InitialAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  final bool? online;
  final bool square;
  const InitialAvatar({super.key, required this.name, this.size = 44, this.color, this.online, this.square = false});

  static const _palette = [
    Color(0xFF3B82F6),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFF8B5CF6),
    Color(0xFF0EA5E9),
    Color(0xFFEC4899),
  ];

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final base = color ?? _palette[name.isEmpty ? 0 : name.codeUnitAt(0) % _palette.length];
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: square ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: square ? BorderRadius.circular(size * 0.3) : null,
          gradient: LinearGradient(
            colors: [base, Color.lerp(base, AppColors.indigo, 0.35)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(initials(name),
              style: TextStyle(color: AppColors.white, fontSize: size * 0.36, fontWeight: FontWeight.w700)),
        ),
      ),
      if (online != null)
        Positioned(
          right: square ? -2 : 0,
          bottom: square ? -2 : 0,
          child: Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: BoxDecoration(
              color: online! ? AppColors.green : AppColors.muted,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.white, width: 2),
            ),
          ),
        ),
    ]);
  }
}

/// Grouped list card (Profile screens): rows separated by hairlines.
class MenuGroup extends StatelessWidget {
  final List<Widget> children;
  final Color? borderColor;
  const MenuGroup({super.key, required this.children, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      borderColor: borderColor,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: AppColors.borderSoft),
          children[i],
        ],
      ]),
    );
  }
}

class MenuRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? labelColor;
  final bool chevron;
  const MenuRow({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.labelColor,
    this.chevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(children: [
          IconTile(icon: icon, color: color, size: 40, iconSize: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      color: labelColor ?? AppColors.text, fontSize: 15, fontWeight: FontWeight.w500)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ),
            ]),
          ),
          if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
          if (chevron)
            Icon(Icons.chevron_right_rounded,
                color: labelColor?.withValues(alpha: 0.6) ?? AppColors.muted, size: 22),
        ]),
      ),
    );
  }
}

/// Rounded search box with leading magnifier.
class SearchBox extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;
  const SearchBox({super.key, this.controller, required this.hint, this.onChanged, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: AppColors.text, fontSize: 14.5),
        decoration: InputDecoration(
          hintText: hint,
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted, size: 21),
          suffixIcon: trailing,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

/// Label above a form field ("Full Name *" / optional trailing hint).
class FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  final String? hint;
  final bool caps;
  const FieldLabel(this.text, {super.key, this.required = false, this.hint, this.caps = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Text(caps ? text.toUpperCase() : text,
            style: caps
                ? AppTextStyles.label.copyWith(color: AppColors.light, fontSize: 12)
                : AppTextStyles.fieldLabel),
        if (required) const Text(' *', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (hint != null) Text(hint!, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
      ]),
    );
  }
}

/// Bottom sheet with drag handle, title, subtitle and a circular close button.
class AppSheet extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? titleTrailing;
  final Widget child;
  final bool showClose;
  final Widget? headerAction;
  final EdgeInsetsGeometry padding;
  const AppSheet({
    super.key,
    this.title,
    this.subtitle,
    this.titleTrailing,
    required this.child,
    this.showClose = true,
    this.headerAction,
    this.padding = const EdgeInsets.fromLTRB(24, 0, 24, 20),
  });

  static Future<T?> show<T>(BuildContext context, {required WidgetBuilder builder}) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      barrierColor: const Color(0x660F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: builder(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: padding,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetHandle(),
            if (title != null) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(title!, style: AppTextStyles.h2.copyWith(fontSize: 21))),
                      if (titleTrailing != null) ...[const SizedBox(width: 10), titleTrailing!],
                    ]),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(subtitle!, style: const TextStyle(color: AppColors.silver, fontSize: 13.5, height: 1.4)),
                      ),
                  ]),
                ),
                if (headerAction != null) headerAction!,
                if (showClose && headerAction == null) const SheetCloseButton(),
              ]),
              const SizedBox(height: 18),
            ],
            child,
          ]),
        ),
      ),
    );
  }
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 42,
        height: 5,
        margin: const EdgeInsets.only(top: 10, bottom: 18),
        decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(3)),
      ),
    );
  }
}

class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({super.key});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(color: AppColors.dark4, shape: BoxShape.circle),
        child: const Icon(Icons.close_rounded, size: 18, color: AppColors.silver),
      ),
    );
  }
}

/// Large filled primary button (52-56px) with optional leading/trailing icon.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final Color color;
  final Gradient? gradient;
  final double height;
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.color = AppColors.brand,
    this.gradient,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled || loading ? 1 : 0.55,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: gradient == null ? color : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled ? AppColors.glow(color) : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.white))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[Icon(icon, color: AppColors.white, size: 20), const SizedBox(width: 10)],
                      Flexible(
                        child: Text(label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      if (trailingIcon != null) ...[
                        const SizedBox(width: 10),
                        Icon(trailingIcon, color: AppColors.white, size: 19),
                      ],
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// White outlined secondary button.
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final Color? fill;
  final double height;
  const SecondaryButton({super.key, required this.label, this.onPressed, this.icon, this.color, this.fill, this.height = 52});

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.text;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: fill ?? AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fill != null ? fill! : (color?.withValues(alpha: 0.6) ?? AppColors.border)),
        boxShadow: fill != null ? null : AppColors.softShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, color: fg, size: 18), const SizedBox(width: 8)],
              Text(label, style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Underlined tab with an optional count bubble (Jobs: Pending / In Progress / Completed).
class CountTab extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  const CountTab({super.key, required this.label, this.count, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 40,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label),
        if (count != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: selected ? AppColors.brandSoft : AppColors.dark4,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.brand : AppColors.silver)),
          ),
        ],
      ]),
    );
  }
}

/// Centered empty state with a soft circular icon halo.
class SoftEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color color;
  const SoftEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.color = AppColors.brand,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.06),
              border: Border.all(color: color.withValues(alpha: 0.12)),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 24, spreadRadius: 4)],
            ),
            child: Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.08)),
                child: Icon(icon, color: color, size: 32),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(title, textAlign: TextAlign.center, style: AppTextStyles.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.silver, fontSize: 14, height: 1.5)),
          ],
          if (action != null) ...[const SizedBox(height: 22), action!],
        ]),
      ),
    );
  }
}

/// Confirmation sheet with icon, title, message and two stacked buttons
/// (Logout / Delete confirmations). Returns true when confirmed.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  Color color = AppColors.red,
  Widget? detail,
}) async {
  final ok = await AppSheet.show<bool>(
    context,
    builder: (ctx) => AppSheet(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        IconTile(icon: icon, color: color, size: 56, iconSize: 26, radius: 16),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: AppTextStyles.h2.copyWith(fontSize: 20)),
        const SizedBox(height: 10),
        Text(message,
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.silver, fontSize: 13.5, height: 1.5)),
        if (detail != null) ...[const SizedBox(height: 16), detail],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: PrimaryButton(label: confirmLabel, color: color, onPressed: () => Navigator.pop(ctx, true)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SecondaryButton(
              label: cancelLabel, fill: AppColors.dark4, onPressed: () => Navigator.pop(ctx, false)),
        ),
      ]),
    ),
  );
  return ok == true;
}

/// Centered confirmation dialog (Delete Customer style).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  Color color = AppColors.red,
  Widget? detail,
  InlineSpan? richMessage,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x660F172A),
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          IconTile(icon: icon, color: color, size: 62, iconSize: 28, radius: 16),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: AppTextStyles.h2.copyWith(fontSize: 19)),
          if (detail != null) ...[const SizedBox(height: 12), detail],
          const SizedBox(height: 12),
          if (richMessage != null)
            Text.rich(richMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.silver, fontSize: 13.5, height: 1.55))
          else
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.silver, fontSize: 13.5, height: 1.55)),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: SecondaryButton(label: cancelLabel, height: 48, onPressed: () => Navigator.pop(ctx, false))),
            const SizedBox(width: 12),
            Expanded(
                child: PrimaryButton(
                    label: confirmLabel, color: color, height: 48, onPressed: () => Navigator.pop(ctx, true))),
          ]),
        ]),
      ),
    ),
  );
  return ok == true;
}

/// Paints a dashed rounded-rectangle border (empty capture slots, invite card).
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  const DashedBorderPainter({required this.color, this.radius = 16, this.strokeWidth = 1.6});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter old) => old.color != color || old.radius != radius;
}
