import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/market_data_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/app_header.dart';
import 'login_screen.dart';
import 'favorites_screen.dart';
import 'top_screen.dart';
import 'market_list_screen.dart';
import 'alert_symbols_screen.dart';
import '../services/chart_service.dart';

// カテゴリ定義
enum MarketCategory {
  crypto('暗号資産', Icons.currency_bitcoin),
  forex('外国為替', Icons.currency_exchange),
  stock('株式', Icons.show_chart);

  final String label;
  final IconData icon;
  const MarketCategory(this.label, this.icon);
}

class HomeScreen extends StatefulWidget {
  final MarketCategory? initialCategory;
  const HomeScreen({super.key, this.initialCategory});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  MarketCategory? _selectedCategory;
  final ChartService _chartService = ChartService();
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: MarketCategory.values.length, vsync: this);

    // データの初期ロード
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<MarketDataProvider>().refreshAllData();
      }
    });

    // 初期カテゴリが指定されていればセットする
    if (widget.initialCategory != null) {
      _selectedCategory = widget.initialCategory;
      _tabController!.index = widget.initialCategory!.index;
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    await context.read<AuthProvider>().logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Future<void> _showEmailRegistrationDialog() async {
    // 現在登録されているメールアドレスを取得（GLOBALとして取得）
    final existingEmails = await _chartService.getEmails(symbol: 'GLOBAL');
    final controller = TextEditingController(
      text: existingEmails.isNotEmpty ? existingEmails.first : '',
    );

    if (!mounted) return;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('メールアドレス登録', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('アラート通知を受け取るメールアドレスを入力してください。', 
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'example@mail.com',
                hintStyle: const TextStyle(color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('登録する', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final success = await _chartService.registerEmail(email: result, symbol: 'GLOBAL');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'メールアドレスを登録しました' : '登録に失敗しました'),
            backgroundColor: success ? AppColors.success : AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ホットリロード等で未初期化の場合に備える
    _tabController ??= TabController(length: MarketCategory.values.length, vsync: this);
    
    final bool showTabs = _selectedCategory != null || _currentIndex == 1 || _currentIndex == 2;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppHeader(
        showBackButton: _selectedCategory != null,
        onBack: () => setState(() => _selectedCategory = null),
        bottom: showTabs ? _buildTabBar() : null,
      ),
      body: _buildBody(),
      bottomNavigationBar: Container(
        height: 100, 
        padding: const EdgeInsets.only(bottom: 10),
        decoration: const BoxDecoration(
          color: AppColors.surface, 
          border: Border(top: BorderSide(color: AppColors.divider, width: 1.0))
        ),
        child: Row(
          children: [
            _buildFooterItem(
              icon: Icons.home, 
              label: 'ホーム', 
              isSelected: _currentIndex == 0 && _selectedCategory == null,
              onTap: () => setState(() {
                _currentIndex = 0;
                _selectedCategory = null;
              }),
            ),
            _buildFooterItem(
              icon: Icons.star, 
              label: '保有/お気に入り', 
              isSelected: _currentIndex == 1,
              onTap: () => setState(() {
                _currentIndex = 1;
                _selectedCategory = null;
              }),
            ),
            _buildFooterItem(
              icon: Icons.notifications_active, 
              label: '通知銘柄', 
              isSelected: _currentIndex == 2,
              onTap: () => setState(() {
                _currentIndex = 2;
                _selectedCategory = null;
              }),
            ),
            _buildFooterItem(
              icon: Icons.category_outlined, 
              label: 'カテゴリー', 
              isSelected: false, 
              onTap: _showCategorySelection,
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor: AppColors.primary,
      indicatorWeight: 3,
      tabs: MarketCategory.values.map((cat) {
        Color iconColor;
        switch (cat) {
          case MarketCategory.crypto: iconColor = AppColors.crypto; break;
          case MarketCategory.forex: iconColor = AppColors.forex; break;
          case MarketCategory.stock: iconColor = AppColors.stock; break;
        }
        return Tab(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(cat.icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(cat.label),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFooterItem({required IconData icon, required String label, bool isSelected = false, VoidCallback? onTap}) {
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
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCategorySelection() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('カテゴリー選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 24),
              ...MarketCategory.values.map((cat) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _currentIndex = 0; // ホームタブを表示
                      _selectedCategory = cat; // その中の銘柄一覧を表示
                      _tabController?.index = cat.index;
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          cat.icon, 
                          color: cat == MarketCategory.crypto 
                              ? AppColors.crypto 
                              : (cat == MarketCategory.forex ? AppColors.forex : AppColors.stock)
                        ),
                        const SizedBox(width: 16),
                        Text(cat.label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        const Icon(Icons.arrow_forward_ios, color: AppColors.textTertiary, size: 14),
                      ],
                    ),
                  ),
                ),
              )).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_selectedCategory != null) {
      return MarketListScreen(
        initialCategory: _selectedCategory!,
        tabController: _tabController!,
        onBack: () => setState(() => _selectedCategory = null),
      );
    }

    switch (_currentIndex) {
      case 0:
        return TopScreen(
          onCategorySelected: (category) {
            setState(() {
              _selectedCategory = category;
              _tabController?.index = category.index;
            });
          },
          onEmailSettingsPressed: _showEmailRegistrationDialog,
        );
      case 1:
        return FavoritesScreen(
          tabController: _tabController!,
          onBack: () => setState(() => _currentIndex = 0),
        );
      case 2:
        return AlertSymbolsScreen(
          tabController: _tabController!,
          onBack: () => setState(() => _currentIndex = 0),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
