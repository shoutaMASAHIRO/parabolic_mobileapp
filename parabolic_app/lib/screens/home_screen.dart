import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
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
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  MarketCategory? _selectedCategory; // 追加：選択されたカテゴリを保持
  final ChartService _chartService = ChartService();

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
            child: const Text('登録する'),
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
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      // AppBarを削除し、各画面のAppBarを表示させる
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 3) {
            _showCategorySelection();
          } else {
            setState(() {
              _currentIndex = index;
              _selectedCategory = null; // タブ切り替え時に銘柄一覧状態を解除
            });
          }
        },
        type: BottomNavigationBarType.fixed, // 項目が増えたため固定表示に
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'ホーム'),
          BottomNavigationBarItem(icon: Icon(Icons.star), label: '保有/お気に入り'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_active), label: '通知銘柄'),
          BottomNavigationBarItem(icon: Icon(Icons.category_outlined), label: 'カテゴリー'),
        ],
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
                        Icon(cat.icon, color: AppColors.primaryLight),
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
        onBack: () => setState(() => _selectedCategory = null),
      );
    }

    switch (_currentIndex) {
      case 0:
        return TopScreen(
          onCategorySelected: (category) {
            setState(() => _selectedCategory = category);
          },
          onEmailSettingsPressed: _showEmailRegistrationDialog,
        );
      case 1:
        return FavoritesScreen(onBack: () => setState(() => _currentIndex = 0));
      case 2:
        return AlertSymbolsScreen(onBack: () => setState(() => _currentIndex = 0));
      case 3:
        return const Center(child: Text('カテゴリー選択', style: TextStyle(color: AppColors.textSecondary))); // ダイアログで表示
      default:
        return const SizedBox.shrink();
    }
  }
}
