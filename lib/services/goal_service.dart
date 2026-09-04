import '../models/goal_models.dart';
import '../models/inventory_models.dart';

/// حساب تقدّم الأهداف الشهرية — كل شيء هنا ديناميكي بالكامل من حركات الوارد
/// الفعلية، بلا أي رقم مخزَّن سابقًا (القسمان 10 و11).
class GoalService {
  /// نافذة "الشهر" الفعلية بحسب يوم بداية الشهر المضبوط في الإعدادات (القسم
  /// 34) — افتراضيًا 1 (بداية شهر ميلادي عادية). مثال: عند month=3 (مارس)
  /// وstartDay=26، تكون النافذة [26 مارس ← 26 أبريل) — أي أن "شهر مارس" هنا
  /// يبدأ من يوم 26 من مارس نفسه ويمتد حتى يوم 26 من الشهر التالي (نفس صيغة
  /// startDay=1 تمامًا، فقط بيوم بداية مختلف؛ صيغة واحدة موحّدة لكل القيم).
  ({DateTime start, DateTime end}) monthWindow(int year, int month, {int startDay = 1}) {
    final safeDay = startDay.clamp(1, 28);
    final start = DateTime(year, month, safeDay);
    final endMonth = month == 12 ? 1 : month + 1;
    final endYear = month == 12 ? year + 1 : year;
    final end = DateTime(endYear, endMonth, safeDay);
    return (start: start, end: end);
  }

  double incomingQuantityFor({
    required String productId,
    required String branchId,
    required int year,
    required int month,
    required List<StockMovement> movements,
    int monthStartDay = 1,
  }) {
    final window = monthWindow(year, month, startDay: monthStartDay);
    return movements
        .where((m) =>
            m.productId == productId &&
            m.branchId == branchId &&
            m.type == MovementType.incoming &&
            !m.date.isBefore(window.start) &&
            m.date.isBefore(window.end))
        .fold<double>(0, (sum, m) => sum + m.quantity);
  }

  GoalProgress progressOf(
    MonthlyGoal goal,
    List<StockMovement> movements, {
    int monthStartDay = 1,
  }) {
    final qty = incomingQuantityFor(
      productId: goal.productId,
      branchId: goal.branchId,
      year: goal.year,
      month: goal.month,
      movements: movements,
      monthStartDay: monthStartDay,
    );
    return GoalProgress(goal: goal, incomingQuantity: qty);
  }

  List<GoalProgress> progressOfAll(
    List<MonthlyGoal> goals,
    List<StockMovement> movements, {
    int monthStartDay = 1,
  }) {
    return goals.map((g) => progressOf(g, movements, monthStartDay: monthStartDay)).toList();
  }

  /// متوسط نسب التحقق عبر مجموعة أهداف — للوحة الأهداف العامة (القسم 12)
  ({double avg1, double avg2, double avg3}) averageAchievement(List<GoalProgress> list) {
    final withGoal1 = list.where((g) => g.goal.goal1 > 0).toList();
    final withGoal2 = list.where((g) => g.goal.goal2 > 0).toList();
    final withGoal3 = list.where((g) => g.goal.goal3 > 0).toList();

    double avgOf(List<GoalProgress> l, double Function(GoalProgress) pick) => l.isEmpty
        ? 0
        : l.map((g) => pick(g).clamp(0, 100)).reduce((a, b) => a + b) / l.length;

    return (
      avg1: avgOf(withGoal1, (g) => g.pct1),
      avg2: avgOf(withGoal2, (g) => g.pct2),
      avg3: avgOf(withGoal3, (g) => g.pct3),
    );
  }
}
