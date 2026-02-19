import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class ChartTimerWidget extends StatelessWidget {
  final bool isRefreshing;
  final int secondsUntilRefresh;

  const ChartTimerWidget({
    super.key,
    required this.isRefreshing,
    required this.secondsUntilRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isRefreshing 
            ? AppColors.info 
            : (secondsUntilRefresh <= 10 ? AppColors.warning : AppColors.success),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRefreshing) 
            const SizedBox(
              width: 14, 
              height: 14, 
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          else 
            const Icon(Icons.timer, size: 16, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            isRefreshing ? '更新中' : '${secondsUntilRefresh}s', 
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
