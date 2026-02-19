import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';

class PerformanceScreen extends StatelessWidget {
  final String symbol;
  final String performance;
  final Map<String, dynamic>? rawData;

  const PerformanceScreen({
    super.key,
    required this.symbol,
    required this.performance,
    this.rawData,
  });

  @override
  Widget build(BuildContext context) {
    final latest = rawData?['latest'] ?? {};
    final hasData = latest.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppHeader(
        title: '直近業績',
        showBackButton: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailCard(
              title: symbol,
              content: hasData ? 'EPS: ${latest['EarningsPerShare'] ?? '--'} 円' : performance,
              description: '企業の収益性を示す主要な業績指標です。1株当たり利益(EPS)や営業利益の推移から、企業の成長ステージを判断することができます。',
            ),
            const SizedBox(height: 24),
            if (hasData)
              _buildInfoSection('業績詳細', [
                '1株利益(EPS): ${latest['EarningsPerShare'] ?? '--'} 円',
                '営業利益: ${latest['OperatingProfit'] ?? '--'} 円',
                '経常利益: ${latest['OrdinaryProfit'] ?? '--'} 円',
                '総資産: ${latest['TotalAssets'] ?? '--'} 円',
                '純資産: ${latest['NetAssets'] ?? '--'} 円',
              ])
            else
              _buildInfoSection('収益性分析', [
                '自己資本利益率 (ROE)',
                '総資産利益率 (ROA)',
                '営業利益率の推移',
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
              fontSize: 24,
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
              const Icon(Icons.bar_chart, color: AppColors.primary, size: 20),
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
