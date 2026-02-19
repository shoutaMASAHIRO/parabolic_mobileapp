import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';

class AnalystRatingScreen extends StatelessWidget {
  final String symbol;
  final String rating;

  const AnalystRatingScreen({
    super.key,
    required this.symbol,
    required this.rating,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppHeader(
        title: 'アナリスト評価',
        showBackButton: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailCard(
              title: symbol,
              content: rating,
              description: '主要証券会社や独立系アナリストによる投資判断の平均的な評価です。目標株価はアナリスト各社の平均値または中央値を表しています。',
            ),
            const SizedBox(height: 24),
            _buildInfoSection('コンセンサス推移', [
              '過去3ヶ月の投資判断の平均: 強気',
              '目標株価の変更履歴',
              'アナリスト数の増減',
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard({
    required String title,
    required String content,
    required String description,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            content,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.show_chart, color: AppColors.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}
