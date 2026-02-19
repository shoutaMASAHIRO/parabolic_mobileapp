import 'package:flutter/material.dart';

/// GMOコイン風のフォーマル&モダンなカラーパレット
/// ダークモードを基本とし、視認性の高い配色を採用
class AppColors {
  AppColors._();

  // --- ダークテーマ用ベースカラー (GMO Coin Style) ---
  static const Color background = Color(0xFF0D1117); // 深い黒
  static const Color surface = Color(0xFF161B22);    // 少し明るい黒（カード等）
  static const Color scaffoldBackground = Color(0xFF0D1117);
  
  // --- ブランドカラー ---
  static const Color primary = Color(0xFF0052CC);    // 信頼感のあるブルー
  static const Color primaryLight = Color(0xFF335CC5);
  static const Color accent = Color(0xFF00A1E9);     // アクセントブルー

  // --- テキストカラー ---
  static const Color textPrimary = Color(0xFFE6EDF3);   // ほぼ白
  static const Color textSecondary = Color(0xFF8B949E); // グレー
  static const Color textTertiary = Color(0xFF484F58);  // 濃いグレー

  // --- 金融・チャートカラー (日本式: 赤=上昇, 青=下落) ---
  static const Color rise = Color(0xFFFF3B30); // 鮮やかな赤 (上昇)
  static const Color fall = Color(0xFF007AFF); // 鮮やかな青 (下落)
  static const Color unchanged = Color(0xFF8E8E93);

  // --- チャート背景 & グリッド ---
  static const Color chartBackground = Color(0xFF0D1117);
  static const Color chartGrid = Color(0xFF21262D);
  static const Color axisLabel = Color(0xFF8B949E);

  // --- テクニカル指標 (視認性重視) ---
  static const Color bbMiddle = Color(0xFFFFD60A);    // 黄色
  static const Color emaShort = Color(0xFF30D158);    // 緑
  static const Color emaMedium = Color(0xFF5E5CE6);   // 紫
  static const Color emaLong = Color(0xFFFF9F0A);     // オレンジ

  // オシレーター
  static const Color rsiLine = Color(0xFFBF5AF2);     // 明るい紫
  static const Color macdLine = Color(0xFF0A84FF);    // 青
  static const Color macdSignal = Color(0xFFFF9F0A);  // オレンジ
  static const Color macdHistogramPositive = Color(0xFF32D74B);
  static const Color macdHistogramNegative = Color(0xFFFF453A);
  static const Color stochK = Color(0xFF0A84FF);      // ストキャスティクスK
  static const Color stochD = Color(0xFFFF9F0A);      // ストキャスティクスD
  static const Color cciLine = Color(0xFF00BCD4);     // CCI

  // その他
  static const Color error = Color(0xFFFF453A);
  static const Color success = Color(0xFF32D74B);
  static const Color warning = Color(0xFFFF9F0A);
  static const Color info = Color(0xFF0A84FF);
  static const Color border = Color(0xFF30363D);
  static const Color divider = Color(0xFF21262D);

  // 旧名称との互換性
  static const Color bullish = rise;
  static const Color bearish = fall;
  static const Color crypto = Color(0xFFF7931A); 
  static const Color forex = Color(0xFF2E7D32); 
  static const Color stock = Color(0xFF1976D2);
  static const Color cryptoLight = Color(0x33F7931A);
  static const Color forexLight = Color(0x332E7D32);
  static const Color stockLight = Color(0x331976D2);
  static const Color cryptoPrimary = crypto;
  static const Color forexPrimary = forex;
  static const Color stockPrimary = stock;
  static const Color borderLight = Color(0xFF30363D);
}

/// カテゴリー別のカラーユーティリティ
class CategoryColors {
  CategoryColors._();

  static Color forCategoryName(String categoryName) {
    switch (categoryName.toLowerCase()) {
      case 'crypto':
        return AppColors.crypto;
      case 'forex':
        return AppColors.forex;
      case 'stock':
        return AppColors.stock;
      default:
        return AppColors.primary;
    }
  }
}
