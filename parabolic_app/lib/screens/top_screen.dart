import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_header.dart';
import 'home_screen.dart' show MarketCategory;

class TopScreen extends StatelessWidget {
  final Function(MarketCategory) onCategorySelected;
  final VoidCallback onEmailSettingsPressed;

  const TopScreen({
    super.key,
    required this.onCategorySelected,
    required this.onEmailSettingsPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('マーケット', style: AppTextStyles.headline3),
          const SizedBox(height: 16),
          _buildCategoryCard(
            context,
            category: MarketCategory.crypto,
            description: 'ビットコイン、イーサリアムなど',
            color: AppColors.crypto,
          ),
          const SizedBox(height: 16),
          _buildCategoryCard(
            context,
            category: MarketCategory.forex,
            description: 'ドル円、ユーロ円など',
            color: AppColors.forex,
          ),
          const SizedBox(height: 16),
          _buildCategoryCard(
            context,
            category: MarketCategory.stock,
            description: '日本株、米国株など',
            color: AppColors.stock,
          ),
          
          const SizedBox(height: 40),
          const Text('通知・設定', style: AppTextStyles.headline3),
          const SizedBox(height: 16),
          _buildSettingsCard(
            context,
            title: 'メールアドレス登録',
            description: 'アラート通知をメールで受け取ります',
            icon: Icons.alternate_email,
            color: AppColors.primary,
            onTap: onEmailSettingsPressed,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context, {
    required MarketCategory category,
    required String description,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onCategorySelected(category),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // カテゴリーを象徴する左側のカラーバー
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // アイコン
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(category.icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.label,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: AppColors.textTertiary, size: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          description,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_right, color: AppColors.textTertiary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
