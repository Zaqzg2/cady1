import '../models/catalog_models.dart';
import '../models/inventory_models.dart';

/// عرض مُركَّب (Join) لصنف + رصيده في فرع معيّن — يُستخدم في شاشة "تحليل
/// المخزون" وأي مكان آخر يحتاج عرض/فرز/تصفية الأصناف مع بيانات فرعها
/// وتصنيفها معًا بلا إعادة البحث عنها في كل مرة.
class InventoryRowView {
  final Product product;
  final InventoryItem item;
  final Branch? branch;
  final ProductCategory? category;
  final StockStatus stockStatus;

  InventoryRowView({
    required this.product,
    required this.item,
    required this.branch,
    required this.category,
    required this.stockStatus,
  });
}

/// كل خيارات الفرز الاثني عشر كما وردت حرفيًا في القسم 9 من المواصفة
enum SortOption {
  nameAsc,
  nameDesc,
  quantityDesc,
  quantityAsc,
  itemNumber,
  barcode,
  expiryDate,
  newest,
  oldest,
  branch,
  category,
  stockStatus,
}

extension SortOptionLabel on SortOption {
  String get labelAr => switch (this) {
        SortOption.nameAsc => 'اسم الصنف A-Z',
        SortOption.nameDesc => 'اسم الصنف Z-A',
        SortOption.quantityDesc => 'الكمية من الأعلى',
        SortOption.quantityAsc => 'الكمية من الأقل',
        SortOption.itemNumber => 'رقم الصنف',
        SortOption.barcode => 'Barcode',
        SortOption.expiryDate => 'تاريخ الانتهاء',
        SortOption.newest => 'الأحدث',
        SortOption.oldest => 'الأقدم',
        SortOption.branch => 'الفرع',
        SortOption.category => 'التصنيف',
        SortOption.stockStatus => 'حالة المخزون',
      };
}

class SortingService {
  List<InventoryRowView> sort(List<InventoryRowView> rows, SortOption option) {
    final list = List<InventoryRowView>.from(rows);
    switch (option) {
      case SortOption.nameAsc:
        list.sort((a, b) => a.product.normalizedName.compareTo(b.product.normalizedName));
        break;
      case SortOption.nameDesc:
        list.sort((a, b) => b.product.normalizedName.compareTo(a.product.normalizedName));
        break;
      case SortOption.quantityDesc:
        list.sort((a, b) => b.item.quantity.compareTo(a.item.quantity));
        break;
      case SortOption.quantityAsc:
        list.sort((a, b) => a.item.quantity.compareTo(b.item.quantity));
        break;
      case SortOption.itemNumber:
        list.sort((a, b) => (a.product.itemNumber ?? '').compareTo(b.product.itemNumber ?? ''));
        break;
      case SortOption.barcode:
        list.sort((a, b) => (a.product.barcode ?? '').compareTo(b.product.barcode ?? ''));
        break;
      case SortOption.expiryDate:
        list.sort((a, b) {
          final ea = a.item.expiryDate;
          final eb = b.item.expiryDate;
          if (ea == null && eb == null) return 0;
          if (ea == null) return 1;
          if (eb == null) return -1;
          return ea.compareTo(eb);
        });
        break;
      case SortOption.newest:
        list.sort((a, b) => b.item.lastUpdated.compareTo(a.item.lastUpdated));
        break;
      case SortOption.oldest:
        list.sort((a, b) => a.item.lastUpdated.compareTo(b.item.lastUpdated));
        break;
      case SortOption.branch:
        list.sort((a, b) => (a.branch?.name ?? '').compareTo(b.branch?.name ?? ''));
        break;
      case SortOption.category:
        list.sort((a, b) => (a.category?.name ?? '').compareTo(b.category?.name ?? ''));
        break;
      case SortOption.stockStatus:
        list.sort((a, b) => a.stockStatus.index.compareTo(b.stockStatus.index));
        break;
    }
    return list;
  }
}
