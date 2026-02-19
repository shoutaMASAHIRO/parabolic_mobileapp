import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';

class EarningsScreen extends StatelessWidget {
  final String symbol;
  final String earnings;
  final Map<String, dynamic>? rawData;

  const EarningsScreen({
    super.key,
    required this.symbol,
    required this.earnings,
    this.rawData,
  });

  @override
  Widget build(BuildContext context) {
    final latest = rawData?['latest'] ?? {};
    final hasData = latest.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppHeader(
        title: '直近の決算内容',
        showBackButton: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailCard(
              title: symbol,
              content: hasData ? '決算期: ${latest['DiscloseDate'] ?? '不明'}' : earnings,
              description: 'J-Quants API から取得した最新の財務報告内容です。企業の収益性、成長性、および財務健全性を判断するための重要な指標が含まれます。',
            ),
            const SizedBox(height: 24),
            if (hasData)
              _buildInfoSection('決算詳細 (実数値)', [
                '売上高: ${NumberFormat("#,###").format(double.tryParse(latest['NetSales']?.toString() ?? '0') ?? 0)} 円',
                '営業利益: ${NumberFormat("#,###").format(double.tryParse(latest['OperatingProfit']?.toString() ?? '0') ?? 0)} 円',
                '経常利益: ${NumberFormat("#,###").format(double.tryParse(latest['OrdinaryProfit']?.toString() ?? '0') ?? 0)} 円',
                '当期純利益: ${NumberFormat("#,###").format(double.tryParse(latest['Profit']?.toString() ?? '0') ?? 0)} 円',
                '1株利益(EPS): ${latest['EarningsPerShare'] ?? '--'} 円',
              ])
            else
              _buildInfoSection('追加情報', [
                '収益のサプライズ分析',
                'ガイダンスの修正状況',
                'キャッシュフローの推移',
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
              const Icon(Icons.description, color: AppColors.primary, size: 20),
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
