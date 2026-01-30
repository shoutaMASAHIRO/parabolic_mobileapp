import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/candle.dart';
import '../providers/auth_provider.dart';
import '../services/chart_service.dart';
import '../services/cross_detection_service.dart';
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
  ChartType _chartType = ChartType.line;

  // 自動更新タイマー（60秒間隔）
  static const int _refreshIntervalSeconds = 60;
  Timer? _countdownTimer;
  int _secondsUntilRefresh = _refreshIntervalSeconds;

  // チャートのズーム・パン状態
  double _chartZoom = 1.0;
  double _chartPanOffsetX = 0.0;
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
  };

  final List<String> _intervals = ['5m', '15m', '30m', '1h', '4h', '1d', '1wk', '1mo'];

  // 通貨表示切替（USD/JPY）
  bool _showJPY = false;
  double _usdJpyRate = 155.0; // デフォルト値（APIから取得して更新）

  // インジケーターのゲッター
  bool get _showBB => _indicators['bb']?.enabled ?? false;
  bool get _showEMA => _indicators['ema']?.enabled ?? false;

  // パラメータのゲッター（型安全に変換）
  int get _bbPeriod => _safeInt(_indicators['bb']?.params['period'], 20);
  double get _bbStdDev1 => _safeDouble(_indicators['bb']?.params['stdDev1'], 1.0);
  double get _bbStdDev2 => _safeDouble(_indicators['bb']?.params['stdDev2'], 2.0);
  int get _emaPeriod1 => _safeInt(_indicators['ema']?.params['period1'], 10);
  int get _emaPeriod2 => _safeInt(_indicators['ema']?.params['period2'], 25);
  int get _emaPeriod3 => _safeInt(_indicators['ema']?.params['period3'], 50);

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
    _loadExchangeRate();
    _loadData();
    _loadCrossSettings();
    _startRefreshTimer();
  }

  // 為替レートを読み込み
  Future<void> _loadExchangeRate() async {
    final rate = await _chartService.getUsdJpyRate();
    if (rate != null && mounted) {
      setState(() {
        _usdJpyRate = rate;
      });
    }
  }

  // サーバーからインジケーター設定を読み込み
  Future<void> _loadIndicatorSettingsFromServer() async {
    final settings = await _chartService.getIndicatorSettingsFromServer();
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
      final candles = await _chartService.getChartData(
        widget.symbol,
        interval: _interval,
      );

      if (mounted) {
        setState(() {
          _candles = candles;
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
      final candles = await _chartService.getChartData(
        widget.symbol,
        interval: _interval,
      );

      final fetchTime = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('[REFRESH] データ取得完了: ${fetchTime}ms, ${candles.length}本');

      if (mounted && candles.isNotEmpty) {
        final lastCandle = candles.last;
        debugPrint('[REFRESH] 最新価格: ${lastCandle.close}');

        setState(() {
          _candles = candles;
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
      bbEnabled: _showBB,
      emaEnabled: _showEMA,
      bbPeriod: _bbPeriod,
      bbStdDev: _bbStdDev2,
      emaPeriod1: _emaPeriod1,
      emaPeriod2: _emaPeriod2,
      emaPeriod3: _emaPeriod3,
      emailAlertsEnabled: _emailNotificationEnabled,
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
        return Colors.orange;
      case MarketCategory.forex:
        return Colors.green;
      case MarketCategory.stock:
        return Colors.blue;
    }
  }

  // タイマーウィジェットを構築
  Widget _buildTimerWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _isRefreshing
            ? Colors.blue
            : _secondsUntilRefresh <= 10
                ? Colors.orange
                : Colors.green,
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
    final displayName = widget.symbol.replaceAll('-USD', '');

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
                    decoration: const BoxDecoration(
                      color: Colors.blue,
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
                        color: Colors.red,
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
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 銘柄情報とタイマー
              _buildSymbolHeader(),
              const SizedBox(height: 12),
              _buildPriceHeader(),
              const SizedBox(height: 16),
              _buildChartTypeSelector(),
              const SizedBox(height: 8),
              _buildCurrencyToggle(),
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
    final displayName = widget.symbol.replaceAll('-USD', '');

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
          color: Colors.blue,
          icon: Icons.stacked_line_chart,
        );
      case 'ema':
        return _IndicatorConfig(
          key: 'ema',
          name: 'EMA',
          fullName: '指数移動平均',
          description: 'EMA(10), EMA(25), EMA(50)',
          color: Colors.orange,
          icon: Icons.show_chart,
        );
      default:
        return _IndicatorConfig(
          key: key,
          name: key.toUpperCase(),
          fullName: key,
          description: '',
          color: Colors.grey,
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
              color: isPositive ? Colors.green : Colors.red,
              size: 20,
            ),
            const SizedBox(width: 4),
            Text(
              '${isPositive ? '+' : ''}$_currencySymbol${_formatPrice(_convertPrice(priceChange.abs()))} (${changePercent.toStringAsFixed(2)}%)',
              style: TextStyle(
                fontSize: 16,
                color: isPositive ? Colors.green : Colors.red,
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
    final closePrices = candles.map((c) => c.close).toList();

    final spots = candles.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.close);
    }).toList();

    final minY = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final maxY = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);

    final isPositive = candles.last.close >= candles.first.close;
    final chartColor = isPositive ? Colors.green : Colors.red;

    // インジケーターデータを準備
    final lineBars = <LineChartBarData>[
      // メインの価格ライン
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

    // ボリンジャーバンド
    if (_showBB) {
      final bb = TechnicalIndicators.calculateBollingerBands(
        closePrices,
        period: _bbPeriod,
        stdDev1: _bbStdDev1,
        stdDev2: _bbStdDev2,
      );
      lineBars.addAll(_createBBLines(bb, candles.length));
    }

    // EMA
    if (_showEMA) {
      lineBars.addAll(_createEMALines(closePrices, candles.length));
    }

    // ズーム・パンに基づいて表示範囲を計算
    final totalDataPoints = candles.length.toDouble();
    final visibleDataPoints = totalDataPoints / _chartZoom;
    final maxPanOffset = totalDataPoints - visibleDataPoints;
    final panOffset = (_chartPanOffsetX * maxPanOffset).clamp(0.0, maxPanOffset);
    final visibleMinX = panOffset;
    final visibleMaxX = panOffset + visibleDataPoints - 1;

    // 表示範囲内のデータでY軸の範囲を再計算
    final visibleStartIdx = visibleMinX.floor().clamp(0, candles.length - 1);
    final visibleEndIdx = visibleMaxX.ceil().clamp(0, candles.length - 1);
    final visibleCandles = candles.sublist(visibleStartIdx, visibleEndIdx + 1);

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

    return Column(
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
                    child: LineChart(
                        LineChartData(
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: true,
                            horizontalInterval: (adjustedMaxY - adjustedMinY) / 5,
                            verticalInterval: xLabelInterval.toDouble(),
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color: Colors.grey.shade800,
                                strokeWidth: 0.5,
                              );
                            },
                            getDrawingVerticalLine: (value) {
                              return FlLine(
                                color: Colors.grey.shade800,
                                strokeWidth: 0.5,
                              );
                            },
                          ),
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
                                  if (index < 0 || index >= candles.length) return null;
                                  if (spot.barIndex != 0) return null;
                                  final candle = candles[index];
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
        // クロスヘア情報表示
        if (_showCrosshair && _crosshairIndex != null && _crosshairIndex! < visibleCandles.length)
          _buildCrosshairInfo(visibleCandles[_crosshairIndex!]),
      ],
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
            _chartPanOffsetX = (_chartPanOffsetX - deltaX).clamp(0.0, (1.0 - (1.0 / _chartZoom)).clamp(0.0, 1.0));
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.black,
          ),
          child: Stack(
            children: [
              SizedBox(height: chartHeight, child: child),
              // クロスヘアオーバーレイ
              if (_showCrosshair && _crosshairPosition != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: CrosshairPainter(
                      position: _crosshairPosition!,
                      color: Colors.white54,
                    ),
                  ),
                ),
            ],
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
                  _chartPanOffsetX = _chartPanOffsetX.clamp(0.0, (1.0 - (1.0 / _chartZoom)).clamp(0.0, 1.0));
                }),
              ),
            ),
          ),
          // リセットボタン
          IconButton(
            icon: Icon(Icons.refresh, size: 20, color: Colors.grey.shade600),
            onPressed: () => setState(() {
              _chartZoom = 1.0;
              _chartPanOffsetX = 0.0;
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

    // BB: グレー系で統一（ローソク足と区別しやすく）
    lines.add(_createIndicatorLine(bb.middle, length, Colors.white70, 1.5));
    lines.add(_createIndicatorLine(bb.upper1, length, Colors.grey.shade500, 1.0));
    lines.add(_createIndicatorLine(bb.lower1, length, Colors.grey.shade500, 1.0));
    lines.add(_createIndicatorLine(bb.upper2, length, Colors.grey.shade600, 1.0));
    lines.add(_createIndicatorLine(bb.lower2, length, Colors.grey.shade600, 1.0));

    return lines;
  }

  List<LineChartBarData> _createEMALines(List<double> prices, int length) {
    final lines = <LineChartBarData>[];

    // EMA: オレンジ系で統一
    final ema1 = TechnicalIndicators.calculateEMA(prices, _emaPeriod1);
    lines.add(_createIndicatorLine(ema1, length, Colors.orange.shade300, 1.5));

    final ema2 = TechnicalIndicators.calculateEMA(prices, _emaPeriod2);
    lines.add(_createIndicatorLine(ema2, length, Colors.orange, 1.5));

    final ema3 = TechnicalIndicators.calculateEMA(prices, _emaPeriod3);
    lines.add(_createIndicatorLine(ema3, length, Colors.orange.shade700, 1.5));

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
    final closePrices = candles.map((c) => c.close).toList();

    final minY = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final maxY = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);

    // ズーム・パンに基づいて表示範囲を計算
    final totalDataPoints = candles.length.toDouble();
    final visibleDataPoints = (totalDataPoints / _chartZoom).round();
    final maxPanOffset = candles.length - visibleDataPoints;
    final panOffset = (_chartPanOffsetX * maxPanOffset).round().clamp(0, maxPanOffset);
    final visibleStartIdx = panOffset;
    final visibleEndIdx = (panOffset + visibleDataPoints).clamp(0, candles.length);
    final visibleCandles = candles.sublist(visibleStartIdx, visibleEndIdx);

    // 表示範囲内のY軸範囲を計算
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

    // インジケーターを計算（表示範囲用にスライス）
    BollingerBandsResult? visibleBB;
    List<List<double?>>? visibleEmaLines;

    if (_showBB) {
      final fullBB = TechnicalIndicators.calculateBollingerBands(
        closePrices,
        period: _bbPeriod,
        stdDev1: _bbStdDev1,
        stdDev2: _bbStdDev2,
      );
      // 表示範囲にスライス
      visibleBB = BollingerBandsResult(
        middle: fullBB.middle.sublist(visibleStartIdx, visibleEndIdx),
        upper1: fullBB.upper1.sublist(visibleStartIdx, visibleEndIdx),
        lower1: fullBB.lower1.sublist(visibleStartIdx, visibleEndIdx),
        upper2: fullBB.upper2.sublist(visibleStartIdx, visibleEndIdx),
        lower2: fullBB.lower2.sublist(visibleStartIdx, visibleEndIdx),
      );
    }
    if (_showEMA) {
      final fullEma1 = TechnicalIndicators.calculateEMA(closePrices, _emaPeriod1);
      final fullEma2 = TechnicalIndicators.calculateEMA(closePrices, _emaPeriod2);
      final fullEma3 = TechnicalIndicators.calculateEMA(closePrices, _emaPeriod3);
      // 表示範囲にスライス
      visibleEmaLines = [
        fullEma1.sublist(visibleStartIdx, visibleEndIdx),
        fullEma2.sublist(visibleStartIdx, visibleEndIdx),
        fullEma3.sublist(visibleStartIdx, visibleEndIdx),
      ];
    }

    // X軸ラベル間隔を計算（重複防止）
    final xLabelInterval = _calculateXLabelInterval(visibleCandles.length);

    return Column(
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
        // クロスヘア情報表示
        if (_showCrosshair && _crosshairIndex != null && _crosshairIndex! < visibleCandles.length)
          _buildCrosshairInfo(visibleCandles[_crosshairIndex!]),
      ],
    );
  }

  // X軸ラベル間隔を計算（重複防止）
  int _calculateXLabelInterval(int dataPoints) {
    if (dataPoints <= 5) return 1;
    if (dataPoints <= 15) return 3;
    if (dataPoints <= 30) return 5;
    if (dataPoints <= 60) return 10;
    if (dataPoints <= 120) return 20;
    return (dataPoints / 5).ceil();
  }

  // Y軸ラベル
  Widget _buildYAxisLabels(double minY, double maxY) {
    final range = maxY - minY;
    final labels = <Widget>[];
    for (int i = 0; i <= 5; i++) {
      final value = maxY - (range * i / 5);
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
        final candleWidth = constraints.maxWidth / candles.length;
        final format = ['5m', '15m', '30m', '1h', '4h'].contains(_interval)
            ? DateFormat('HH:mm')
            : DateFormat('MM/dd');

        for (int i = 0; i < candles.length; i += interval) {
          // ラベル位置を計算（左端・右端で切れないように調整）
          double leftPos = i * candleWidth + candleWidth / 2 - 20;
          // 左端で切れないように
          if (leftPos < 0) leftPos = 0;
          // 右端で切れないように
          if (leftPos > constraints.maxWidth - 40) {
            leftPos = constraints.maxWidth - 40;
          }

          labels.add(
            Positioned(
              left: leftPos,
              child: SizedBox(
                width: 40,
                child: Text(
                  format.format(candles[i].date),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
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
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
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

  // 価格をフォーマット（通貨変換込み）
  String _formatPriceWithCurrency(double priceUSD) {
    final price = _convertPrice(priceUSD);
    return '$_currencySymbol${_formatPrice(price)}';
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
  }) : totalLength = totalLength ?? candles.length;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final candleWidth = size.width / candles.length;
    final priceRange = maxY - minY;

    // グリッド線を描画（黒背景用に明るく）
    final gridPaint = Paint()
      ..color = Colors.grey.shade800
      ..strokeWidth = 0.5;

    // 横グリッド線
    for (int i = 0; i <= 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 縦グリッド線（X軸ラベル位置に合わせる）
    for (int i = 0; i < candles.length; i += xLabelInterval) {
      final x = i * candleWidth + candleWidth / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // ボリンジャーバンドを描画（グレー系で統一）
    if (bb != null) {
      _drawIndicatorLine(canvas, size, bb!.middle, Colors.white70, 1.5, priceRange);
      _drawIndicatorLine(canvas, size, bb!.upper1, Colors.grey.shade500, 1.0, priceRange);
      _drawIndicatorLine(canvas, size, bb!.lower1, Colors.grey.shade500, 1.0, priceRange);
      _drawIndicatorLine(canvas, size, bb!.upper2, Colors.grey.shade600, 1.0, priceRange);
      _drawIndicatorLine(canvas, size, bb!.lower2, Colors.grey.shade600, 1.0, priceRange);
    }

    // EMAを描画（オレンジ系で統一）
    if (emaLines != null && emaLines!.isNotEmpty) {
      final emaColors = [Colors.orange.shade300, Colors.orange, Colors.orange.shade700];
      for (int i = 0; i < emaLines!.length && i < emaColors.length; i++) {
        _drawIndicatorLine(canvas, size, emaLines![i], emaColors[i], 1.5, priceRange);
      }
    }

    // 各ローソク足を描画
    for (int i = 0; i < candles.length; i++) {
      final candle = candles[i];
      final x = i * candleWidth + candleWidth / 2;

      // Y座標を計算（上が高値、下が安値）
      final highY = size.height - ((candle.high - minY) / priceRange * size.height);
      final lowY = size.height - ((candle.low - minY) / priceRange * size.height);
      final openY = size.height - ((candle.open - minY) / priceRange * size.height);
      final closeY = size.height - ((candle.close - minY) / priceRange * size.height);

      final isPositive = candle.close >= candle.open;
      final color = isPositive ? Colors.green : Colors.red;

      // ヒゲ（高値-安値の線）
      final wickPaint = Paint()
        ..color = color
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, highY), Offset(x, lowY), wickPaint);

      // ローソク本体
      final bodyPaint = Paint()
        ..color = color
        ..style = isPositive ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = 1;

      final bodyTop = isPositive ? closeY : openY;
      final bodyBottom = isPositive ? openY : closeY;
      final bodyHeight = (bodyBottom - bodyTop).abs();

      // 本体の幅（データ量に応じて調整）
      final bodyWidth = (candleWidth * 0.7).clamp(2.0, 12.0);

      final rect = Rect.fromCenter(
        center: Offset(x, (bodyTop + bodyBottom) / 2),
        width: bodyWidth,
        height: bodyHeight < 1 ? 1 : bodyHeight,
      );
      canvas.drawRect(rect, bodyPaint);
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
        oldDelegate.emaLines != emaLines;
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

  // 利用可能なインジケーター一覧（ここに追加していく）
  static final List<_IndicatorConfig> _availableIndicators = [
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
    // 将来追加するインジケーター例
    // _IndicatorConfig(
    //   key: 'rsi',
    //   name: 'RSI',
    //   fullName: '相対力指数',
    //   description: '買われすぎ・売られすぎを判定',
    //   color: Colors.purple,
    //   icon: Icons.speed,
    //   params: [
    //     _ParamConfig(key: 'period', label: '期間', min: 2, max: 50),
    //   ],
    // ),
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
            // インジケーターリスト
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _availableIndicators.length,
                itemBuilder: (context, index) {
                  final config = _availableIndicators[index];
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
                },
              ),
            ),
          ],
        );
      },
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
          backgroundColor: success ? Colors.green : Colors.red,
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
                color: isUp ? Colors.green.withAlpha(30) : Colors.red.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isUp ? Icons.arrow_upward : Icons.arrow_downward,
                color: isUp ? Colors.green : Colors.red,
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
                          color: isUp ? Colors.green : Colors.red,
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
