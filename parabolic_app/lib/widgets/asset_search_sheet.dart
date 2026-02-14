import 'package:flutter/material.dart';
import '../services/stock_service.dart';
import '../theme/app_colors.dart';
import '../screens/home_screen.dart' show MarketCategory;

class AssetSearchSheet extends StatefulWidget {
  final AssetService assetService;
  final MarketCategory category;
  final Set<String> currentSymbols;
  final VoidCallback onAssetAdded;

  const AssetSearchSheet({
    super.key,
    required this.assetService,
    required this.category,
    required this.currentSymbols,
    required this.onAssetAdded,
  });

  @override
  State<AssetSearchSheet> createState() => _AssetSearchSheetState();
}

class _AssetSearchSheetState extends State<AssetSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String? _lastQuery;
  Set<String> _localCurrentSymbols = {};

  @override
  void initState() {
    super.initState();
    _localCurrentSymbols = Set.from(widget.currentSymbols);
  }

  String get _title {
    switch (widget.category) {
      case MarketCategory.crypto: return '暗号通貨を検索';
      case MarketCategory.forex: return '為替ペアを検索';
      case MarketCategory.stock: return '銘柄を検索';
    }
  }

  String get _hintText {
    switch (widget.category) {
      case MarketCategory.crypto: return 'BTC, Bitcoinなど';
      case MarketCategory.forex: return 'USD, JPYなど';
      case MarketCategory.stock: return '銘柄コード, 会社名';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() { _searchResults = []; _isSearching = false; });
      return;
    }
    if (query == _lastQuery) return;
    _lastQuery = query;
    setState(() { _isSearching = true; });

    List<Map<String, dynamic>> results;
    switch (widget.category) {
      case MarketCategory.crypto: results = await widget.assetService.searchCrypto(query); break;
      case MarketCategory.forex: results = await widget.assetService.searchForex(query); break;
      case MarketCategory.stock: results = await widget.assetService.searchStocks(query); break;
    }

    if (_lastQuery != query) return;
    if (mounted) {
      setState(() { _searchResults = results; _isSearching = false; });
    }
  }

  Future<bool> _addAsset(String symbol, String displayName, String description) async {
    switch (widget.category) {
      case MarketCategory.crypto: return widget.assetService.addCrypto(symbol: symbol, displayName: displayName, description: description);
      case MarketCategory.forex: return widget.assetService.addForex(symbol: symbol, displayName: displayName, description: description);
      case MarketCategory.stock: return widget.assetService.addStock(symbol: symbol, displayName: displayName, description: description);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _hintText,
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, color: AppColors.textSecondary), onPressed: () { _searchController.clear(); _performSearch(''); }) : null,
              ),
              onChanged: (value) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (_searchController.text == value) _performSearch(value);
                });
                setState(() {});
              },
            ),
            const SizedBox(height: 16),
            if (_isSearching) const LinearProgressIndicator(color: AppColors.primary)
            else if (_searchResults.isNotEmpty)
              Flexible(
                child: Container(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final item = _searchResults[index];
                      final symbol = item['symbol'];
                      final name = item['displayName'];
                      final isAdded = _localCurrentSymbols.contains(symbol);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text(symbol, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        trailing: isAdded
                            ? const Icon(Icons.check_circle, color: AppColors.success)
                            : FilledButton(
                                onPressed: () async {
                                  final success = await _addAsset(symbol, name, item['description'] ?? '');
                                  if (success && mounted) {
                                    setState(() {
                                      _localCurrentSymbols.add(symbol);
                                    });
                                    widget.onAssetAdded();
                                  }
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('追加'),
                              ),
                      );
                    },
                  ),
                ),
              ),
            if (_searchResults.isEmpty && _searchController.text.isNotEmpty && !_isSearching)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('該当する銘柄が見つかりません', style: TextStyle(color: AppColors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}
