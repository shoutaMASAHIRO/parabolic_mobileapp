import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import '../models/chart_configs.dart';
import '../providers/market_data_provider.dart';
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
  final Set<String> _dismissedSymbols = {};

  @override
  void didUpdateWidget(AssetListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // データが更新されたら、削除済みリストをリセット（または実際に消えたか確認）
    // ここではシンプルに、新しいデータに削除済みシンボルが含まれていないことを期待
    _dismissedSymbols.removeWhere((s) => !widget.data.any((item) {
      final symbol = item is Map ? item['symbol'] as String : item.toString();
      return symbol == s;
    }));
  }

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
    final isCurrentlyFavorite = widget.favoriteSymbols.contains(symbol);
    final success = await assetService.toggleFavorite(
      symbol, 
      !isCurrentlyFavorite, // 現在の状態の逆にする
      displayName: displayName,
      category: widget.category.name,
    );
    if (success && context.mounted) {
      setState(() {
        if (isCurrentlyFavorite) {
          widget.favoriteSymbols.remove(symbol);
        } else {
          widget.favoriteSymbols.add(symbol);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isCurrentlyFavorite 
            ? '$symbol をお気に入りから削除しました' 
            : '$symbol をお気に入りに追加しました'),
          backgroundColor: isCurrentlyFavorite ? AppColors.error : AppColors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 削除済みのシンボルを除外して表示
    final displayData = widget.data.where((item) {
      final symbol = item is Map ? item['symbol'] as String : item.toString();
      return !_dismissedSymbols.contains(symbol);
    }).toList();

    // Provider から最新の価格情報を取得するために一度だけ watch
    final provider = context.watch<MarketDataProvider>();

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
          child: displayData.isEmpty
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
                      itemCount: displayData.length,
                      itemBuilder: (context, index) {
                        final item = displayData[index];
                        final symbol = item is Map ? item['symbol'] as String : item.toString();
                        final displayName = item is Map
                            ? item['displayName'] as String
                            : symbol.replaceAll('-USD', '');
                        
                        final priceInfo = provider.getPriceInfo(symbol);

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
                              setState(() {
                                _dismissedSymbols.add(symbol);
                              });
                              _deleteAsset(context, symbol);
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
                            } else if (direction == DismissDirection.startToEnd) {
                              // お気に入り登録の場合は、アクションだけ実行してスライドを戻す
                              _toggleFavorite(context, symbol, displayName);
                              return false;
                            }
                            return false;
                          },
                          child: RateListItem(
                            symbol: symbol,
                            name: displayName,
                            price: priceInfo['price']!,
                            change: priceInfo['change']!,
                            changePercent: priceInfo['percent']!,
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
}
