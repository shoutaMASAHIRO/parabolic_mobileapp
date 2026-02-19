import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';

class MorningstarRatingScreen extends StatelessWidget {
  final String symbol;
  final String rating;

  const MorningstarRatingScreen({
    super.key,
    required this.symbol,
    required this.rating,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppHeader(
        title: 'モーニングスター格付け',
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
              description: 'モーニングスターによる企業の財務状況、収益性、競争優位性、不確実性などの定性・定量分析に基づく評価です。格付けは将来の収益を保証するものではありません。',
            ),
            const SizedBox(height: 24),
            _buildInfoSection('評価のポイント', [
              'フェアバリュー（適正株価）に対する現在の乖離度',
              'ビジネスモデルの堅牢性（堀/Economic Moat）',
              '資本配分の質',
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
              const Icon(Icons.check_circle_outline, color: AppColors.primary, size: 20),
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
