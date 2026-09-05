import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// هدف شهري لصنف معيّن في فرع معيّن — القسم 10 من المواصفة (Goal 1/2/3).
class MonthlyGoal {
  final String id;
  int year;
  int month; // 1-12
  String branchId;
  String productId;
  double goal1;
  double goal2;
  double goal3;
  DateTime createdAt;
  DateTime updatedAt;

  MonthlyGoal({
    String? id,
    required this.year,
    required this.month,
    required this.branchId,
    required this.productId,
    this.goal1 = 0,
    this.goal2 = 0,
    this.goal3 = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'year': year,
        'month': month,
        'branchId': branchId,
        'productId': productId,
        'goal1': goal1,
        'goal2': goal2,
        'goal3': goal3,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory MonthlyGoal.fromMap(Map<dynamic, dynamic> map) => MonthlyGoal(
        id: map['id'] as String,
        year: map['year'] as int? ?? DateTime.now().year,
        month: map['month'] as int? ?? DateTime.now().month,
        branchId: map['branchId'] as String,
        productId: map['productId'] as String,
        goal1: (map['goal1'] as num?)?.toDouble() ?? 0,
        goal2: (map['goal2'] as num?)?.toDouble() ?? 0,
        goal3: (map['goal3'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// نتيجة محسوبة (غير مخزَّنة) لتقدّم هدف واحد نحو مستوياته الثلاثة — تُنتجها
/// GoalService بناءً على [MonthlyGoal] + الكمية الواردة الفعلية خلال الشهر
/// (القسمان 10 و11). كل الحسابات هنا ديناميكية بالكامل من الحركات الفعلية.
class GoalProgress {
  final MonthlyGoal goal;
  final double incomingQuantity;

  GoalProgress({required this.goal, required this.incomingQuantity});

  double get pct1 => goal.goal1 <= 0 ? 0 : (incomingQuantity / goal.goal1 * 100);
  double get pct2 => goal.goal2 <= 0 ? 0 : (incomingQuantity / goal.goal2 * 100);
  double get pct3 => goal.goal3 <= 0 ? 0 : (incomingQuantity / goal.goal3 * 100);

  double get remaining1 => (goal.goal1 - incomingQuantity) < 0 ? 0 : (goal.goal1 - incomingQuantity);
  double get remaining2 => (goal.goal2 - incomingQuantity) < 0 ? 0 : (goal.goal2 - incomingQuantity);
  double get remaining3 => (goal.goal3 - incomingQuantity) < 0 ? 0 : (goal.goal3 - incomingQuantity);

  bool get achieved1 => goal.goal1 > 0 && incomingQuantity >= goal.goal1;
  bool get achieved2 => goal.goal2 > 0 && incomingQuantity >= goal.goal2;
  bool get achieved3 => goal.goal3 > 0 && incomingQuantity >= goal.goal3;

  /// أعلى هدف مُحقَّق حاليًا (0 إن لم يتحقق أي منها) — لتلوين بطاقة الملخص
  int get highestAchievedTier => achieved3 ? 3 : (achieved2 ? 2 : (achieved1 ? 1 : 0));
}
