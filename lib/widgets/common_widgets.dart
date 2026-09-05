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

  /// true عندما لا يوفّر مصدر الاستخراج (OCR.space) ثقة حقيقية لكل حقل —
  /// نعرض "الثقة غير متاحة" بدل نسبة مختلَقة (قسم ١٢ من مواصفة الدمج: لا
  /// تخترع ثقة وهمية). [confidence] في هذه الحالة قيمة داخلية للفرز فقط،
  /// لا تُعرض كنسبة.
  final bool unavailable;

  const ConfidenceBadge({super.key, required this.confidence, this.compact = false, this.unavailable = false});

  @override
  Widget build(BuildContext context) {
    if (unavailable) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 5),
        decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text('الثقة غير متاحة', style: TextStyle(color: Colors.grey.shade700, fontSize: compact ? 10.5 : 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    final level = confidence.level;
    final Color color;
    final String label;
    switch (level) {
      case ConfidenceLevel.high:
        color = AppColors.confidenceHigh;
        label = 'ثقة عالية';
      case ConfidenceLevel.medium:
        color = AppColors.confidenceMedium;
        label = 'مراجعة موصى بها';
      case ConfidenceLevel.low:
        color = AppColors.confidenceLow;
        label = 'تحتاج مراجعة';
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
