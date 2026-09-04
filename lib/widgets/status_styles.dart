import 'package:flutter/material.dart';

import '../models/inventory_models.dart';
import '../models/purchase_models.dart';
import '../theme/app_theme.dart';

Color colorForStockStatus(StockStatus status) => switch (status) {
      StockStatus.available => AppColors.stockAvailable,
      StockStatus.low => AppColors.stockLow,
      StockStatus.outOfStock => AppColors.stockOut,
    };

IconData iconForStockStatus(StockStatus status) => switch (status) {
      StockStatus.available => Icons.check_circle_outline,
      StockStatus.low => Icons.warning_amber_rounded,
      StockStatus.outOfStock => Icons.remove_circle_outline,
    };

Color colorForExpiryStatus(ExpiryStatus status) => switch (status) {
      ExpiryStatus.expired => AppColors.expiryExpired,
      ExpiryStatus.within30 => AppColors.expiryWithin30,
      ExpiryStatus.within60 => AppColors.expiryWithin60,
      ExpiryStatus.safe => AppColors.expirySafe,
      ExpiryStatus.noDate => Colors.grey,
    };

String labelForExpiryStatus(ExpiryStatus status) => switch (status) {
      ExpiryStatus.expired => 'منتهي',
      ExpiryStatus.within30 => 'قريب الانتهاء',
      ExpiryStatus.within60 => 'يقترب لاحقًا',
      ExpiryStatus.safe => 'آمن',
      ExpiryStatus.noDate => 'بلا تاريخ',
    };

Color colorForPurchaseStatus(PurchaseRequestStatus status) => switch (status) {
      PurchaseRequestStatus.draft => AppColors.purchaseDraft,
      PurchaseRequestStatus.requested => AppColors.purchaseRequested,
      PurchaseRequestStatus.partial => AppColors.purchasePartial,
      PurchaseRequestStatus.completed => AppColors.purchaseCompleted,
      PurchaseRequestStatus.cancelled => AppColors.purchaseCancelled,
    };
