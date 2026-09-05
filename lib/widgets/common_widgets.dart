import 'package:flutter/material.dart';

import '../models/import_models.dart';
import '../theme/app_theme.dart';

class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accentColor;
  final VoidCallback? onTap;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 12),
              Text(value,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class ConfidenceBadge extends StatelessWidget {
  final double confidence; // 0.0 - 1.0
  final bool compact;
  const ConfidenceBadge({super.key, required this.confidence, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final level = confidence.level;
    final Color color;
    final String label;
    switch (level) {
      case ConfidenceLevel.high:
        color = AppColors.confidenceHigh;
        label = 'مؤكدة';
      case ConfidenceLevel.medium:
        color = AppColors.confidenceMedium;
        label = 'راجع';
      case ConfidenceLevel.low:
        color = AppColors.confidenceLow;
        label = 'غير مؤكدة';
    }
    final percent = '${(confidence * 100).round()}%';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            compact ? percent : '$label · $percent',
            style: TextStyle(color: color, fontSize: compact ? 10.5 : 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// شارة حالة توفر المخزون 🟢🟡🔴 (القسم 8) — نُطلقها StockStatus من
/// inventory_models.dart، لكن نتفادى استيرادها هنا مباشرة لإبقاء هذا الملف
/// عامًا؛ لذلك تُمرَّر اللون والنص جاهزين من المستدعي عبر [StatusPill].
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool compact;
  const StatusPill({super.key, required this.label, required this.color, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: compact ? 10.5 : 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// شريط تقدّم هدف واحد (من الأهداف الثلاثة) بنمط بصري حديث (القسم 11)
class GoalTierProgress extends StatelessWidget {
  final String label;
  final double current;
  final double target;
  final double pct;
  final bool achieved;

  const GoalTierProgress({
    super.key,
    required this.label,
    required this.current,
    required this.target,
    required this.pct,
    required this.achieved,
  });

  @override
  Widget build(BuildContext context) {
    final color = achieved
        ? AppColors.expirySafe
        : (pct >= 60 ? AppColors.expiryWithin30 : AppColors.expiryExpired);
    final clamped = target <= 0 ? 0.0 : (current / target).clamp(0, 1).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            Text('${current.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12.5)),
            const SizedBox(width: 8),
            Icon(achieved ? Icons.check_circle : Icons.circle_outlined, color: color, size: 16),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 2),
        Text('${pct.clamp(0, 999).toStringAsFixed(0)}٪', style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

/// حوار تأكيد موحّد لأي عملية حذف/تصفير (القسم 33: "قبل Delete/Reset/Clear
/// Data اعرض Confirmation") — نفس الشكل والسلوك في كل شاشات التطبيق.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'حذف',
  bool danger = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
