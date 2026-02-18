import 'dart:async';
import 'package:flutter/material.dart';
import '../services/stock_service.dart';
import '../services/chart_service.dart';
import '../screens/home_screen.dart' show MarketCategory;

class MarketDataProvider with ChangeNotifier {
  final AssetService _assetService = AssetService();
  final ChartService _chartService = ChartService();
  Timer? _refreshTimer;
  Timer? _priceUpdateTimer;

  List<dynamic> _cryptoData = [];
  List<dynamic> _forexData = [];
  List<dynamic> _stockData = [];

  final Map<String, double> _currentPrices = {};
  final Map<String, double> _priceChanges = {};
  final Map<String, double> _priceChangePercents = {};

  final Map<String, Map<String, double>> _thresholdsCache = {};
  final Set<String> _favoriteSymbols = {};
  final Set<String> _notifiedSymbols = {};

  double _usdJpyRate = 150.0; // デフォルト値（取得失敗時のフォールバック）
  bool _isLoading = false;
  DateTime? _lastFetchTime;
  DateTime? _lastPriceFetchTime;

  List<dynamic> get cryptoData => _cryptoData;
  List<dynamic> get forexData => _forexData;
  List<dynamic> get stockData => _stockData;
  bool get isLoading => _isLoading;
  Set<String> get favoriteSymbols => _favoriteSymbols;
  Set<String> get notifiedSymbols => _notifiedSymbols;

  MarketDataProvider() {
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _priceUpdateTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _priceUpdateTimer?.cancel();

    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      refreshAllData();
    });

    _priceUpdateTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      _updateAllPrices();
    });
  }

  Future<void> refreshAllData({bool force = false}) async {
    if (!force && _lastFetchTime != null && 
        DateTime.now().difference(_lastFetchTime!) < const Duration(seconds: 25)) {
      return;
    }

    if (force && _cryptoData.isEmpty) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final results = await Future.wait([
        _assetService.getCryptoTickers(),
        _assetService.getForexTickers(),
        _assetService.getStockTickers(),
        _assetService.getFavorites(),
        _chartService.getUsdJpyRate(), // ドル円レートも取得
      ]);

      _cryptoData = results[0] as List<dynamic>;
      _forexData = results[1] as List<dynamic>;
      _stockData = results[2] as List<dynamic>;
      
      _favoriteSymbols.clear();
      final favorites = results[3] as List<dynamic>;
      for (var item in favorites) {
        _favoriteSymbols.add(item['symbol'] as String);
      }

      if (results[4] != null) {
        _usdJpyRate = results[4] as double;
      }

      _lastFetchTime = DateTime.now();
      _updateAllPrices(force: true);
      
    } catch (e) {
      debugPrint('MarketDataProvider refreshAllData Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _updateAllPrices({bool force = false}) async {
    if (!force && _lastPriceFetchTime != null && 
        DateTime.now().difference(_lastPriceFetchTime!) < const Duration(seconds: 30)) {
      return;
    }

    final allSymbols = {
      ..._cryptoData.map((e) => e['symbol'] as String),
      ..._forexData.map((e) => e['symbol'] as String),
      ..._stockData.map((e) => e['symbol'] as String),
      ..._favoriteSymbols,
    }.where((s) => s.isNotEmpty).toList();

    if (allSymbols.isEmpty) return;
    _lastPriceFetchTime = DateTime.now();

    // 最新のドル円レートを更新
    final rate = await _chartService.getUsdJpyRate();
    if (rate != null) {
      _usdJpyRate = rate;
    }

    await Future.wait(allSymbols.map((symbol) async {
      try {
        final candles = await _chartService.getChartData(symbol, interval: '1d', limit: 2)
            .timeout(const Duration(seconds: 10));
            
        if (candles.isNotEmpty) {
          final latest = candles.last;
          _currentPrices[symbol] = latest.close;
          
          if (candles.length > 1) {
            final prev = candles[candles.length - 2];
            final diff = latest.close - prev.close;
            _priceChanges[symbol] = diff;
            _priceChangePercents[symbol] = (diff / prev.close) * 100;
          }
        }
      } catch (e) {
        debugPrint('Failed to fetch price for $symbol: $e');
      }
    }));

    notifyListeners();
  }

  Map<String, String> getPriceInfo(String symbol) {
    double? rawPrice = _currentPrices[symbol];
    double rawChange = _priceChanges[symbol] ?? 0.0;
    final percent = _priceChangePercents[symbol] ?? 0.0;

    if (rawPrice == null) {
      return {'price': '---', 'change': '0', 'percent': '0%'};
    }

    // 暗号資産判定 (-USD)
    bool isCrypto = symbol.contains('-USD');
    // その他のドル建て（米国株など）判定
    bool isOtherUsdBased = !isCrypto && (!symbol.endsWith('.T') && !symbol.endsWith('=X') && !symbol.contains('-USD'));
    
    double displayPrice = rawPrice;
    double displayChange = rawChange;
    String currencyPrefix = '¥';

    if (isCrypto) {
      // 暗号資産はドルのまま表示
      currencyPrefix = '\$';
    } else if (isOtherUsdBased) {
      // 米国株などは日本円に換算
      displayPrice = rawPrice * _usdJpyRate;
      displayChange = rawChange * _usdJpyRate;
    }

    String formattedPrice = '$currencyPrefix${_formatNumber(displayPrice, decimalPlaces: displayPrice < 100 ? 2 : (isCrypto ? 2 : 0))}';
    
    // 為替ペアの場合は記号なし
    if (symbol.endsWith('=X')) {
      formattedPrice = displayPrice.toStringAsFixed(2);
    }

    final sign = displayChange >= 0 ? '+' : '';
    String formattedChange = '$sign${_formatNumber(displayChange.abs(), decimalPlaces: displayChange.abs() < 10 ? 2 : 0)}';

    return {
      'price': formattedPrice,
      'change': formattedChange,
      'percent': '$sign${percent.toStringAsFixed(2)}%',
    };
  }

  String _formatNumber(double number, {int decimalPlaces = 0}) {
    if (decimalPlaces > 0) {
      String parts = number.toStringAsFixed(decimalPlaces);
      List<String> split = parts.split('.');
      String integerPart = split[0].replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
      return '$integerPart.${split[1]}';
    } else {
      return number.round().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    }
  }

  void updateSymbolCache(String symbol, Map<String, double> thresholds) {
    _thresholdsCache[symbol] = thresholds;
    if (thresholds['favorite'] == 1.0) _favoriteSymbols.add(symbol);
    else _favoriteSymbols.remove(symbol);
    if (thresholds.keys.any((k) => k != 'favorite')) _notifiedSymbols.add(symbol);
    else _notifiedSymbols.remove(symbol);
    notifyListeners();
  }

  List<dynamic> getDataByCategory(MarketCategory category) {
    switch (category) {
      case MarketCategory.crypto: return _cryptoData;
      case MarketCategory.forex: return _forexData;
      case MarketCategory.stock: return _stockData;
    }
  }
}
