import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_analyzer/models/goal_models.dart';
import 'package:inventory_analyzer/models/inventory_models.dart';
import 'package:inventory_analyzer/services/goal_service.dart';

void main() {
  final service = GoalService();

  group('GoalProgress — أمثلة القسم 11 حرفيًا', () {
    test('100/100 = 100% محقَّق', () {
      final goal = MonthlyGoal(year: 2026, month: 1, branchId: 'b1', productId: 'p1', goal1: 100);
      final progress = GoalProgress(goal: goal, incomingQuantity: 100);
      expect(progress.pct1, 100);
      expect(progress.achieved1, true);
      expect(progress.remaining1, 0);
    });

    test('135/150 = 90% ومتبقٍ 15', () {
      final goal = MonthlyGoal(year: 2026, month: 1, branchId: 'b1', productId: 'p1', goal2: 150);
      final progress = GoalProgress(goal: goal, incomingQuantity: 135);
      expect(progress.pct2, 90);
      expect(progress.achieved2, false);
      expect(progress.remaining2, 15);
    });

    test('135/200 = 67.5% ومتبقٍ 65', () {
      final goal = MonthlyGoal(year: 2026, month: 1, branchId: 'b1', productId: 'p1', goal3: 200);
      final progress = GoalProgress(goal: goal, incomingQuantity: 135);
      expect(progress.pct3, 67.5);
      expect(progress.achieved3, false);
      expect(progress.remaining3, 65);
    });
  });

  group('حالات حدّية', () {
    test('هدف = 0 لا يُقسَّم عليه أبدًا (لا استثناء)', () {
      final goal = MonthlyGoal(year: 2026, month: 1, branchId: 'b1', productId: 'p1', goal1: 0);
      final progress = GoalProgress(goal: goal, incomingQuantity: 50);
      expect(progress.pct1, 0);
      expect(progress.achieved1, false);
    });

    test('وارد = 0 يعطي 0% ومتبقٍ يساوي الهدف كاملاً', () {
      final goal = MonthlyGoal(year: 2026, month: 1, branchId: 'b1', productId: 'p1', goal1: 100);
      final progress = GoalProgress(goal: goal, incomingQuantity: 0);
      expect(progress.pct1, 0);
      expect(progress.remaining1, 100);
    });

    test('تجاوز الهدف (وارد 1000 لهدف 100): المتبقي 0 لا سالب', () {
      final goal = MonthlyGoal(year: 2026, month: 1, branchId: 'b1', productId: 'p1', goal1: 100);
      final progress = GoalProgress(goal: goal, incomingQuantity: 1000);
      expect(progress.pct1, 1000);
      expect(progress.remaining1, 0);
      expect(progress.achieved1, true);
    });
  });

  group('GoalService.incomingQuantityFor', () {
    test('يجمع فقط حركات incoming ضمن نافذة الشهر لنفس الصنف والفرع', () {
      final movements = [
        StockMovement.incoming(
            productId: 'p1', branchId: 'b1', quantity: 40, date: DateTime(2026, 1, 5)),
        StockMovement.incoming(
            productId: 'p1', branchId: 'b1', quantity: 20, date: DateTime(2026, 1, 20)),
        // خارج الشهر
        StockMovement.incoming(
            productId: 'p1', branchId: 'b1', quantity: 999, date: DateTime(2026, 2, 1)),
        // نوع حركة مختلف (لا يُحتسَب ضمن "الوارد")
        StockMovement.issue(productId: 'p1', branchId: 'b1', quantity: 15, date: DateTime(2026, 1, 10)),
        // صنف مختلف
        StockMovement.incoming(
            productId: 'p2', branchId: 'b1', quantity: 999, date: DateTime(2026, 1, 10)),
      ];
      final total = service.incomingQuantityFor(
        productId: 'p1',
        branchId: 'b1',
        year: 2026,
        month: 1,
        movements: movements,
      );
      expect(total, 60);
    });

    test('بداية شهر مخصَّصة (يوم 26) تُزيح نافذة الحساب بشكل صحيح', () {
      final movements = [
        // ضمن نافذة "مارس" [26 مارس ← 26 أبريل) حين تبدأ الشهور من يوم 26
        StockMovement.incoming(
            productId: 'p1', branchId: 'b1', quantity: 30, date: DateTime(2026, 4, 1)),
        // يقع قبل بداية نافذة مارس (ضمن نافذة فبراير بدلاً من ذلك) فلا يُحتسَب
        StockMovement.incoming(
            productId: 'p1', branchId: 'b1', quantity: 999, date: DateTime(2026, 3, 20)),
      ];
      final total = service.incomingQuantityFor(
        productId: 'p1',
        branchId: 'b1',
        year: 2026,
        month: 3,
        movements: movements,
        monthStartDay: 26,
      );
      expect(total, 30);
    });
  });

  group('GoalService.averageAchievement', () {
    test('يتجاهل الأهداف غير المضبوطة (0) عند حساب المتوسط', () {
      final g1 = MonthlyGoal(year: 2026, month: 1, branchId: 'b1', productId: 'p1', goal1: 100);
      final g2 = MonthlyGoal(year: 2026, month: 1, branchId: 'b2', productId: 'p2', goal1: 0);
      final progressList = [
        GoalProgress(goal: g1, incomingQuantity: 50),
        GoalProgress(goal: g2, incomingQuantity: 999),
      ];
      final avg = service.averageAchievement(progressList);
      expect(avg.avg1, 50); // فقط g1 دخلت الحساب
    });

    test('قائمة فارغة تعطي كل المتوسطات صفرًا بلا استثناء', () {
      final avg = service.averageAchievement([]);
      expect(avg.avg1, 0);
      expect(avg.avg2, 0);
      expect(avg.avg3, 0);
    });
  });
}
