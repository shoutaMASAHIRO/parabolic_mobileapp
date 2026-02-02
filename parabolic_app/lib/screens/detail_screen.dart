import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/candle.dart';
import '../providers/auth_provider.dart';
import '../services/chart_service.dart';
import '../services/cross_detection_service.dart';
import '../theme/app_colors.dart';
import 'memo_screen.dart';
import 'home_screen.dart' show MarketCategory;

// チャートタイプ
enum ChartType { line, candlestick, heikinAshi }

// インジケーター設定クラス
class IndicatorSettings {
  bool enabled;
  final Map<String, dynamic> params;

  IndicatorSettings({
    this.enabled = false,
    Map<String, dynamic>? params,
  }) : params = params ?? {};

  IndicatorSettings copyWith({bool? enabled, Map<String, dynamic>? params}) {
    return IndicatorSettings(
      enabled: enabled ?? this.enabled,
      params: params ?? Map.from(this.params),
    );
  }
}

class DetailScreen extends StatefulWidget {
  final String symbol;
  final MarketCategory category;

  const DetailScreen({
    super.key,
    required this.symbol,
    this.category = MarketCategory.crypto,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final ChartService _chartService = ChartService();
  List<Candle> _candles = [];
  bool _isLoading = true;
  String? _error;
  String _interval = '1d';
  ChartType _chartType = ChartType.candlestick;

  // 自動更新タイマー（60秒間隔）
  static const int _refreshIntervalSeconds = 60;
  Timer? _countdownTimer;
  int _secondsUntilRefresh = _refreshIntervalSeconds;

  // チャートのズーム・パン状態
  // チャートのズーム・パン状態
  double _chartZoom = 1.0;
  double _chartPanOffsetX = 1.0; // 右端（最新データ）から表示開始
  double _chartPanOffsetY = 0.0;
  static const double _minZoom = 1.0;
  static const double _maxZoom = 8.0;
  double? _lastScaleStart;
  Offset? _lastFocalPoint;
  Offset? _lastTapPosition;

  // クロスヘア（タッチ位置表示）
  Offset? _crosshairPosition;
  int? _crosshairIndex;
  bool _showCrosshair = false;

  // インジケーター設定（パラメータ付き）
  final Map<String, IndicatorSettings> _indicators = {
    'bb': IndicatorSettings(
      enabled: false,
      params: {'period': 20, 'stdDev1': 1.0, 'stdDev2': 2.0},
    ),
    'ema': IndicatorSettings(
      enabled: false,
      params: {'period1': 10, 'period2': 25, 'period3': 50},
    ),
    // オシレーター
    'rsi': IndicatorSettings(
      enabled: false,
      params: {'period': 14},
    ),
    'macd': IndicatorSettings(
      enabled: false,
      params: {'fast': 12, 'slow': 26, 'signal': 9},
    ),
    'stochastic': IndicatorSettings(
      enabled: false,
      params: {'kPeriod': 14, 'dPeriod': 3, 'smooth': 3},
    ),
    'cci': IndicatorSettings(
      enabled: false,
      params: {'period': 20},
    ),
  };

  final List<String> _intervals = ['5m', '15m', '30m', '1h', '4h', '1d', '1wk', '1mo'];

  // 通貨表示切替（USD/JPY）
  bool _showJPY = false;
  double _usdJpyRate = 155.0; // デフォルト値（APIから取得して更新）

  // インジケーターのゲッター
  bool get _showBB => _indicators['bb']?.enabled ?? false;
  bool get _showEMA => _indicators['ema']?.enabled ?? false;
  bool get _showRSI => _indicators['rsi']?.enabled ?? false;
  bool get _showMACD => _indicators['macd']?.enabled ?? false;
  bool get _showStochastic => _indicators['stochastic']?.enabled ?? false;
  bool get _showCCI => _indicators['cci']?.enabled ?? false;

  // パラメータのゲッター（型安全に変換）
  int get _bbPeriod => _safeInt(_indicators['bb']?.params['period'], 20);
  double get _bbStdDev1 => _safeDouble(_indicators['bb']?.params['stdDev1'], 1.0);
  double get _bbStdDev2 => _safeDouble(_indicators['bb']?.params['stdDev2'], 2.0);
  int get _emaPeriod1 => _safeInt(_indicators['ema']?.params['period1'], 10);
  int get _emaPeriod2 => _safeInt(_indicators['ema']?.params['period2'], 25);
  int get _emaPeriod3 => _safeInt(_indicators['ema']?.params['period3'], 50);

  // オシレーターパラメータのゲッター
  int get _rsiPeriod => _safeInt(_indicators['rsi']?.params['period'], 14);
  int get _macdFast => _safeInt(_indicators['macd']?.params['fast'], 12);
  int get _macdSlow => _safeInt(_indicators['macd']?.params['slow'], 26);
  int get _macdSignal => _safeInt(_indicators['macd']?.params['signal'], 9);
  int get _stochKPeriod => _safeInt(_indicators['stochastic']?.params['kPeriod'], 14);
  int get _stochDPeriod => _safeInt(_indicators['stochastic']?.params['dPeriod'], 3);
  int get _stochSmooth => _safeInt(_indicators['stochastic']?.params['smooth'], 3);
  int get _cciPeriod => _safeInt(_indicators['cci']?.params['period'], 20);

  // 型安全なint変換
  static int _safeInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  // 型安全なdouble変換
  static double _safeDouble(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  // アクティブなインジケーター数
  int get _activeIndicatorCount => _indicators.values.where((v) => v.enabled).length;

  // クロス検知関連
  List<CrossEvent> _crossHistory = [];
  double? _threshold;
  bool _emailNotificationEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadIndicatorSettingsFromServer();
    _loadData(); // 為替レートもここで取得
    _loadCrossSettings();
    _startRefreshTimer();
  }

  // サーバーからインジケーター設定を読み込み（銘柄ごと）
  Future<void> _loadIndicatorSettingsFromServer() async {
    final settings = await _chartService.getIndicatorSettingsFromServer(widget.symbol);
    if (settings != null && mounted) {
      setState(() {
        _indicators['bb']!.enabled = settings['areBollingerBandsVisible'] == true;
        _indicators['ema']!.enabled = settings['areEmaVisible'] == true;
        _indicators['bb']!.params['period'] = _safeInt(settings['bbPeriod'], 20);
        _indicators['bb']!.params['stdDev2'] = _safeDouble(settings['bbStdDev'], 2.0);
        _indicators['ema']!.params['period1'] = _safeInt(settings['ema1Period'], 10);
        _indicators['ema']!.params['period2'] = _safeInt(settings['ema2Period'], 25);
        _indicators['ema']!.params['period3'] = _safeInt(settings['ema3Period'], 50);
        _emailNotificationEnabled = settings['emailAlertsEnabled'] == true;

        // オシレーター設定
        _indicators['rsi']!.enabled = settings['rsiEnabled'] == true;
        _indicators['rsi']!.params['period'] = _safeInt(settings['rsiPeriod'], 14);
        _indicators['macd']!.enabled = settings['macdEnabled'] == true;
        _indicators['macd']!.params['fast'] = _safeInt(settings['macdFast'], 12);
        _indicators['macd']!.params['slow'] = _safeInt(settings['macdSlow'], 26);
        _indicators['macd']!.params['signal'] = _safeInt(settings['macdSignal'], 9);
        _indicators['stochastic']!.enabled = settings['stochasticEnabled'] == true;
        _indicators['stochastic']!.params['kPeriod'] = _safeInt(settings['stochKPeriod'], 14);
        _indicators['stochastic']!.params['dPeriod'] = _safeInt(settings['stochDPeriod'], 3);
        _indicators['stochastic']!.params['smooth'] = _safeInt(settings['stochSmooth'], 3);
        _indicators['cci']!.enabled = settings['cciEnabled'] == true;
        _indicators['cci']!.params['period'] = _safeInt(settings['cciPeriod'], 20);
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  bool _isRefreshing = false;

  void _startRefreshTimer() {
    _countdownTimer?.cancel();

    // カウントダウンをリセット
    _secondsUntilRefresh = _refreshIntervalSeconds;

    // 1秒ごとにカウントダウンを更新
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      // 更新中はカウントダウンを止める
      if (_isRefreshing) return;

      // カウントダウンを減らす
      _secondsUntilRefresh--;

      // 0以下になったら更新処理を実行
      if (_secondsUntilRefresh <= 0) {
        _isRefreshing = true;
        setState(() {}); // 「更新中」表示

        _refreshChartData().then((_) {
          if (mounted) {
            setState(() {
              _secondsUntilRefresh = _refreshIntervalSeconds;
              _isRefreshing = false;
            });
          }
        });
      } else {
        setState(() {}); // カウントダウン表示更新
      }
    });
  }

  Future<void> _loadCrossSettings() async {
    // サーバーから閾値を取得
    final threshold = await _chartService.getThresholdFromServer(
      symbol: widget.symbol,
      interval: _interval,
    );

    // サーバーからクロス履歴を取得
    final serverHistory = await _chartService.getCrossHistoryFromServer(widget.symbol);
    final crossEvents = _parseServerCrossHistory(serverHistory, _interval);

    if (mounted) {
      setState(() {
        _crossHistory = crossEvents;
        _threshold = threshold;
      });
    }
  }

  // サーバーのクロス履歴をCrossEventリストに変換
  List<CrossEvent> _parseServerCrossHistory(Map<String, dynamic> serverHistory, String interval) {
    final events = <CrossEvent>[];

    // serverHistory[interval][indicatorName] = { price, timestamp, direction, lineValue, interval }
    final intervalData = serverHistory[interval] as Map<String, dynamic>?;
    if (intervalData == null) return events;

    for (final entry in intervalData.entries) {
      final indicatorName = entry.key;
      final data = entry.value as Map<String, dynamic>?;
      if (data == null) continue;

      final price = (data['price'] as num?)?.toDouble();
      final lineValue = (data['lineValue'] as num?)?.toDouble();
      final direction = data['direction'] as String?;
      final timestamp = data['timestamp'] as String?;

      if (price == null || timestamp == null) continue;

      events.add(CrossEvent(
        symbol: widget.symbol,
        interval: interval,
        type: indicatorName.startsWith('ema') ? CrossType.ema : CrossType.bb,
        indicatorName: indicatorName,
        price: price,
        lineValue: lineValue ?? price,
        direction: direction == 'up' ? CrossDirection.up : CrossDirection.down,
        timestamp: DateTime.parse(timestamp),
      ));
    }

    // タイムスタンプ降順でソート
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events;
  }

  // 初回ロード（ローディング表示あり）
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // APIから3年分のデータを取得する（という想定）
      final results = await Future.wait([
        _chartService.getChartData(widget.symbol, interval: _interval),
        _chartService.getUsdJpyRate(),
      ]);

      final candles = results[0] as List<Candle>;
      final rate = results[1] as double?;

      if (mounted) {
        setState(() {
          _candles = candles;
          if (rate != null) {
            _usdJpyRate = rate;
          }

          // 初期表示位置を右端（最新データ）に設定
          // データ数が基準表示数以下の場合は左端（0.0）に設定
          final baseVisible = _getBaseVisibleDataPoints();
          if (candles.length <= baseVisible) {
            _chartPanOffsetX = 0.0; // データが少ない場合は左端から表示
          } else {
            _chartPanOffsetX = 1.0; // データが多い場合は右端（最新）から表示
          }

          _isLoading = false;
        });

        // サーバーからクロス履歴を更新
        _refreshCrossHistory();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // 自動更新（ローディング表示なし、スムーズに更新）
  Future<void> _refreshChartData() async {
    final startTime = DateTime.now();
    debugPrint('[REFRESH] 開始: $startTime');

    try {
      // チャートデータと為替レートを並行取得
      final results = await Future.wait([
        _chartService.getChartData(widget.symbol, interval: _interval),
        _chartService.getUsdJpyRate(),
      ]);

      final candles = results[0] as List<Candle>;
      final rate = results[1] as double?;

      final fetchTime = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('[REFRESH] データ取得完了: ${fetchTime}ms, ${candles.length}本, レート: $rate');

      if (mounted && candles.isNotEmpty) {
        final lastCandle = candles.last;
        debugPrint('[REFRESH] 最新価格: ${lastCandle.close}');

        setState(() {
          _candles = candles;
          if (rate != null) {
            _usdJpyRate = rate;
          }
        });

        // サーバーからクロス履歴を更新
        _refreshCrossHistory();
      }
    } catch (e) {
      debugPrint('[REFRESH] エラー: $e');
    }

    final totalTime = DateTime.now().difference(startTime).inMilliseconds;
    debugPrint('[REFRESH] 完了: ${totalTime}ms');
  }

  // サーバーからクロス履歴を再取得
  Future<void> _refreshCrossHistory() async {
    final serverHistory = await _chartService.getCrossHistoryFromServer(widget.symbol);
    final crossEvents = _parseServerCrossHistory(serverHistory, _interval);

    if (mounted) {
      setState(() {
        _crossHistory = crossEvents;
      });
    }
  }


  // インジケーター設定をサーバーに同期
  Future<void> _syncIndicatorSettingsToServer() async {
    await _chartService.saveIndicatorSettingsToServer(
      symbol: widget.symbol,
      bbEnabled: _showBB,
      emaEnabled: _showEMA,
      bbPeriod: _bbPeriod,
      bbStdDev: _bbStdDev2,
      emaPeriod1: _emaPeriod1,
      emaPeriod2: _emaPeriod2,
      emaPeriod3: _emaPeriod3,
      emailAlertsEnabled: _emailNotificationEnabled,
      // オシレーター設定
      rsiEnabled: _showRSI,
      rsiPeriod: _rsiPeriod,
      macdEnabled: _showMACD,
      macdFast: _macdFast,
      macdSlow: _macdSlow,
      macdSignal: _macdSignal,
      stochasticEnabled: _showStochastic,
      stochKPeriod: _stochKPeriod,
      stochDPeriod: _stochDPeriod,
      stochSmooth: _stochSmooth,
      cciEnabled: _showCCI,
      cciPeriod: _cciPeriod,
    );
  }

  Future<void> _handleLogout() async {
    await context.read<AuthProvider>().logout();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Color _getCategoryColor() {
    switch (widget.category) {
      case MarketCategory.crypto:
        return AppColors.cryptoPrimary;
      case MarketCategory.forex:
        return AppColors.forexPrimary;
      case MarketCategory.stock:
        return AppColors.stockPrimary;
    }
  }

  // タイマーウィジェットを構築
  Widget _buildTimerWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _isRefreshing
            ? AppColors.info
            : _secondsUntilRefresh <= 10
                ? AppColors.warning
                : AppColors.success,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _isRefreshing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(
                  Icons.timer,
                  size: 16,
                  color: Colors.white,
                ),
          const SizedBox(width: 4),
          Text(
            _isRefreshing ? '更新中' : '${_secondsUntilRefresh}s',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // カテゴリに応じた表示名を生成
    String displayName;
    switch (widget.category) {
      case MarketCategory.crypto:
        displayName = widget.symbol.replaceAll('-USD', '');
        break;
      case MarketCategory.forex:
        displayName = widget.symbol
            .replaceAll('=X', '')
            .replaceAllMapped(RegExp(r'([A-Z]{3})([A-Z]{3})'), (m) => '${m[1]}/${m[2]}');
        break;
      case MarketCategory.stock:
        displayName = widget.symbol;
        break;
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(displayName),
        actions: [
          // インジケーター設定ボタン
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'インジケーター',
                onPressed: _showIndicatorSettings,
              ),
              if (_activeIndicatorCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$_activeIndicatorCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // クロス履歴/通知設定ボタン
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.notifications_outlined),
                if (_crossHistory.isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: 'クロス履歴・通知',
            onPressed: _showCrossSettings,
          ),
          // メモボタン
          IconButton(
            icon: const Icon(Icons.note_alt_outlined),
            tooltip: 'メモ',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MemoScreen(symbol: widget.symbol),
                ),
              );
            },
          ),
          // インターバル選択
          PopupMenuButton<String>(
            initialValue: _interval,
            onSelected: (value) {
              setState(() {
                _interval = value;
                _chartPanOffsetX = 0.0; // インターバル変更時にリセット
              });
              _loadData();
            },
            itemBuilder: (context) => _intervals
                .map((i) => PopupMenuItem(
                      value: i,
                      child: Text(_getIntervalLabel(i)),
                    ))
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Text(_getIntervalLabel(_interval)),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          // ログアウトボタン
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'ログアウト',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('ログアウト'),
                  content: const Text('ログアウトしますか？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('キャンセル'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _handleLogout();
                      },
                      child: const Text('ログアウト'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  String _getIntervalLabel(String interval) {
    switch (interval) {
      case '5m':
        return '5分';
      case '15m':
        return '15分';
      case '30m':
        return '30分';
      case '1h':
        return '1時間';
      case '4h':
        return '4時間';
      case '1d':
        return '1日';
      case '1wk':
        return '1週間';
      case '1mo':
        return '1ヶ月';
      default:
        return interval;
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('再試行'),
            ),
          ],
        ),
      );
    }

    if (_candles.isEmpty) {
      return const Center(child: Text('データがありません'));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 銘柄情報とタイマー
              _buildSymbolHeader(),
              const SizedBox(height: 12),
              _buildPriceHeader(),
              const SizedBox(height: 16),
              _buildChartTypeSelector(),
              // 暗号通貨・米国株の場合は通貨切替を表示（為替・日本株は不要）
              if (_shouldShowCurrencyToggle()) ...[
                const SizedBox(height: 8),
                _buildCurrencyToggle(),
              ],
              if (_activeIndicatorCount > 0) ...[
                const SizedBox(height: 8),
                _buildActiveIndicatorChips(),
              ],
              const SizedBox(height: 16),
              _buildChart(),
              const SizedBox(height: 24),
              _buildStats(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSymbolHeader() {
    // カテゴリに応じた表示名を生成
    String displayName;
    switch (widget.category) {
      case MarketCategory.crypto:
        displayName = widget.symbol.replaceAll('-USD', '');
        break;
      case MarketCategory.forex:
        // USDJPY=X → USD/JPY
        displayName = widget.symbol
            .replaceAll('=X', '')
            .replaceAllMapped(RegExp(r'([A-Z]{3})([A-Z]{3})'), (m) => '${m[1]}/${m[2]}');
        break;
      case MarketCategory.stock:
        displayName = widget.symbol;
        break;
    }

    return Row(
      children: [
        // カテゴリアイコン
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _getCategoryColor().withAlpha(30),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            widget.category.icon,
            size: 28,
            color: _getCategoryColor(),
          ),
        ),
        const SizedBox(width: 12),
        // 銘柄情報
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${widget.category.label} • ${widget.symbol}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        // タイマー
        _buildTimerWidget(),
      ],
    );
  }

  Widget _buildChartTypeSelector() {
    return Center(
      child: SegmentedButton<ChartType>(
        segments: const [
          ButtonSegment<ChartType>(
            value: ChartType.line,
            label: Text('折れ線'),
            icon: Icon(Icons.show_chart),
          ),
          ButtonSegment<ChartType>(
            value: ChartType.candlestick,
            label: Text('ローソク'),
            icon: Icon(Icons.candlestick_chart),
          ),
          ButtonSegment<ChartType>(
            value: ChartType.heikinAshi,
            label: Text('平均足'),
            icon: Icon(Icons.bar_chart),
          ),
        ],
        selected: {_chartType},
        onSelectionChanged: (Set<ChartType> newSelection) {
          setState(() {
            _chartType = newSelection.first;
          });
        },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  // 通貨切替ボタン（USD/JPY）
  Widget _buildCurrencyToggle() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCurrencyButton('USD', !_showJPY),
                _buildCurrencyButton('JPY', _showJPY),
              ],
            ),
          ),
          if (_showJPY) ...[
            const SizedBox(width: 8),
            Text(
              '(1\$ = ¥${_usdJpyRate.toStringAsFixed(2)})',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrencyButton(String currency, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showJPY = currency == 'JPY';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          currency,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // アクティブなインジケーターをチップで表示
  Widget _buildActiveIndicatorChips() {
    final activeIndicators = _indicators.entries.where((e) => e.value.enabled).toList();

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: activeIndicators.map((entry) {
        final config = _getIndicatorConfig(entry.key);
        final paramText = _getIndicatorParamText(entry.key);
        return Chip(
          label: Text(
            paramText.isNotEmpty ? '${config.name} ($paramText)' : config.name,
            style: TextStyle(color: config.color, fontSize: 12),
          ),
          backgroundColor: config.color.withAlpha(30),
          deleteIcon: Icon(Icons.close, size: 16, color: config.color),
          onDeleted: () {
            setState(() {
              _indicators[entry.key]!.enabled = false;
            });
          },
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      }).toList(),
    );
  }

  // インジケーターのパラメータテキストを取得
  String _getIndicatorParamText(String key) {
    switch (key) {
      case 'bb':
        return '$_bbPeriod';
      case 'ema':
        return '$_emaPeriod1/$_emaPeriod2/$_emaPeriod3';
      default:
        return '';
    }
  }

  // インジケーター設定ボトムシートを表示
  void _showIndicatorSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _IndicatorSettingsSheet(
        indicators: _indicators,
        onChanged: (key, settings) {
          setState(() {
            _indicators[key] = settings;
          });
          // サーバーに設定を同期
          _syncIndicatorSettingsToServer();
        },
        onToggle: (key, enabled) {
          setState(() {
            _indicators[key]!.enabled = enabled;
          });
          // サーバーに設定を同期
          _syncIndicatorSettingsToServer();
        },
      ),
    );
  }

  // クロス履歴・通知設定ボトムシートを表示
  void _showCrossSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CrossSettingsSheet(
        symbol: widget.symbol,
        interval: _interval,
        crossHistory: _crossHistory,
        threshold: _threshold,
        emailNotificationEnabled: _emailNotificationEnabled,
        currentPrice: _candles.isNotEmpty ? _candles.last.close : null,
        onThresholdChanged: (value) async {
          setState(() {
            _threshold = value;
          });
          // サーバーに閾値を保存
          await _chartService.saveThresholdToServer(
            symbol: widget.symbol,
            interval: _interval,
            threshold: value,
          );
        },
        onEmailNotificationChanged: (value) {
          setState(() {
            _emailNotificationEnabled = value;
          });
          // サーバーにメール通知設定を同期
          _syncIndicatorSettingsToServer();
        },
        onClearHistory: () async {
          // サーバー上のクロス履歴をクリア
          await _chartService.clearCrossHistoryOnServer(widget.symbol);
          // 再取得
          await _refreshCrossHistory();
        },
      ),
    );
  }

  // インジケーター設定を取得
  _IndicatorConfig _getIndicatorConfig(String key) {
    switch (key) {
      case 'bb':
        return _IndicatorConfig(
          key: 'bb',
          name: 'BB',
          fullName: 'ボリンジャーバンド',
          description: '±1σ, ±2σのバンドを表示',
          color: AppColors.bbMiddle,
          icon: Icons.stacked_line_chart,
        );
      case 'ema':
        return _IndicatorConfig(
          key: 'ema',
          name: 'EMA',
          fullName: '指数移動平均',
          description: 'EMA(10), EMA(25), EMA(50)',
          color: AppColors.emaMedium,
          icon: Icons.show_chart,
        );
      case 'rsi':
        return _IndicatorConfig(
          key: 'rsi',
          name: 'RSI',
          fullName: '相対力指数',
          description: '買われすぎ(70)/売られすぎ(30)',
          color: AppColors.rsiLine,
          icon: Icons.trending_up,
        );
      case 'macd':
        return _IndicatorConfig(
          key: 'macd',
          name: 'MACD',
          fullName: '移動平均収束拡散',
          description: 'シグナルラインとのクロス',
          color: AppColors.macdLine,
          icon: Icons.bar_chart,
        );
      case 'stochastic':
        return _IndicatorConfig(
          key: 'stochastic',
          name: 'Stoch',
          fullName: 'ストキャスティクス',
          description: '%K/%Dクロス、80/20レベル',
          color: AppColors.stochK,
          icon: Icons.ssid_chart,
        );
      case 'cci':
        return _IndicatorConfig(
          key: 'cci',
          name: 'CCI',
          fullName: '商品チャンネル指数',
          description: '±100レベルのクロス',
          color: AppColors.cciLine,
          icon: Icons.multiline_chart,
        );
      default:
        return _IndicatorConfig(
          key: key,
          name: key.toUpperCase(),
          fullName: key,
          description: '',
          color: AppColors.textSecondary,
          icon: Icons.analytics,
        );
    }
  }

  Widget _buildPriceHeader() {
    final latestCandle = _candles.last;
    final previousCandle = _candles.length > 1 ? _candles[_candles.length - 2] : _candles.last;
    final priceChange = latestCandle.close - previousCandle.close;
    final changePercent = (priceChange / previousCandle.close) * 100;
    final isPositive = priceChange >= 0;

    // 価格変動の表示文字列を生成
    String priceChangeStr;
    if (widget.category == MarketCategory.forex) {
      // 為替: 通貨変換なし、クォート通貨で表示
      final quoteCurrency = _getQuoteCurrencySymbol();
      priceChangeStr = '${isPositive ? '+' : ''}$quoteCurrency${_formatPrice(priceChange.abs())} (${changePercent.toStringAsFixed(2)}%)';
    } else if (widget.category == MarketCategory.stock && _isJapaneseStock()) {
      // 日本株: 通貨変換なし、円で表示
      priceChangeStr = '${isPositive ? '+' : ''}¥${_formatPrice(priceChange.abs())} (${changePercent.toStringAsFixed(2)}%)';
    } else {
      // 暗号通貨・米国株: 通貨変換あり
      priceChangeStr = '${isPositive ? '+' : ''}$_currencySymbol${_formatPrice(_convertPrice(priceChange.abs()))} (${changePercent.toStringAsFixed(2)}%)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatPriceWithCurrency(latestCandle.close),
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              isPositive ? Icons.arrow_upward : Icons.arrow_downward,
              color: isPositive ? Colors.red : Colors.lightBlue, // 上昇時は赤、下落時は水色
              size: 20,
            ),
            const SizedBox(width: 4),
            Text(
              priceChangeStr,
              style: TextStyle(
                fontSize: 16,
                color: isPositive ? Colors.red : Colors.lightBlue, // 上昇時は赤、下落時は水色
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChart() {
    if (_candles.length < 2) {
      return const SizedBox(
        height: 300,
        child: Center(child: Text('チャートデータが不足しています')),
      );
    }

    switch (_chartType) {
      case ChartType.line:
        return _buildLineChart(_candles);
      case ChartType.candlestick:
        return _buildCandlestickChart(_candles);
      case ChartType.heikinAshi:
        final haCandles = Candle.toHeikinAshi(_candles);
        return _buildCandlestickChart(haCandles);
    }
  }

  Widget _buildLineChart(List<Candle> candles) {
    // インジケーターの最大期間を計算
    int maxPeriod = 0;
    if (_showBB) {
      maxPeriod = max(maxPeriod, _bbPeriod);
    }
    if (_showEMA) {
      maxPeriod = max(maxPeriod, _emaPeriod1);
      maxPeriod = max(maxPeriod, _emaPeriod2);
      maxPeriod = max(maxPeriod, _emaPeriod3);
    }
    final int startOffset = (maxPeriod > 0) ? maxPeriod - 1 : 0;

    // 描画対象のローソク足リスト（ウォームアップ期間を削除）
    final displayCandles = (startOffset > 0 && candles.length > startOffset)
        ? candles.sublist(startOffset)
        : candles;

    if (displayCandles.isEmpty) {
      return const SizedBox(
        height: 300,
        child: Center(child: Text('インジケーター計算後のデータが不足しています')),
      );
    }

    // 描画対象のデータでスポットを生成
    final spots = displayCandles.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.close);
    }).toList();

    final minY = displayCandles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final maxY = displayCandles.map((c) => c.high).reduce((a, b) => a > b ? a : b);

    final isPositive = displayCandles.last.close >= displayCandles.first.close;
    final chartColor = isPositive ? Colors.red : Colors.lightBlue; // 上昇時は赤、下落時は水色に

    // メインの価格ライン
    final lineBars = <LineChartBarData>[
      LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.2,
        color: chartColor,
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: chartColor.withAlpha(30),
        ),
      ),
    ];
    
    // インジケーターは元の完全なリストから計算
    final fullClosePrices = candles.map((c) => c.close).toList();

    // ボリンジャーバンド
    if (_showBB) {
      final bb = TechnicalIndicators.calculateBollingerBands(
        fullClosePrices,
        period: _bbPeriod,
        stdDev1: _bbStdDev1,
        stdDev2: _bbStdDev2,
      );
      // BB: 内側から紫、ピンク、濃い目のピンク（透明度0.6、線幅変更）
      final bbMiddleColor = Colors.pink.shade700.withOpacity(0.6); // 濃い目のピンク
      final bb1SigmaColor = Colors.purple.withOpacity(0.6); // 紫
      final bb2SigmaColor = Colors.pink.withOpacity(0.6); // ピンク

      lineBars.add(_createIndicatorLine(bb.middle.sublist(startOffset), displayCandles.length, bbMiddleColor, 1.0)); // 線幅1.0
      lineBars.add(_createIndicatorLine(bb.upper1.sublist(startOffset), displayCandles.length, bb1SigmaColor, 0.75)); // 線幅0.75
      lineBars.add(_createIndicatorLine(bb.lower1.sublist(startOffset), displayCandles.length, bb1SigmaColor, 0.75)); // 線幅0.75
      lineBars.add(_createIndicatorLine(bb.upper2.sublist(startOffset), displayCandles.length, bb2SigmaColor, 0.75)); // 線幅0.75
      lineBars.add(_createIndicatorLine(bb.lower2.sublist(startOffset), displayCandles.length, bb2SigmaColor, 0.75)); // 線幅0.75
    }

    // EMA
    if (_showEMA) {
      // EMA: 短いものから青（深め）、水色（明るめ）、緑（透明度0.6、線幅1.0）
      final emaShortColor = Colors.blue.shade800.withOpacity(0.6); // 青を深めに
      final emaMediumColor = Colors.lightBlue.shade300.withOpacity(0.6); // 水色を明るめに
      final emaLongColor = Colors.green.withOpacity(0.6);
      
      final ema1 = TechnicalIndicators.calculateEMA(fullClosePrices, _emaPeriod1);
      lineBars.add(_createIndicatorLine(ema1.sublist(startOffset), displayCandles.length, emaShortColor, 1.0)); // 線幅1.0

      final ema2 = TechnicalIndicators.calculateEMA(fullClosePrices, _emaPeriod2);
      lineBars.add(_createIndicatorLine(ema2.sublist(startOffset), displayCandles.length, emaMediumColor, 1.0)); // 線幅1.0

      final ema3 = TechnicalIndicators.calculateEMA(fullClosePrices, _emaPeriod3);
      lineBars.add(_createIndicatorLine(ema3.sublist(startOffset), displayCandles.length, emaLongColor, 1.0)); // 線幅1.0
    }

    // ズーム・パンは描画対象のリスト基準で計算
    final totalDataPoints = displayCandles.length.toDouble();
    // 基準表示数（ズーム1.0で表示する量）を使用し、全データ数を超えないようにする
    final baseVisible = _getBaseVisibleDataPoints().toDouble();
    final visibleDataPoints = (baseVisible / _chartZoom).clamp(1.0, totalDataPoints);
    final maxPanOffset = (totalDataPoints - visibleDataPoints).clamp(0.0, totalDataPoints);
    final panOffset = (_chartPanOffsetX * maxPanOffset).clamp(0.0, maxPanOffset);
    final visibleMinX = panOffset;
    final visibleMaxX = (panOffset + visibleDataPoints - 1).clamp(0.0, totalDataPoints - 1);

    // 表示範囲内のデータでY軸の範囲を再計算
    final visibleStartIdx = visibleMinX.floor().clamp(0, displayCandles.length - 1);
    final visibleEndIdx = visibleMaxX.ceil().clamp(visibleStartIdx, displayCandles.length - 1);
    final visibleCandles = displayCandles.sublist(visibleStartIdx, visibleEndIdx + 1);

    double visibleMinY = minY;
    double visibleMaxY = maxY;
    if (visibleCandles.isNotEmpty) {
      visibleMinY = visibleCandles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
      visibleMaxY = visibleCandles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    }
    final visiblePadding = (visibleMaxY - visibleMinY) * 0.1;

    // 縦パンオフセットを適用
    final yRange = visibleMaxY - visibleMinY + visiblePadding * 2;
    final yPanAmount = yRange * _chartPanOffsetY * 0.5;
    final adjustedMinY = visibleMinY - visiblePadding + yPanAmount;
    final adjustedMaxY = visibleMaxY + visiblePadding + yPanAmount;

    // X軸ラベル間隔を計算（重複防止）
    final xLabelInterval = _calculateXLabelInterval(visibleCandles.length);

    // オシレーター用の元リストのインデックス（範囲外アクセス防止）
    final originalListVisibleStartIdx = (visibleStartIdx + startOffset).clamp(0, candles.length);
    final originalListVisibleEndIdx = (visibleEndIdx + 1 + startOffset).clamp(originalListVisibleStartIdx, candles.length);

    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          // ズームコントロール（コンパクト）
          _buildCompactZoomControls(),
          // チャート本体（軸ラベル付き）
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Y軸ラベル（左側）
              SizedBox(
                width: 55,
                height: 300,
                child: _buildYAxisLabels(adjustedMinY, adjustedMaxY),
              ),
              // メインチャート
              Expanded(
                child: Column(
                  children: [
                    _buildInteractiveChartWrapper(
                      chartHeight: 300,
                      visibleCandles: visibleCandles,
                      visibleStartIdx: visibleStartIdx,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            children: [
                              // グリッド・枠線（背景）
                              CustomPaint(
                                size: Size(constraints.maxWidth, 300),
                                painter: ChartGridPainter(
                                  dataLength: visibleCandles.length,
                                  xLabelInterval: xLabelInterval,
                                ),
                              ),
                              // 折れ線チャート（グリッド・枠線なし）
                              LineChart(
                                LineChartData(
                                  gridData: const FlGridData(show: false),
                                  titlesData: const FlTitlesData(show: false),
                                  borderData: FlBorderData(show: false),
                                  minX: visibleMinX,
                                  maxX: visibleMaxX,
                                  minY: adjustedMinY,
                                  maxY: adjustedMaxY,
                                  lineBarsData: lineBars,
                                  clipData: const FlClipData.all(),
                                  lineTouchData: LineTouchData(
                                    touchTooltipData: LineTouchTooltipData(
                                      getTooltipItems: (touchedSpots) {
                                        return touchedSpots.map((spot) {
                                          final index = spot.x.toInt();
                                          if (index < 0 || index >= displayCandles.length) return null;
                                          if (spot.barIndex != 0) return null;
                                          final candle = displayCandles[index];
                                          return LineTooltipItem(
                                            '${DateFormat('yyyy/MM/dd').format(candle.date)}\n${_formatPriceWithCurrency(candle.close)}',
                                            const TextStyle(color: Colors.white),
                                          );
                                        }).toList();
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    // X軸ラベル（下側）
                    SizedBox(
                      height: 30,
                      child: _buildXAxisLabels(visibleCandles, xLabelInterval),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // オシレーターパネル
          if (_hasActiveOscillator)
            _buildOscillatorPanels(candles, originalListVisibleStartIdx, originalListVisibleEndIdx),
          // クロスヘア情報表示
          if (_showCrosshair && _crosshairIndex != null && _crosshairIndex! < visibleCandles.length)
            _buildCrosshairInfo(visibleCandles[_crosshairIndex!]),
        ],
      ),
    );
  }

  // インタラクティブチャートラッパー
  Widget _buildInteractiveChartWrapper({
    required double chartHeight,
    required List<Candle> visibleCandles,
    required int visibleStartIdx,
    required Widget child,
  }) {
    return GestureDetector(
      onVerticalDragStart: (details) {}, // これを追加してジェスチャーの競合を解決
      onScaleStart: (details) {
        _lastScaleStart = _chartZoom;
        _lastFocalPoint = details.focalPoint;
      },
      onScaleUpdate: (details) {
        setState(() {
          // ピンチズーム
          if (_lastScaleStart != null && details.scale != 1.0) {
            final newZoom = (_lastScaleStart! * details.scale).clamp(_minZoom, _maxZoom);
            _chartZoom = newZoom;
          }
          // パン（スムーズ）
          if (details.scale == 1.0) {
            final sensitivity = 1.5 / _chartZoom; // ズーム時は感度を上げる
            final deltaX = details.focalPointDelta.dx / 150 * sensitivity;
            final deltaY = details.focalPointDelta.dy / 120 * sensitivity;

            // スクロール位置を更新（0.0=左端、1.0=右端）
            _chartPanOffsetX = (_chartPanOffsetX - deltaX).clamp(0.0, 1.0);

            _chartPanOffsetY = (_chartPanOffsetY + deltaY).clamp(-1.5, 1.5);
          }
          _lastFocalPoint = details.focalPoint;
        });
      },
      onScaleEnd: (details) {
        _lastScaleStart = null;
        _lastFocalPoint = null;
      },
      // ダブルタップでズーム
      onDoubleTapDown: (details) {
        _lastTapPosition = details.localPosition;
      },
      onDoubleTap: () {
        setState(() {
          if (_chartZoom < 2.0) {
            _chartZoom = 3.0;
          } else {
            _chartZoom = 1.0;
            _chartPanOffsetX = 0.0;
            _chartPanOffsetY = 0.0;
          }
        });
      },
      // ロングプレスでクロスヘア表示
      onLongPressStart: (details) {
        _updateCrosshair(details.localPosition, visibleCandles, chartHeight);
      },
      onLongPressMoveUpdate: (details) {
        _updateCrosshair(details.localPosition, visibleCandles, chartHeight);
      },
      onLongPressEnd: (details) {
        setState(() {
          _showCrosshair = false;
          _crosshairPosition = null;
          _crosshairIndex = null;
        });
      },
      child: SizedBox(
        height: chartHeight,
        child: ClipRect(
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.chartBackground,
            ),
            child: Stack(
              children: [
                child,
                // クロスヘアオーバーレイ
                if (_showCrosshair && _crosshairPosition != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: CrosshairPainter(
                        position: _crosshairPosition!,
                        color: AppColors.axisLabel.withOpacity(0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _updateCrosshair(Offset position, List<Candle> candles, double chartHeight) {
    if (candles.isEmpty) return;
    // 簡易的なインデックス計算（チャート幅に基づく）
    final chartWidth = MediaQuery.of(context).size.width - 32; // padding分を引く
    final index = ((position.dx / chartWidth) * candles.length).floor().clamp(0, candles.length - 1);

    setState(() {
      _showCrosshair = true;
      _crosshairPosition = position;
      _crosshairIndex = index;
    });
  }

  // クロスヘア情報表示
  Widget _buildCrosshairInfo(Candle candle) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildInfoItem('日付', DateFormat('MM/dd').format(candle.date)),
          _buildInfoItem('始値', _formatPriceWithCurrency(candle.open)),
          _buildInfoItem('高値', _formatPriceWithCurrency(candle.high)),
          _buildInfoItem('安値', _formatPriceWithCurrency(candle.low)),
          _buildInfoItem('終値', _formatPriceWithCurrency(candle.close)),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // コンパクトなズームコントロール
  Widget _buildCompactZoomControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // ズームレベル表示
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${(_chartZoom * 100).toInt()}%',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          // ズームスライダー
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Theme.of(context).primaryColor,
                inactiveTrackColor: Colors.grey.shade300,
              ),
              child: Slider(
                value: _chartZoom,
                min: _minZoom,
                max: _maxZoom,
                onChanged: (value) => setState(() {
                  _chartZoom = value;
                }),
              ),
            ),
          ),
          // リセットボタン
          IconButton(
            icon: Icon(Icons.refresh, size: 20, color: Colors.grey.shade600),
            onPressed: () => setState(() {
              _chartZoom = 1.0;
              _chartPanOffsetX = 1.0; // 右端（最新データ）にリセット
              _chartPanOffsetY = 0.0;
            }),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'リセット',
          ),
          const SizedBox(width: 8),
          // 操作ヒント
          Tooltip(
            message: 'ピンチ: ズーム\nドラッグ: スクロール\nダブルタップ: ズーム切替\n長押し: 詳細表示',
            child: Icon(Icons.help_outline, size: 18, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  List<LineChartBarData> _createBBLines(BollingerBandsResult bb, int length) {
    final lines = <LineChartBarData>[];

    // BB: 内側から紫、ピンク、濃い目のピンク
    final bbMiddleColor = Colors.pink.shade700.withOpacity(0.6); // 濃い目のピンク
    final bb1SigmaColor = Colors.purple.withOpacity(0.6); // 紫
    final bb2SigmaColor = Colors.pink.withOpacity(0.6); // ピンク

    lines.add(_createIndicatorLine(bb.middle, length, bbMiddleColor, 1.0));
    lines.add(_createIndicatorLine(bb.upper1, length, bb1SigmaColor, 0.75));
    lines.add(_createIndicatorLine(bb.lower1, length, bb1SigmaColor, 0.75));
    lines.add(_createIndicatorLine(bb.upper2, length, bb2SigmaColor, 0.75));
    lines.add(_createIndicatorLine(bb.lower2, length, bb2SigmaColor, 0.75));

    return lines;
  }

  List<LineChartBarData> _createEMALines(List<double> prices, int length) {
    final lines = <LineChartBarData>[];

    // EMA: 短いものから青（深め）、水色（明るめ）、緑
    final emaShortColor = Colors.blue.shade800.withOpacity(0.6); // 青を深めに
    final emaMediumColor = Colors.lightBlue.shade300.withOpacity(0.6); // 水色を明るめに
    final emaLongColor = Colors.green.withOpacity(0.6);
    
    final ema1 = TechnicalIndicators.calculateEMA(prices, _emaPeriod1);
    lines.add(_createIndicatorLine(ema1, length, emaShortColor, 1.0));

    final ema2 = TechnicalIndicators.calculateEMA(prices, _emaPeriod2);
    lines.add(_createIndicatorLine(ema2, length, emaMediumColor, 1.0));

    final ema3 = TechnicalIndicators.calculateEMA(prices, _emaPeriod3);
    lines.add(_createIndicatorLine(ema3, length, emaLongColor, 1.0));

    return lines;
  }

  LineChartBarData _createIndicatorLine(List<double?> data, int length, Color color, double width) {
    final spots = <FlSpot>[];
    for (int i = 0; i < length; i++) {
      if (data[i] != null) {
        spots.add(FlSpot(i.toDouble(), data[i]!));
      }
    }

    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.2,
      color: color,
      barWidth: width,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }

  Widget _buildCandlestickChart(List<Candle> candles) {
    // 指標の最大期間を計算
    int maxPeriod = 0;
    if (_showBB) {
      maxPeriod = max(maxPeriod, _bbPeriod);
    }
    if (_showEMA) {
      maxPeriod = max(maxPeriod, _emaPeriod1);
      maxPeriod = max(maxPeriod, _emaPeriod2);
      maxPeriod = max(maxPeriod, _emaPeriod3);
    }
    final int startOffset = (maxPeriod > 0) ? maxPeriod - 1 : 0;

    // 描画対象のローソク足リスト（インジケーターのウォームアップ期間を削除）
    final displayCandles = (startOffset > 0 && candles.length > startOffset)
        ? candles.sublist(startOffset)
        : candles;

    if (displayCandles.isEmpty) {
      return const SizedBox(
        height: 300,
        child: Center(child: Text('インジケーター計算後のデータが不足しています')),
      );
    }

    // Y軸の範囲は表示対象のキャンドルから計算
    final minY = displayCandles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final maxY = displayCandles.map((c) => c.high).reduce((a, b) => a > b ? a : b);

    // ズーム・パンは表示対象のキャンドルリストに対して行う
    final totalDataPoints = displayCandles.length.toDouble();
    // 基準表示数（ズーム1.0で表示する量）を使用し、全データ数を超えないようにする
    final baseVisible = _getBaseVisibleDataPoints().toDouble();
    final visibleDataPoints = (baseVisible / _chartZoom).clamp(1.0, totalDataPoints).round();
    final maxPanOffset = (displayCandles.length - visibleDataPoints).clamp(0, displayCandles.length);
    final panOffset = (_chartPanOffsetX * maxPanOffset).round().clamp(0, maxPanOffset);
    final visibleStartIdx = panOffset.clamp(0, displayCandles.length - 1);
    final visibleEndIdx = (panOffset + visibleDataPoints).clamp(visibleStartIdx + 1, displayCandles.length);
    final visibleCandles = displayCandles.sublist(visibleStartIdx, visibleEndIdx);

    // 表示範囲内のY軸範囲を再計算
    double visibleMinY = minY;
    double visibleMaxY = maxY;
    if (visibleCandles.isNotEmpty) {
      visibleMinY = visibleCandles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
      visibleMaxY = visibleCandles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    }
    final visiblePadding = (visibleMaxY - visibleMinY) * 0.1;

    // 縦パンオフセットを適用
    final yRange = visibleMaxY - visibleMinY + visiblePadding * 2;
    final yPanAmount = yRange * _chartPanOffsetY * 0.5;
    final adjustedMinY = visibleMinY - visiblePadding + yPanAmount;
    final adjustedMaxY = visibleMaxY + visiblePadding + yPanAmount;
    
    // インジケーターは元の完全なリストから計算
    final fullClosePrices = candles.map((c) => c.close).toList();
    BollingerBandsResult? visibleBB;
    List<List<double?>>? visibleEmaLines;
    
    // 表示範囲のインデックスを元のリストのインデックスに変換（範囲外アクセス防止）
    final originalListVisibleStartIdx = (visibleStartIdx + startOffset).clamp(0, candles.length);
    final originalListVisibleEndIdx = (visibleEndIdx + startOffset).clamp(originalListVisibleStartIdx, candles.length);

    if (_showBB && originalListVisibleStartIdx < originalListVisibleEndIdx) {
      final fullBB = TechnicalIndicators.calculateBollingerBands(
        fullClosePrices,
        period: _bbPeriod,
        stdDev1: _bbStdDev1,
        stdDev2: _bbStdDev2,
      );
      // 正しい範囲でスライス（範囲チェック付き）
      final bbEndIdx = originalListVisibleEndIdx.clamp(0, fullBB.middle.length);
      final bbStartIdx = originalListVisibleStartIdx.clamp(0, bbEndIdx);
      visibleBB = BollingerBandsResult(
        middle: fullBB.middle.sublist(bbStartIdx, bbEndIdx),
        upper1: fullBB.upper1.sublist(bbStartIdx, bbEndIdx),
        lower1: fullBB.lower1.sublist(bbStartIdx, bbEndIdx),
        upper2: fullBB.upper2.sublist(bbStartIdx, bbEndIdx),
        lower2: fullBB.lower2.sublist(bbStartIdx, bbEndIdx),
      );
    }
    if (_showEMA && originalListVisibleStartIdx < originalListVisibleEndIdx) {
      final fullEma1 = TechnicalIndicators.calculateEMA(fullClosePrices, _emaPeriod1);
      final fullEma2 = TechnicalIndicators.calculateEMA(fullClosePrices, _emaPeriod2);
      final fullEma3 = TechnicalIndicators.calculateEMA(fullClosePrices, _emaPeriod3);
      // 正しい範囲でスライス（範囲チェック付き）
      final ema1EndIdx = originalListVisibleEndIdx.clamp(0, fullEma1.length);
      final ema1StartIdx = originalListVisibleStartIdx.clamp(0, ema1EndIdx);
      final ema2EndIdx = originalListVisibleEndIdx.clamp(0, fullEma2.length);
      final ema2StartIdx = originalListVisibleStartIdx.clamp(0, ema2EndIdx);
      final ema3EndIdx = originalListVisibleEndIdx.clamp(0, fullEma3.length);
      final ema3StartIdx = originalListVisibleStartIdx.clamp(0, ema3EndIdx);
      visibleEmaLines = [
        fullEma1.sublist(ema1StartIdx, ema1EndIdx),
        fullEma2.sublist(ema2StartIdx, ema2EndIdx),
        fullEma3.sublist(ema3StartIdx, ema3EndIdx),
      ];
    }
    
    // X軸ラベル間隔を計算
    final xLabelInterval = _calculateXLabelInterval(visibleCandles.length);

    // CustomPainterに渡すデータは既にトリミングされているため、インジケーター開始インデックスは0
    const int indicatorStartIndex = 0;

    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          // ズームコントロール（コンパクト）
          _buildCompactZoomControls(),
          // チャート本体（軸ラベル付き）
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Y軸ラベル（左側）
              SizedBox(
                width: 55,
                height: 300,
                child: _buildYAxisLabels(adjustedMinY, adjustedMaxY),
              ),
              // メインチャート
              Expanded(
                child: Column(
                  children: [
                    _buildInteractiveChartWrapper(
                      chartHeight: 300,
                      visibleCandles: visibleCandles,
                      visibleStartIdx: visibleStartIdx,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return CustomPaint(
                            size: Size(constraints.maxWidth, 300),
                            painter: CandlestickPainter(
                              candles: visibleCandles,
                              minY: adjustedMinY,
                              maxY: adjustedMaxY,
                              bb: visibleBB,
                              emaLines: visibleEmaLines,
                              startIndex: visibleStartIdx,
                              totalLength: candles.length,
                              xLabelInterval: xLabelInterval,
                              interval: _interval,
                              indicatorStartIndex: indicatorStartIndex,
                            ),
                          );
                        },
                      ),
                    ),
                    // X軸ラベル（下側）
                    SizedBox(
                      height: 30,
                      child: _buildXAxisLabels(visibleCandles, xLabelInterval),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // オシレーターパネル
          if (_hasActiveOscillator)
            _buildOscillatorPanels(candles, originalListVisibleStartIdx, originalListVisibleEndIdx),
          // クロスヘア情報表示
          if (_showCrosshair && _crosshairIndex != null && _crosshairIndex! < visibleCandles.length)
            _buildCrosshairInfo(visibleCandles[_crosshairIndex!]),
        ],
      ),
    );
  }

  // オシレーターが有効かどうか
  bool get _hasActiveOscillator => _showRSI || _showMACD || _showStochastic || _showCCI;

  // 安全なsublist（範囲外アクセス防止）
  List<T> _safeSublist<T>(List<T> list, int start, int end) {
    final safeEnd = end.clamp(0, list.length);
    final safeStart = start.clamp(0, safeEnd);
    return list.sublist(safeStart, safeEnd);
  }

  // オシレーターパネルを構築
  Widget _buildOscillatorPanels(List<Candle> candles, int visibleStartIdx, int visibleEndIdx) {
    final closePrices = candles.map((c) => c.close).toList();
    final panels = <Widget>[];

    // RSIパネル
    if (_showRSI) {
      final rsi = OscillatorIndicators.calculateRSI(closePrices, period: _rsiPeriod);
      final visibleRSI = _safeSublist(rsi.values, visibleStartIdx, visibleEndIdx);
      if (visibleRSI.isNotEmpty) {
        panels.add(_buildSingleOscillatorPanel(
          title: 'RSI($_rsiPeriod)',
          values: visibleRSI,
          minY: 0,
          maxY: 100,
          lineColor: AppColors.rsiLine,
          oscillatorType: 'rsi',
        ));
      }
    }

    // MACDパネル
    if (_showMACD) {
      final macd = OscillatorIndicators.calculateMACD(
        closePrices,
        fastPeriod: _macdFast,
        slowPeriod: _macdSlow,
        signalPeriod: _macdSignal,
      );
      final visibleMACD = _safeSublist(macd.macdLine, visibleStartIdx, visibleEndIdx);
      final visibleSignal = _safeSublist(macd.signalLine, visibleStartIdx, visibleEndIdx);
      final visibleHistogram = _safeSublist(macd.histogram, visibleStartIdx, visibleEndIdx);

      if (visibleMACD.isNotEmpty) {
        // MACDの範囲を計算
        double macdMin = 0, macdMax = 0;
        for (final v in visibleMACD) {
          if (v != null) {
            macdMin = min(macdMin, v);
            macdMax = max(macdMax, v);
          }
        }
        for (final v in visibleSignal) {
          if (v != null) {
            macdMin = min(macdMin, v);
            macdMax = max(macdMax, v);
          }
        }
        final macdPadding = (macdMax - macdMin) * 0.1;

        panels.add(_buildSingleOscillatorPanel(
          title: 'MACD($_macdFast,$_macdSlow,$_macdSignal)',
          values: visibleMACD,
          minY: macdMin - macdPadding,
          maxY: macdMax + macdPadding,
          lineColor: AppColors.macdLine,
          oscillatorType: 'macd',
          signalLine: visibleSignal,
          histogram: visibleHistogram,
        ));
      }
    }

    // Stochasticパネル
    if (_showStochastic) {
      final stoch = OscillatorIndicators.calculateStochastic(
        candles,
        kPeriod: _stochKPeriod,
        dPeriod: _stochDPeriod,
        smooth: _stochSmooth,
      );
      final visibleK = _safeSublist(stoch.percentK, visibleStartIdx, visibleEndIdx);
      final visibleD = _safeSublist(stoch.percentD, visibleStartIdx, visibleEndIdx);

      if (visibleK.isNotEmpty) {
        panels.add(_buildSingleOscillatorPanel(
          title: 'Stoch($_stochKPeriod,$_stochDPeriod,$_stochSmooth)',
          values: visibleK,
          minY: 0,
          maxY: 100,
          lineColor: AppColors.stochK,
          oscillatorType: 'stochastic',
          signalLine: visibleD,
        ));
      }
    }

    // CCIパネル
    if (_showCCI) {
      final cci = OscillatorIndicators.calculateCCI(candles, period: _cciPeriod);
      final visibleCCI = _safeSublist(cci.values, visibleStartIdx, visibleEndIdx);

      if (visibleCCI.isNotEmpty) {
        // CCIの範囲を計算
        double cciMin = -100, cciMax = 100;
        for (final v in visibleCCI) {
          if (v != null) {
            cciMin = min(cciMin, v);
            cciMax = max(cciMax, v);
          }
        }
        final cciPadding = (cciMax - cciMin) * 0.1;

        panels.add(_buildSingleOscillatorPanel(
          title: 'CCI($_cciPeriod)',
          values: visibleCCI,
          minY: cciMin - cciPadding,
          maxY: cciMax + cciPadding,
          lineColor: AppColors.cciLine,
          oscillatorType: 'cci',
        ));
      }
    }

    return Column(children: panels);
  }

  // 単一オシレーターパネルを構築
  Widget _buildSingleOscillatorPanel({
    required String title,
    required List<double?> values,
    required double minY,
    required double maxY,
    required Color lineColor,
    required String oscillatorType,
    List<double?> signalLine = const [],
    List<double?> histogram = const [],
  }) {
    const panelHeight = 100.0;

    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Y軸ラベル（左側）
            SizedBox(
              width: 55,
              height: panelHeight,
              child: _buildOscillatorYAxisLabels(minY, maxY),
            ),
            // オシレーターチャート
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // タイトル
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: lineColor,
                      ),
                    ),
                  ),
                  // チャート
                  SizedBox(
                    height: panelHeight,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return CustomPaint(
                          size: Size(constraints.maxWidth, panelHeight),
                          painter: OscillatorPainter(
                            values: values,
                            minY: minY,
                            maxY: maxY,
                            lineColor: lineColor,
                            oscillatorType: oscillatorType,
                            signalLine: signalLine,
                            histogram: histogram,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // オシレーター用Y軸ラベル
  Widget _buildOscillatorYAxisLabels(double minY, double maxY) {
    final range = maxY - minY;
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          maxY.toStringAsFixed(0),
          style: const TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold),
        ),
        Text(
          ((maxY + minY) / 2).toStringAsFixed(0),
          style: const TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold),
        ),
        Text(
          minY.toStringAsFixed(0),
          style: const TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // X軸ラベル間隔を計算（重複防止）
  int _calculateXLabelInterval(int dataPoints) {
    if (dataPoints <= 10) return 1;
    if (dataPoints <= 30) return 3;
    if (dataPoints <= 60) return 5;
    if (dataPoints <= 120) return 10;
    if (dataPoints <= 240) return 20;
    return (dataPoints / 10).ceil();
  }

  // 基準表示データ数（ズーム1.0で表示する量）
  // 全時間軸で100本を表示、左右スクロールで残りを閲覧可能
  int _getBaseVisibleDataPoints() {
    return 100;
  }

  // Y軸ラベル
  Widget _buildYAxisLabels(double minY, double maxY) {
    final range = maxY - minY;
    final labels = <Widget>[];
    for (int i = 0; i <= 10; i++) {
      final value = maxY - (range * i / 10);
      labels.add(
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                _formatPrice(value),
                style: const TextStyle(
                  fontSize: 9,
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Column(children: labels);
  }

  // X軸ラベル
  Widget _buildXAxisLabels(List<Candle> candles, int interval) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final labels = <Widget>[];
        if (candles.isEmpty || constraints.maxWidth == 0) return Stack(children: labels);

        final candleWidth = constraints.maxWidth / candles.length;
        final format = ['5m', '15m', '30m', '1h', '4h'].contains(_interval)
            ? DateFormat('HH:mm')
            : DateFormat('MM/dd');

        double? lastLabelRightEdge; // 最後に描画したラベルの右端のX座標

        for (int i = 0; i < candles.length; i += interval) {
          if (i == 0) continue; // 一番左のラベルを描画しない

          const double labelWidth = 30; // ラベルの幅を小さく
          // ラベルの理想的な中央位置
          final double idealCenter = i * candleWidth + candleWidth / 2;
          // ラベルの左端の開始位置
          double leftPos = idealCenter - (labelWidth / 2);

          // 描画範囲内に収まるように位置を調整
          // if (leftPos < 0) { // 左端の固定を削除
          //   leftPos = 0;
          // }
          if (leftPos + labelWidth > constraints.maxWidth) {
            leftPos = constraints.maxWidth - labelWidth;
          }

          // 前のラベルと重なる場合は描画をスキップ
          if (lastLabelRightEdge != null && leftPos < lastLabelRightEdge) {
            continue;
          }

          labels.add(
            Positioned(
              left: leftPos,
              child: SizedBox(
                width: labelWidth,
                child: Text(
                  format.format(candles[i].date),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9, // フォントサイズを元に戻す
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );

          lastLabelRightEdge = leftPos + labelWidth; // 最後に描画したラベルの右端を更新
        }
        return Stack(children: labels);
      },
    );
  }

  Widget _buildStats() {
    final high = _candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final low = _candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final open = _candles.first.open;
    final close = _candles.last.close;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '統計情報',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildStatRow('始値', _formatPriceWithCurrency(open)),
            _buildStatRow('終値', _formatPriceWithCurrency(close)),
            _buildStatRow('高値', _formatPriceWithCurrency(high)),
            _buildStatRow('安値', _formatPriceWithCurrency(low)),
            _buildStatRow('期間', '${_candles.length}本'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // 通貨シンボルを取得
  String get _currencySymbol => _showJPY ? '¥' : '\$';

  // 価格を選択した通貨に変換
  double _convertPrice(double priceUSD) {
    return _showJPY ? priceUSD * _usdJpyRate : priceUSD;
  }

  // 通貨切替を表示するかどうか
  bool _shouldShowCurrencyToggle() {
    // 暗号通貨: 常に表示
    if (widget.category == MarketCategory.crypto) return true;
    // 為替: 表示しない
    if (widget.category == MarketCategory.forex) return false;
    // 株式: 日本株以外（米国株）は表示
    if (widget.category == MarketCategory.stock) {
      return !_isJapaneseStock();
    }
    return false;
  }

  // 日本株かどうか判定
  bool _isJapaneseStock() {
    return widget.symbol.endsWith('.T');
  }

  // 為替ペアまたは株式の通貨シンボルを取得
  String _getQuoteCurrencySymbol() {
    // 為替の場合
    if (widget.category == MarketCategory.forex) {
      final symbol = widget.symbol.replaceAll('=X', '');
      if (symbol.endsWith('JPY')) return '¥';
      if (symbol.endsWith('USD')) return '\$';
      if (symbol.endsWith('EUR')) return '€';
      if (symbol.endsWith('GBP')) return '£';
    }
    // 日本株の場合
    if (widget.category == MarketCategory.stock && _isJapaneseStock()) {
      return '¥';
    }
    // その他（米国株、暗号通貨）
    return '\$';
  }

  // 価格をフォーマット（通貨変換込み）
  String _formatPriceWithCurrency(double price) {
    // 為替の場合は通貨変換せず、クォート通貨で表示
    if (widget.category == MarketCategory.forex) {
      final quoteCurrency = _getQuoteCurrencySymbol();
      return '$quoteCurrency${_formatPrice(price)}';
    }
    // 日本株の場合は通貨変換せず、円で表示
    if (widget.category == MarketCategory.stock && _isJapaneseStock()) {
      return '¥${_formatPrice(price)}';
    }
    // 暗号通貨・米国株の場合は通貨変換
    final convertedPrice = _convertPrice(price);
    return '$_currencySymbol${_formatPrice(convertedPrice)}';
  }

  String _formatPrice(double price) {
    if (price >= 1000) {
      return NumberFormat('#,##0.00').format(price);
    } else if (price >= 1) {
      return price.toStringAsFixed(2);
    } else {
      return price.toStringAsFixed(6);
    }
  }
}

// グリッドと枠線を描画するCustomPainter（折れ線チャート用）
class ChartGridPainter extends CustomPainter {
  final int dataLength;
  final int xLabelInterval;

  ChartGridPainter({
    required this.dataLength,
    required this.xLabelInterval,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dataLength == 0) return;

    final dataWidth = size.width / dataLength;

    // グリッド線を描画
    final gridPaint = Paint()
      ..color = AppColors.textSecondary.withAlpha(200)
      ..strokeWidth = 0.5;

    // ダッシュパターン
    const dashLength = 3.0;
    const spaceLength = 3.0;

    // 横グリッド線（10分割）
    for (int i = 0; i <= 10; i++) {
      final y = size.height * i / 10;
      double currentX = 0;
      while (currentX < size.width) {
        canvas.drawLine(
          Offset(currentX, y),
          Offset(min(currentX + dashLength, size.width), y),
          gridPaint,
        );
        currentX += dashLength + spaceLength;
      }
    }

    // 縦グリッド線（X軸ラベル位置に合わせる）
    for (int i = 0; i < dataLength; i += xLabelInterval) {
      final x = i * dataWidth + dataWidth / 2;
      double currentY = 0;
      while (currentY < size.height) {
        canvas.drawLine(
          Offset(x, currentY),
          Offset(x, min(currentY + dashLength, size.height)),
          gridPaint,
        );
        currentY += dashLength + spaceLength;
      }
    }

    // チャート全体を囲む枠線を描画
    final borderPaint = Paint()
      ..color = AppColors.textSecondary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), borderPaint);
  }

  @override
  bool shouldRepaint(covariant ChartGridPainter oldDelegate) {
    return oldDelegate.dataLength != dataLength ||
        oldDelegate.xLabelInterval != xLabelInterval;
  }
}

// クロスヘアを描画するCustomPainter
class CrosshairPainter extends CustomPainter {
  final Offset position;
  final Color color;

  CrosshairPainter({required this.position, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final dashPaint = Paint()
      ..color = color.withAlpha(150)
      ..strokeWidth = 1;

    // 縦線（点線）
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(position.dx, y),
        Offset(position.dx, y + 4),
        dashPaint,
      );
      y += 8;
    }

    // 横線（点線）
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, position.dy),
        Offset(x + 4, position.dy),
        dashPaint,
      );
      x += 8;
    }

    // 交点の円
    canvas.drawCircle(position, 6, paint);
    canvas.drawCircle(
      position,
      3,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant CrosshairPainter oldDelegate) {
    return position != oldDelegate.position;
  }
}

// ローソク足チャートを描画するCustomPainter
class CandlestickPainter extends CustomPainter {
  final List<Candle> candles;
  final double minY;
  final double maxY;
  final BollingerBandsResult? bb;
  final List<List<double?>>? emaLines;
  final int startIndex;
  final int totalLength;
  final int xLabelInterval;
  final String interval;
  final int indicatorStartIndex; // インジケーターが有効になる開始インデックス

  CandlestickPainter({
    required this.candles,
    required this.minY,
    required this.maxY,
    this.bb,
    this.emaLines,
    this.startIndex = 0,
    int? totalLength,
    this.xLabelInterval = 5,
    this.interval = '1d',
    this.indicatorStartIndex = 0,
  }) : totalLength = totalLength ?? candles.length;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final candleWidth = size.width / candles.length;
    final priceRange = maxY - minY;

    // グリッド線を描画
    final gridPaint = Paint()
      ..color = AppColors.textSecondary.withOpacity(0.8)
      ..strokeWidth = 0.5;

    // 横グリッド線
    final dashLength = 3.0;
    final spaceLength = 3.0;
    for (int i = 0; i <= 10; i++) {
      final y = size.height * i / 10;
      double currentX = 0;
      while (currentX < size.width) {
        canvas.drawLine(Offset(currentX, y), Offset(min(currentX + dashLength, size.width), y), gridPaint);
        currentX += dashLength + spaceLength;
      }
    }

    // 縦グリッド線（X軸ラベル位置に合わせる）
    for (int i = 0; i < candles.length; i += xLabelInterval) {
      final x = i * candleWidth + candleWidth / 2;
      double currentY = 0;
      while (currentY < size.height) {
        canvas.drawLine(Offset(x, currentY), Offset(x, min(currentY + dashLength, size.height)), gridPaint);
        currentY += dashLength + spaceLength;
      }
    }

    // チャート全体を囲む枠線を描画
    final borderPaint = Paint()
      ..color = AppColors.textSecondary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), borderPaint);

    // 各ローソク足を描画（インジケーターの有効範囲のみ）
    for (int i = indicatorStartIndex; i < candles.length; i++) {
      final candle = candles[i];
      final x = i * candleWidth + candleWidth / 2;

      // Y座標を計算（上が高値、下が安値）
      final highY = size.height - ((candle.high - minY) / priceRange * size.height);
      final lowY = size.height - ((candle.low - minY) / priceRange * size.height);
      final openY = size.height - ((candle.open - minY) / priceRange * size.height);
      final closeY = size.height - ((candle.close - minY) / priceRange * size.height);

      final isPositive = candle.close >= candle.open;
      final color = isPositive ? Colors.red : Colors.lightBlue; // 陽線を赤、陰線を水色に

      // ヒゲ（高値-安値の線）
      final wickPaint = Paint()
        ..color = Colors.grey // ヒゲの色を灰色に
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, highY), Offset(x, lowY), wickPaint);

      // ローソク本体
      final bodyPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill // 陽線も常に塗りつぶすように変更
        ..strokeWidth = 1;

      final bodyTop = isPositive ? closeY : openY;
      final bodyBottom = isPositive ? openY : closeY;
      final bodyHeight = (bodyBottom - bodyTop).abs();

      // 本体の幅（データ量に応じて調整）
      final bodyWidth = (candleWidth * 0.7).clamp(2.0, 12.0);

      // 実体の最小高さを確保（為替など変動が小さい場合でも見えるように）
      final minBodyHeight = 4.0;
      final actualBodyHeight = bodyHeight < minBodyHeight ? minBodyHeight : bodyHeight;

      final rect = Rect.fromCenter(
        center: Offset(x, (bodyTop + bodyBottom) / 2),
        width: bodyWidth,
        height: actualBodyHeight,
      );
      canvas.drawRect(rect, bodyPaint);
    }

    // ボリンジャーバンドを描画（内側から紫、ピンク、濃い目のピンク）
    if (bb != null) {
      final bbMiddleColor = Colors.pink.shade700.withOpacity(0.6); // 濃い目のピンク
      final bb1SigmaColor = Colors.purple.withOpacity(0.6); // 紫
      final bb2SigmaColor = Colors.pink.withOpacity(0.6); // ピンク

      _drawIndicatorLine(canvas, size, bb!.middle, bbMiddleColor, 1.0, priceRange);
      _drawIndicatorLine(canvas, size, bb!.upper1, bb1SigmaColor, 0.75, priceRange);
      _drawIndicatorLine(canvas, size, bb!.lower1, bb1SigmaColor, 0.75, priceRange);
      _drawIndicatorLine(canvas, size, bb!.upper2, bb2SigmaColor, 0.75, priceRange);
      _drawIndicatorLine(canvas, size, bb!.lower2, bb2SigmaColor, 0.75, priceRange);
    }

    // EMAを描画（短いものから青、水色、緑）
    if (emaLines != null && emaLines!.isNotEmpty) {
      final emaColors = [
        Colors.blue.shade800.withOpacity(0.6), // 青を深めに
        Colors.lightBlue.shade300.withOpacity(0.6), // 水色を明るめに
        Colors.green.withOpacity(0.6)
      ]; // 短いものから青（深め）、水色（明るめ）、緑
      for (int i = 0; i < emaLines!.length && i < emaColors.length; i++) {
        _drawIndicatorLine(canvas, size, emaLines![i], emaColors[i], 1.0, priceRange);
      }
    }
  }

  void _drawIndicatorLine(Canvas canvas, Size size, List<double?> data, Color color, double width, double priceRange) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool started = false;
    final candleWidth = size.width / candles.length;

    for (int i = 0; i < data.length; i++) {
      if (data[i] != null) {
        final x = i * candleWidth + candleWidth / 2;
        final y = size.height - ((data[i]! - minY) / priceRange * size.height);

        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CandlestickPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.minY != minY ||
        oldDelegate.maxY != maxY ||
        oldDelegate.bb != bb ||
        oldDelegate.emaLines != emaLines ||
        oldDelegate.indicatorStartIndex != indicatorStartIndex;
  }
}

// オシレーターを描画するCustomPainter
class OscillatorPainter extends CustomPainter {
  final List<double?> values;
  final double minY;
  final double maxY;
  final Color lineColor;
  final String oscillatorType; // 'rsi', 'macd', 'stochastic', 'cci'
  final List<double?> signalLine; // MACD用シグナルライン、Stochastic用%D
  final List<double?> histogram; // MACD用ヒストグラム
  final int xLabelInterval;

  OscillatorPainter({
    required this.values,
    required this.minY,
    required this.maxY,
    required this.lineColor,
    required this.oscillatorType,
    this.signalLine = const [],
    this.histogram = const [],
    this.xLabelInterval = 5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final dataWidth = size.width / values.length;
    final valueRange = maxY - minY;

    // グリッド線を描画
    final gridPaint = Paint()
      ..color = AppColors.textSecondary.withAlpha(150)
      ..strokeWidth = 0.5;

    // 横グリッド線（ダッシュ線）
    const dashLength = 3.0;
    const spaceLength = 3.0;

    // レベルラインを描画
    _drawLevelLines(canvas, size, valueRange, gridPaint);

    // 枠線を描画
    final borderPaint = Paint()
      ..color = AppColors.textSecondary
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), borderPaint);

    // MACDヒストグラムを描画
    if (oscillatorType == 'macd' && histogram.isNotEmpty) {
      _drawHistogram(canvas, size, valueRange, dataWidth);
    }

    // メインラインを描画
    _drawLine(canvas, size, values, lineColor, valueRange, dataWidth, 1.5);

    // シグナルラインを描画（MACD、Stochastic用）
    if (signalLine.isNotEmpty) {
      final signalColor = oscillatorType == 'macd'
          ? AppColors.macdSignal
          : AppColors.stochD;
      _drawLine(canvas, size, signalLine, signalColor, valueRange, dataWidth, 1.0);
    }
  }

  void _drawLevelLines(Canvas canvas, Size size, double valueRange, Paint gridPaint) {
    final levels = <double>[];

    switch (oscillatorType) {
      case 'rsi':
        levels.addAll([70, 50, 30]); // 買われすぎ、中央、売られすぎ
        break;
      case 'macd':
        levels.add(0); // ゼロライン
        break;
      case 'stochastic':
        levels.addAll([80, 50, 20]); // 買われすぎ、中央、売られすぎ
        break;
      case 'cci':
        levels.addAll([100, 0, -100]); // +100、ゼロ、-100
        break;
    }

    for (final level in levels) {
      final y = size.height - ((level - minY) / valueRange * size.height);
      if (y >= 0 && y <= size.height) {
        // ダッシュ線
        double currentX = 0;
        while (currentX < size.width) {
          canvas.drawLine(
            Offset(currentX, y),
            Offset(min(currentX + 3.0, size.width), y),
            gridPaint,
          );
          currentX += 6.0;
        }
      }
    }
  }

  void _drawHistogram(Canvas canvas, Size size, double valueRange, double dataWidth) {
    for (int i = 0; i < histogram.length; i++) {
      if (histogram[i] == null) continue;

      final x = i * dataWidth + dataWidth / 2;
      final zeroY = size.height - ((0 - minY) / valueRange * size.height);
      final valueY = size.height - ((histogram[i]! - minY) / valueRange * size.height);

      final isPositive = histogram[i]! >= 0;
      final color = isPositive ? AppColors.macdHistogramPositive : AppColors.macdHistogramNegative;

      final paint = Paint()
        ..color = color.withAlpha(150)
        ..style = PaintingStyle.fill;

      final barWidth = (dataWidth * 0.6).clamp(1.0, 8.0);
      canvas.drawRect(
        Rect.fromLTRB(
          x - barWidth / 2,
          isPositive ? valueY : zeroY,
          x + barWidth / 2,
          isPositive ? zeroY : valueY,
        ),
        paint,
      );
    }
  }

  void _drawLine(Canvas canvas, Size size, List<double?> data, Color color, double valueRange, double dataWidth, double strokeWidth) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    bool started = false;

    for (int i = 0; i < data.length; i++) {
      if (data[i] != null) {
        final x = i * dataWidth + dataWidth / 2;
        final y = size.height - ((data[i]! - minY) / valueRange * size.height);

        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant OscillatorPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.minY != minY ||
        oldDelegate.maxY != maxY ||
        oldDelegate.signalLine != signalLine ||
        oldDelegate.histogram != histogram;
  }
}

// インジケーター設定情報クラス
class _IndicatorConfig {
  final String key;
  final String name;
  final String fullName;
  final String description;
  final Color color;
  final IconData icon;
  final List<_ParamConfig> params;

  _IndicatorConfig({
    required this.key,
    required this.name,
    required this.fullName,
    required this.description,
    required this.color,
    required this.icon,
    this.params = const [],
  });
}

// パラメータ設定情報クラス
class _ParamConfig {
  final String key;
  final String label;
  final int min;
  final int max;
  final bool isDouble;

  _ParamConfig({
    required this.key,
    required this.label,
    this.min = 1,
    this.max = 200,
    this.isDouble = false,
  });
}

// インジケーター設定ボトムシート
class _IndicatorSettingsSheet extends StatefulWidget {
  final Map<String, IndicatorSettings> indicators;
  final Function(String key, IndicatorSettings settings) onChanged;
  final Function(String key, bool enabled) onToggle;

  const _IndicatorSettingsSheet({
    required this.indicators,
    required this.onChanged,
    required this.onToggle,
  });

  @override
  State<_IndicatorSettingsSheet> createState() => _IndicatorSettingsSheetState();
}

class _IndicatorSettingsSheetState extends State<_IndicatorSettingsSheet> {
  String? _expandedKey;
  late Map<String, IndicatorSettings> _localIndicators;

  @override
  void initState() {
    super.initState();
    // 親の状態をコピーしてローカルで管理
    _localIndicators = {};
    widget.indicators.forEach((key, value) {
      _localIndicators[key] = value.copyWith();
    });
  }

  // トレンド系インジケーター（価格チャート上に表示）
  static final List<_IndicatorConfig> _trendIndicators = [
    _IndicatorConfig(
      key: 'bb',
      name: 'BB',
      fullName: 'ボリンジャーバンド',
      description: '価格の変動範囲を示す',
      color: Colors.blue,
      icon: Icons.stacked_line_chart,
      params: [
        _ParamConfig(key: 'period', label: '期間', min: 5, max: 100),
        _ParamConfig(key: 'stdDev1', label: '内側σ', min: 1, max: 3, isDouble: true),
        _ParamConfig(key: 'stdDev2', label: '外側σ', min: 1, max: 4, isDouble: true),
      ],
    ),
    _IndicatorConfig(
      key: 'ema',
      name: 'EMA',
      fullName: '指数移動平均線',
      description: '3本のEMAを表示',
      color: Colors.orange,
      icon: Icons.show_chart,
      params: [
        _ParamConfig(key: 'period1', label: '短期', min: 1, max: 100),
        _ParamConfig(key: 'period2', label: '中期', min: 1, max: 200),
        _ParamConfig(key: 'period3', label: '長期', min: 1, max: 500),
      ],
    ),
  ];

  // オシレーター系インジケーター（サブチャートに表示）
  static final List<_IndicatorConfig> _oscillatorIndicators = [
    _IndicatorConfig(
      key: 'rsi',
      name: 'RSI',
      fullName: '相対力指数',
      description: '買われすぎ(70)/売られすぎ(30)',
      color: AppColors.rsiLine,
      icon: Icons.trending_up,
      params: [
        _ParamConfig(key: 'period', label: '期間', min: 2, max: 50),
      ],
    ),
    _IndicatorConfig(
      key: 'macd',
      name: 'MACD',
      fullName: '移動平均収束拡散',
      description: 'シグナルラインとのクロス',
      color: AppColors.macdLine,
      icon: Icons.bar_chart,
      params: [
        _ParamConfig(key: 'fast', label: '短期EMA', min: 2, max: 50),
        _ParamConfig(key: 'slow', label: '長期EMA', min: 10, max: 100),
        _ParamConfig(key: 'signal', label: 'シグナル', min: 2, max: 50),
      ],
    ),
    _IndicatorConfig(
      key: 'stochastic',
      name: 'Stoch',
      fullName: 'ストキャスティクス',
      description: '%K/%Dクロス、80/20レベル',
      color: AppColors.stochK,
      icon: Icons.ssid_chart,
      params: [
        _ParamConfig(key: 'kPeriod', label: '%K期間', min: 5, max: 50),
        _ParamConfig(key: 'dPeriod', label: '%D期間', min: 1, max: 10),
        _ParamConfig(key: 'smooth', label: 'スムース', min: 1, max: 10),
      ],
    ),
    _IndicatorConfig(
      key: 'cci',
      name: 'CCI',
      fullName: '商品チャンネル指数',
      description: '±100レベルのクロス',
      color: AppColors.cciLine,
      icon: Icons.multiline_chart,
      params: [
        _ParamConfig(key: 'period', label: '期間', min: 5, max: 50),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // ハンドル
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // ヘッダー
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'インジケーター設定',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        for (final key in _localIndicators.keys) {
                          _localIndicators[key]!.enabled = false;
                          widget.onToggle(key, false);
                        }
                      });
                    },
                    child: const Text('すべてオフ'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // インジケーターリスト（セクション分け）
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  // トレンド系セクション
                  _buildSectionHeader(
                    title: 'トレンド系',
                    subtitle: '価格チャート上に表示',
                    icon: Icons.show_chart,
                    color: AppColors.primary,
                  ),
                  ..._trendIndicators.map((config) => _buildIndicatorTile(config)),

                  const SizedBox(height: 8),

                  // オシレーター系セクション
                  _buildSectionHeader(
                    title: 'オシレーター系',
                    subtitle: 'サブチャートに表示',
                    icon: Icons.ssid_chart,
                    color: AppColors.rsiLine,
                  ),
                  ..._oscillatorIndicators.map((config) => _buildIndicatorTile(config)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // セクションヘッダーを構築
  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        border: Border(
          bottom: BorderSide(color: color.withAlpha(50), width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: color.withAlpha(180),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // インジケータータイルを構築
  Widget _buildIndicatorTile(_IndicatorConfig config) {
    final settings = _localIndicators[config.key];
    final isEnabled = settings?.enabled ?? false;
    final isExpanded = _expandedKey == config.key;

    return Column(
      children: [
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: config.color.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(config.icon, color: config.color),
          ),
          title: Row(
            children: [
              Text(
                config.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                config.fullName,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          subtitle: Text(
            _getParamSummary(config, settings),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 設定ボタン
              if (config.params.isNotEmpty)
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.settings,
                    color: Colors.grey,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _expandedKey = isExpanded ? null : config.key;
                    });
                  },
                ),
              // スイッチ
              Switch(
                value: isEnabled,
                activeTrackColor: config.color.withAlpha(100),
                activeThumbColor: config.color,
                onChanged: (value) {
                  setState(() {
                    _localIndicators[config.key]!.enabled = value;
                  });
                  widget.onToggle(config.key, value);
                },
              ),
            ],
          ),
          onTap: () {
            final newValue = !isEnabled;
            setState(() {
              _localIndicators[config.key]!.enabled = newValue;
            });
            widget.onToggle(config.key, newValue);
          },
        ),
        // パラメータ設定エリア
        if (isExpanded && config.params.isNotEmpty)
          _buildParamEditor(config, settings),
      ],
    );
  }

  String _getParamSummary(_IndicatorConfig config, IndicatorSettings? settings) {
    if (settings == null) return config.description;

    switch (config.key) {
      case 'bb':
        final period = settings.params['period'] ?? 20;
        final std1 = settings.params['stdDev1'] ?? 1.0;
        final std2 = settings.params['stdDev2'] ?? 2.0;
        return '期間: $period, σ: ±$std1/±$std2';
      case 'ema':
        final p1 = settings.params['period1'] ?? 10;
        final p2 = settings.params['period2'] ?? 25;
        final p3 = settings.params['period3'] ?? 50;
        return 'EMA($p1), EMA($p2), EMA($p3)';
      case 'rsi':
        final period = settings.params['period'] ?? 14;
        return '期間: $period, レベル: 70/30';
      case 'macd':
        final fast = settings.params['fast'] ?? 12;
        final slow = settings.params['slow'] ?? 26;
        final signal = settings.params['signal'] ?? 9;
        return 'MACD($fast, $slow, $signal)';
      case 'stochastic':
        final k = settings.params['kPeriod'] ?? 14;
        final d = settings.params['dPeriod'] ?? 3;
        final smooth = settings.params['smooth'] ?? 3;
        return '%K($k), %D($d), Smooth($smooth)';
      case 'cci':
        final period = settings.params['period'] ?? 20;
        return '期間: $period, レベル: ±100';
      default:
        return config.description;
    }
  }

  Widget _buildParamEditor(_IndicatorConfig config, IndicatorSettings? settings) {
    if (settings == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: config.color.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: config.color.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${config.name} パラメータ設定',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: config.color,
            ),
          ),
          const SizedBox(height: 12),
          ...config.params.map((param) {
            final value = settings.params[param.key];
            return _buildParamSlider(config, param, value, settings);
          }),
        ],
      ),
    );
  }

  Widget _buildParamSlider(
    _IndicatorConfig config,
    _ParamConfig param,
    dynamic value,
    IndicatorSettings settings,
  ) {
    final doubleValue = (value is int ? value.toDouble() : (value ?? param.min).toDouble());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(param.label),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: config.color.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  param.isDouble ? doubleValue.toStringAsFixed(1) : doubleValue.toInt().toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: config.color,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: config.color,
              inactiveTrackColor: config.color.withAlpha(30),
              thumbColor: config.color,
              overlayColor: config.color.withAlpha(30),
            ),
            child: Slider(
              value: doubleValue,
              min: param.min.toDouble(),
              max: param.max.toDouble(),
              divisions: param.isDouble ? (param.max - param.min) * 10 : (param.max - param.min),
              onChanged: (newValue) {
                final newParams = Map<String, dynamic>.from(settings.params);
                newParams[param.key] = param.isDouble ? newValue : newValue.toInt();
                final newSettings = settings.copyWith(params: newParams);
                setState(() {
                  _localIndicators[config.key] = newSettings;
                });
                widget.onChanged(config.key, newSettings);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// クロス履歴・通知設定ボトムシート
class _CrossSettingsSheet extends StatefulWidget {
  final String symbol;
  final String interval;
  final List<CrossEvent> crossHistory;
  final double? threshold;
  final bool emailNotificationEnabled;
  final double? currentPrice;
  final Function(double?) onThresholdChanged;
  final Function(bool) onEmailNotificationChanged;
  final VoidCallback onClearHistory;

  const _CrossSettingsSheet({
    required this.symbol,
    required this.interval,
    required this.crossHistory,
    required this.threshold,
    required this.emailNotificationEnabled,
    required this.currentPrice,
    required this.onThresholdChanged,
    required this.onEmailNotificationChanged,
    required this.onClearHistory,
  });

  @override
  State<_CrossSettingsSheet> createState() => _CrossSettingsSheetState();
}

class _CrossSettingsSheetState extends State<_CrossSettingsSheet> {
  final ChartService _chartService = ChartService();
  late TextEditingController _thresholdController;
  late TextEditingController _emailController;
  late bool _emailEnabled;
  List<String> _registeredEmails = [];
  bool _isLoadingEmails = false;
  bool _isEmailExpanded = false;

  @override
  void initState() {
    super.initState();
    _thresholdController = TextEditingController(
      text: widget.threshold?.toStringAsFixed(2) ?? '',
    );
    _emailController = TextEditingController();
    _emailEnabled = widget.emailNotificationEnabled;
    _loadRegisteredEmails();
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadRegisteredEmails() async {
    setState(() => _isLoadingEmails = true);
    final emails = await _chartService.getEmails(symbol: widget.symbol);
    if (mounted) {
      setState(() {
        _registeredEmails = emails;
        _isLoadingEmails = false;
      });
    }
  }

  Future<void> _registerEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('有効なメールアドレスを入力してください')),
      );
      return;
    }

    final success = await _chartService.registerEmail(
      email: email,
      symbol: widget.symbol,
    );

    if (success) {
      _emailController.clear();
      await _loadRegisteredEmails();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('メールアドレスを登録しました')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登録に失敗しました')),
        );
      }
    }
  }

  Future<void> _deleteEmail(String email) async {
    final success = await _chartService.deleteEmail(
      email: email,
      symbol: widget.symbol,
    );

    if (success) {
      await _loadRegisteredEmails();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('メールアドレスを削除しました')),
        );
      }
    }
  }

  bool _isSendingTest = false;

  Future<void> _sendTestEmail() async {
    if (_registeredEmails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先にメールアドレスを登録してください')),
      );
      return;
    }

    setState(() => _isSendingTest = true);

    final success = await _chartService.sendTestEmail(symbol: widget.symbol);

    if (mounted) {
      setState(() => _isSendingTest = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'テストメールを送信しました' : 'テストメールの送信に失敗しました'),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // ハンドル
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // ヘッダー
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'クロス履歴・通知設定',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      widget.onClearHistory();
                      Navigator.pop(context);
                    },
                    child: const Text('履歴クリア'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 設定と履歴
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  // 閾値設定
                  _buildThresholdSection(),
                  const SizedBox(height: 24),
                  // メール通知設定
                  _buildEmailNotificationSection(),
                  const SizedBox(height: 24),
                  // クロス履歴
                  _buildCrossHistorySection(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildThresholdSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.straighten, size: 20),
                SizedBox(width: 8),
                Text(
                  '閾値設定',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'クロス発生時の価格から現在価格の差がこの値を超えるとメール通知されます。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _thresholdController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '閾値 (\$)',
                      hintText: '例: 100.00',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (value) {
                      final parsed = double.tryParse(value);
                      widget.onThresholdChanged(parsed);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    final parsed = double.tryParse(_thresholdController.text);
                    widget.onThresholdChanged(parsed);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('閾値を保存しました')),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailNotificationSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // メール通知スイッチ
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.email_outlined, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'メール通知',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _emailEnabled,
                  onChanged: (value) {
                    setState(() {
                      _emailEnabled = value;
                    });
                    widget.onEmailNotificationChanged(value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _emailEnabled
                  ? '閾値達成時にメールで通知されます。'
                  : 'メール通知はオフです。',
              style: TextStyle(
                fontSize: 12,
                color: _emailEnabled ? Colors.green : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            // メールアドレス登録欄
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'メールアドレスを入力',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _registerEmail,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  child: const Text('登録'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 登録済みメールアドレス（ドロップダウン）
            InkWell(
              onTap: () {
                setState(() {
                  _isEmailExpanded = !_isEmailExpanded;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.people_outline, size: 18, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Text(
                          '登録済み (${_registeredEmails.length}件)',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                    Icon(
                      _isEmailExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
            ),
            // 展開時のメールリスト
            if (_isEmailExpanded) ...[
              const SizedBox(height: 8),
              if (_isLoadingEmails)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_registeredEmails.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    '登録されたメールアドレスがありません',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _registeredEmails.length,
                    itemBuilder: (context, index) {
                      final email = _registeredEmails[index];
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        leading: const Icon(Icons.mail_outline, size: 18),
                        title: Text(email, style: const TextStyle(fontSize: 13)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _deleteEmail(email),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      );
                    },
                  ),
                ),
            ],
            const SizedBox(height: 16),
            // テスト送信ボタン
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSendingTest ? null : _sendTestEmail,
                icon: _isSendingTest
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_isSendingTest ? '送信中...' : 'テストメール送信'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCrossHistorySection() {
    final historyForInterval = widget.crossHistory
        .where((e) => e.interval == widget.interval)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history, size: 20),
            const SizedBox(width: 8),
            Text(
              'クロス履歴 (${widget.interval})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (historyForInterval.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'クロス履歴がありません',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'BB/EMAを有効にするとクロスが検知されます',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...historyForInterval.map((event) => _buildCrossEventCard(event)),
      ],
    );
  }

  Widget _buildCrossEventCard(CrossEvent event) {
    final isUp = event.direction == CrossDirection.up;
    final diff = widget.currentPrice != null
        ? (widget.currentPrice! - event.price).abs()
        : null;
    final thresholdReached = widget.threshold != null && diff != null && diff >= widget.threshold!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: thresholdReached ? Colors.orange.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 方向アイコン
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isUp ? AppColors.bullish.withAlpha(30) : AppColors.bearish.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isUp ? Icons.arrow_upward : Icons.arrow_downward,
                color: isUp ? AppColors.bullish : AppColors.bearish,
              ),
            ),
            const SizedBox(width: 12),
            // 情報
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        event.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isUp ? '上抜け' : '下抜け',
                        style: TextStyle(
                          fontSize: 12,
                          color: isUp ? AppColors.bullish : AppColors.bearish,
                        ),
                      ),
                      if (thresholdReached) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '閾値達成',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'クロス時: \$${event.price.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (diff != null)
                    Text(
                      '差分: \$${diff.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
            // 時刻
            Text(
              DateFormat('MM/dd HH:mm').format(event.timestamp),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
