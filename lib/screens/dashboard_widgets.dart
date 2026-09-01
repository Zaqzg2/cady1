import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _numberFormat = NumberFormat('#,##0', 'en_US');

/// قائمة أشرطة تناسبية (بديل عن أعمدة fl_chart الرأسية) — مناسبة أكثر لأسماء
/// أصناف عربية طويلة، وتدعم النقر لعرض التفاصيل تمامًا كما تطلب المواصفة.
class ProportionalBarList extends StatelessWidget {
  final List<({String label, double value})> items;
  final Color color;
  final void Function(int index)? onTap;

  const ProportionalBarList({
    super.key,
    required this.items,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('لا توجد بيانات كافية بعد.')),
      );
    }
    final maxValue = items.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Column(
      children: List.generate(items.length, (i) {
        final item = items[i];
        final ratio = maxValue == 0 ? 0.0 : (item.value / maxValue).clamp(0.03, 1.0);
        return InkWell(
          onTap: onTap == null ? null : () => onTap!(i),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    const SizedBox(width: 8),
                    Text(_numberFormat.format(item.value),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LayoutBuilder(builder: (context, constraints) {
                    return Stack(
                      children: [
                        Container(height: 8, color: color.withValues(alpha: 0.12)),
                        Container(height: 8, width: constraints.maxWidth * ratio, color: color),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// رسم دائري تفاعلي للتوزيع (حسب الفرع أو التصنيف)
class DistributionPieChart extends StatefulWidget {
  final List<({String label, double value})> items;
  final List<Color> palette;

  const DistributionPieChart({super.key, required this.items, required this.palette});

  @override
  State<DistributionPieChart> createState() => _DistributionPieChartState();
}

class _DistributionPieChartState extends State<DistributionPieChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('لا توجد بيانات كافية بعد.')),
      );
    }
    final total = widget.items.fold<double>(0, (s, i) => s + i.value);

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 42,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        response == null ||
                        response.touchedSection == null) {
                      _touchedIndex = null;
                    } else {
                      _touchedIndex = response.touchedSection!.touchedSectionIndex;
                    }
                  });
                },
              ),
              sections: List.generate(widget.items.length, (i) {
                final item = widget.items[i];
                final isTouched = i == _touchedIndex;
                final percent = total == 0 ? 0 : (item.value / total * 100);
                return PieChartSectionData(
                  value: item.value <= 0 ? 0.001 : item.value,
                  color: widget.palette[i % widget.palette.length],
                  title: '${percent.toStringAsFixed(0)}%',
                  radius: isTouched ? 58 : 50,
                  titleStyle: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: List.generate(widget.items.length, (i) {
            final item = widget.items[i];
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: widget.palette[i % widget.palette.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(item.label, style: const TextStyle(fontSize: 12)),
              ],
            );
          }),
        ),
      ],
    );
  }
}
