import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/app_header.dart';
import '../services/analysis_service.dart';
import 'analysis/morningstar_rating_screen.dart';
import 'analysis/analyst_rating_screen.dart';
import 'analysis/earnings_screen.dart';
import 'analysis/performance_screen.dart';
import 'analysis/valuation_screen.dart';
import 'analysis/revenue_composition_screen.dart';

class AnalysisScreen extends StatefulWidget {
  final String symbol;
  const AnalysisScreen({super.key, required this.symbol});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final AnalysisService _analysisService = AnalysisService();
  Map<String, dynamic>? _analysisData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await _analysisService.getStockAnalysis(widget.symbol);
    if (mounted) {
      setState(() {
        _analysisData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppHeader(
        title: '分析 - ${widget.symbol}',
        showBackButton: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('企業・銘柄評価'),
                    _buildInfoCard(
                      title: 'モーニングスター格付け',
                      content: _analysisData?['morningstarRating'] ?? 'データなし',
                      icon: Icons.stars,
                      color: Colors.orange,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MorningstarRatingScreen(
                            symbol: widget.symbol,
                            rating: _analysisData?['morningstarRating'] ?? 'データなし',
                          ),
                        ),
                      ),
                    ),
                    _buildInfoCard(
                      title: 'アナリスト評価',
                      content: _analysisData?['analystRating'] ?? 'データなし',
                      icon: Icons.trending_up,
                      color: AppColors.primary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AnalystRatingScreen(
                            symbol: widget.symbol,
                            rating: _analysisData?['analystRating'] ?? 'データなし',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    _buildSectionTitle('業績・決算'),
                    _buildInfoCard(
                      title: '直近の決算内容',
                      content: _analysisData?['earnings'] ?? 'データなし',
                      icon: Icons.event_note,
                      color: AppColors.success,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EarningsScreen(
                            symbol: widget.symbol,
                            earnings: _analysisData?['earnings'] ?? 'データなし',
                          ),
                        ),
                      ),
                    ),
                    _buildInfoCard(
                      title: '直近業績',
                      content: _analysisData?['performance'] ?? 'データなし',
                      icon: Icons.bar_chart,
                      color: AppColors.info,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PerformanceScreen(
                            symbol: widget.symbol,
                            performance: _analysisData?['performance'] ?? 'データなし',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    _buildSectionTitle('構成・バリュエーション'),
                    _buildInfoCard(
                      title: '企業評価 (主要指標)',
                      content: _analysisData?['valuation'] ?? 'データなし',
                      icon: Icons.pie_chart_outline,
                      color: Colors.purple,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ValuationScreen(
                            symbol: widget.symbol,
                            valuation: _analysisData?['valuation'] ?? 'データなし',
                          ),
                        ),
                      ),
                    ),
                    _buildInfoCard(
                      title: '売り上げ構成',
                      content: _analysisData?['revenueComposition'] ?? 'データなし',
                      icon: Icons.account_balance,
                      color: Colors.teal,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RevenueCompositionScreen(
                            symbol: widget.symbol,
                            composition: _analysisData?['revenueComposition'] ?? 'データなし',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Center(
                      child: Text(
                        '※データは参考値であり、投資の助言ではありません。',
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String content,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.white.withOpacity(0.3),
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        content,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
