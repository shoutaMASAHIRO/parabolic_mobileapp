import 'package:flutter/material.dart';
import 'app_colors.dart';

/// アプリケーション全体のタイポグラフィ設定
class AppTextStyles {
  AppTextStyles._(); // プライベートコンストラクタ

  // ヘッドライン
  static const TextStyle headline1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle headline2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle headline3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // ボディテキスト
  static const TextStyle body1 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle body2 = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  // セカンダリテキスト
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  // キャプション
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // ボタン
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );

  // ラベル
  static const TextStyle label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  // チャート用テキスト
  static const TextStyle chartLabel = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.bold,
    color: AppColors.axisLabel,
  );

  static const TextStyle chartPrice = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
}
