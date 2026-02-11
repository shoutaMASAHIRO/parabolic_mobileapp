import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class RateListItem extends StatelessWidget {
  final String symbol;
  final String name;
  final String price;
  final String change; // e.g., "+100", "-50"
  final String changePercent; // e.g., "+1.5%", "-0.8%"
  final IconData? icon;
  final Color? iconColor;
  final bool hasNotification;
  final VoidCallback? onTap;

  const RateListItem({
    super.key,
    required this.symbol,
    required this.name,
    required this.price,
    required this.change,
    required this.changePercent,
    this.icon,
    this.iconColor,
    this.hasNotification = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 騰落判定
    final isPositive = change.startsWith('+');
    final isNegative = change.startsWith('-');


    final changeColor = isPositive
        ? AppColors.rise
        : isNegative
            ? AppColors.fall
            : AppColors.unchanged;

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.divider, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 1. アイコン
            if (icon != null) ...[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (iconColor ?? AppColors.primary).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: iconColor ?? AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
            ],

            // 2. 銘柄名 & シンボル
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasNotification) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.notifications_active,
                          size: 14,
                          color: AppColors.warning,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    symbol,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // 3. 価格
            Expanded(
              flex: 4,
              child: Text(
                price,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: changeColor, // 価格も色付けする（GMOスタイル）
                  fontFamily: 'RobotoMono', // 等幅フォントっぽく
                ),
              ),
            ),

            // 4. 前日比
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: changeColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      changePercent,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    change,
                    style: TextStyle(
                      fontSize: 11,
                      color: changeColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
