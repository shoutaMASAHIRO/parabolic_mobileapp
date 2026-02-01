import 'package:flutter/material.dart';

/// フォーマル&モダンな白基調デザインのカラーパレット
class AppColors {
  AppColors._(); // プライベートコンストラクタ

  // ベースカラー
  static const Color background = Color(0xFFFAFAFA); // ソフトホワイト
  static const Color surface = Color(0xFFFFFFFF); // ピュアホワイト
  static const Color primary = Color(0xFF1A365D); // ネイビーブルー（権威性）

  // テキストカラー
  static const Color textPrimary = Color(0xFF1A202C); // ほぼ黒
  static const Color textSecondary = Color(0xFF718096); // ミディアムグレー

  // ボーダー
  static const Color borderLight = Color(0xFFE2E8F0); // サブトルボーダー
  static const Color borderMedium = Color(0xFFCBD5E0); // ビジブルディバイダー

  // カテゴリーカラー（プロフェッショナル）
  // 仮想通貨
  static const Color cryptoPrimary = Color(0xFF2D3748); // チャコール
  static const Color cryptoAccent = Color(0xFF4A5568); // スレートグレー
  static const Color cryptoLight = Color(0xFFEDF2F7); // ライトグレー背景

  // 為替
  static const Color forexPrimary = Color(0xFF276749); // フォレストグリーン
  static const Color forexAccent = Color(0xFF38A169); // セージグリーン
  static const Color forexLight = Color(0xFFE6FFFA); // ライトグリーン背景

  // 株式
  static const Color stockPrimary = Color(0xFF2C5282); // コーポレートブルー
  static const Color stockAccent = Color(0xFF3182CE); // スカイブルー
  static const Color stockLight = Color(0xFFEBF8FF); // ライトブルー背景

  // チャートカラー
  static const Color chartBackground = Color(0xFFFAFAFA); // ソフトホワイト
  static const Color gridLines = Color(0xFFE2E8F0); // ライトグレー
  static const Color axisLabel = Color(0xFF4A5568); // ダークグレー

  // 陽線/陰線
  static const Color bullish = Color(0xFF276749); // フォレストグリーン
  static const Color bearish = Color(0xFFC53030); // プロフェッショナルレッド

  // ボリンジャーバンド（グレートーン系）
  static const Color bbMiddle = Color(0xFF718096); // ミディアムグレー
  static const Color bb1Sigma = Color(0xFF94A3B8); // ライトグレー
  static const Color bb2Sigma = Color(0xFFA0AEC0); // ベリーライトグレー

  // EMA（ネイビーブルートーン系）
  static const Color emaShort = Color(0xFF4299E1); // ライトブルー
  static const Color emaMedium = Color(0xFF3182CE); // ミディアムブルー
  static const Color emaLong = Color(0xFF2C5282); // ダークブルー

  // フィードバックカラー
  static const Color success = Color(0xFF276749); // フォレストグリーン
  static const Color error = Color(0xFFC53030); // プロフェッショナルレッド
  static const Color errorLight = Color(0xFFFED7D7); // ライトレッド背景
  static const Color warning = Color(0xFFD69E2E); // アンバー
  static const Color info = Color(0xFF2C5282); // ネイビーブルー
}

/// カテゴリー別のカラーユーティリティ
/// Note: MarketCategoryはhome_screen.dartで定義されているenumを使用
class CategoryColors {
  CategoryColors._(); // プライベートコンストラクタ

  /// カテゴリー名からプライマリカラーを取得
  static Color forCategoryName(String categoryName) {
    switch (categoryName.toLowerCase()) {
      case 'crypto':
        return AppColors.cryptoPrimary;
      case 'forex':
        return AppColors.forexPrimary;
      case 'stock':
        return AppColors.stockPrimary;
      default:
        return AppColors.primary;
    }
  }

  /// カテゴリー名からアクセントカラーを取得
  static Color accentForCategoryName(String categoryName) {
    switch (categoryName.toLowerCase()) {
      case 'crypto':
        return AppColors.cryptoAccent;
      case 'forex':
        return AppColors.forexAccent;
      case 'stock':
        return AppColors.stockAccent;
      default:
        return AppColors.primary;
    }
  }

  /// カテゴリー名から背景カラーを取得
  static Color backgroundForCategoryName(String categoryName) {
    switch (categoryName.toLowerCase()) {
      case 'crypto':
        return AppColors.cryptoLight;
      case 'forex':
        return AppColors.forexLight;
      case 'stock':
        return AppColors.stockLight;
      default:
        return AppColors.background;
    }
  }
}
