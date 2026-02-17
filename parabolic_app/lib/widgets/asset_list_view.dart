import 'package:flutter/material.dart';
import 'dart:math';
import '../models/chart_configs.dart';
import '../theme/app_colors.dart';
import '../widgets/rate_list_item.dart';
import '../screens/detail_screen.dart';
import '../screens/home_screen.dart' show MarketCategory;
import '../services/stock_service.dart';

class AssetListView extends StatefulWidget {
  final MarketCategory category;
  final List<dynamic> data;
  final Set<String> notifiedSymbols;
  final Set<String> favoriteSymbols;
  final Future<void> Function() onRefresh;
  final VoidCallback onAddPressed;
  final bool showAddButton;

  const AssetListView({
    super.key,
    required this.category,
    required this.data,
    required this.notifiedSymbols,
    required this.favoriteSymbols,
    required this.onRefresh,
    required this.onAddPressed,
    this.showAddButton = true,
  });

  @override
  State<AssetListView> createState() => _AssetListViewState();
}

class _AssetListViewState extends State<AssetListView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _deleteAsset(BuildContext context, String symbol) async {
    final assetService = AssetService();
    bool success = false;
    
    switch (widget.category) {
      case MarketCategory.crypto: success = await assetService.hideCrypto(symbol); break;
      case MarketCategory.forex: success = await assetService.hideForex(symbol); break;
      case MarketCategory.stock: success = await assetService.hideStock(symbol); break;
    }

    if (success) {
      widget.onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$symbol を削除しました'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _toggleFavorite(BuildContext context, String symbol, String displayName) async {
    final assetService = AssetService();
    final success = await assetService.toggleFavorite(
      symbol, 
      true, 
      displayName: displayName,
      category: widget.category.name,
    );
    if (success && context.mounted) {
      widget.onRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$symbol をお気に入りに追加しました'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.background,
          child: const Row(
            children: [
              Expanded(flex: 3, child: Text('銘柄', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
              Expanded(flex: 4, child: Text('現在値', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
              Expanded(flex: 3, child: Text('前日比', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
            ],
          ),
        ),
        Expanded(
          child: widget.data.isEmpty
              ? Center(child: Text('${widget.category.label}データがありません'))
              : RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: RawScrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    thickness: 4,
                    radius: const Radius.circular(2),
                    thumbColor: Colors.grey.withOpacity(0.5),
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: widget.data.length,
                      itemBuilder: (context, index) {
                        final item = widget.data[index];
                        final symbol = item is Map ? item['symbol'] as String : item.toString();
                        final displayName = item is Map
                            ? item['displayName'] as String
                            : symbol.replaceAll('-USD', '');
                        
                        final random = Random(symbol.hashCode);
                        final price = _generateMockPrice(widget.category, random);
                        final change = _generateMockChange(price, random);
                        final changePercent = _generateMockChangePercent(change, price);

                        return Dismissible(
                          key: Key(symbol),
                          direction: DismissDirection.horizontal,
                          secondaryBackground: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            color: AppColors.error,
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            color: AppColors.success,
                            child: const Icon(Icons.star, color: Colors.white),
                          ),
                          onDismissed: (direction) {
                            if (direction == DismissDirection.endToStart) {
                              _deleteAsset(context, symbol);
                            } else {
                              _toggleFavorite(context, symbol, displayName);
                              widget.onRefresh();
                            }
                          },
                          confirmDismiss: (direction) async {
                            if (direction == DismissDirection.endToStart) {
                              return await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: AppColors.surface,
                                  title: const Text('銘柄の削除', style: TextStyle(color: Colors.white)),
                                  content: Text('$displayName をリストから削除しますか？', style: const TextStyle(color: AppColors.textSecondary)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
                                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除', style: TextStyle(color: AppColors.error))),
                                  ],
                                ),
                              );
                            }
                            return true;
                          },
                          child: RateListItem(
                            symbol: symbol,
                            name: displayName,
                            price: price,
                            change: change,
                            changePercent: changePercent,
                            icon: widget.category.icon,
                            iconColor: CategoryColors.forCategoryName(widget.category.name),
                            hasNotification: widget.notifiedSymbols.contains(symbol),
                            isFavorite: widget.favoriteSymbols.contains(symbol),
                            onTap: () async {
                              await Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(
                                  builder: (_) => DetailScreen(
                                    symbol: symbol,
                                    category: widget.category,
                                  ),
                                ),
                              );
                              widget.onRefresh();
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
        if (widget.showAddButton)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onAddPressed,
                icon: const Icon(Icons.add),
                label: Text('${widget.category.label}を追加'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _generateMockPrice(MarketCategory category, Random random) {
    switch (category) {
      case MarketCategory.crypto:
        if (random.nextBool()) {
          return '¥${(4000000 + random.nextInt(5000000)).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
        } else {
          return '¥${(1000 + random.nextInt(90000)).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
        }
      case MarketCategory.forex:
        return '${(100 + random.nextInt(50))}.${(random.nextInt(99)).toString().padLeft(2, '0')}';
      case MarketCategory.stock:
        return '¥${(1000 + random.nextInt(9000)).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
    }
  }

  String _generateMockChange(String priceStr, Random random) {
     double priceVal = double.tryParse(priceStr.replaceAll('¥', '').replaceAll(',', '')) ?? 1000;
     double change = priceVal * (random.nextDouble() * 0.04 - 0.02);
     String sign = change >= 0 ? '+' : '';
     return '$sign${change.toStringAsFixed(priceStr.contains('.') ? 2 : 0)}';
  }

   String _generateMockChangePercent(String changeStr, String priceStr) {
     double change = double.tryParse(changeStr) ?? 0;
     double price = double.tryParse(priceStr.replaceAll('¥', '').replaceAll(',', '')) ?? 1000;
     double percent = (change / price) * 100;
     String sign = percent >= 0 ? '+' : '';
     return '$sign${percent.toStringAsFixed(2)}%';
  }
}
