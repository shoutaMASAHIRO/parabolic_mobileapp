import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class DetailFooter extends StatelessWidget {
  final bool isChartMaximized;
  final VoidCallback onHomeTap;
  final VoidCallback onChartMaximizeTap;
  final VoidCallback onCategoryTap;

  const DetailFooter({
    super.key,
    required this.isChartMaximized,
    required this.onHomeTap,
    required this.onChartMaximizeTap,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100, 
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface, 
        border: Border(top: BorderSide(color: AppColors.divider, width: 1.0)),
      ),
      child: Row(
        children: [
          _buildFooterItem(
            icon: Icons.home, 
            label: 'ホーム', 
            onTap: onHomeTap,
          ),
          _buildFooterItem(
            icon: isChartMaximized ? Icons.fullscreen_exit : Icons.stacked_line_chart, 
            label: 'チャート', 
            isSelected: true,
            onTap: onChartMaximizeTap,
          ),
          _buildFooterItem(
            icon: Icons.category_outlined, 
            label: 'カテゴリー', 
            onTap: onCategoryTap,
          ),
        ],
      ),
    );
  }

  Widget _buildFooterItem({
    required IconData icon, 
    required String label, 
    bool isSelected = false, 
    VoidCallback? onTap,
  }) {
    final color = isSelected ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(
              label, 
              style: TextStyle(
                color: color, 
                fontSize: 11, 
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
