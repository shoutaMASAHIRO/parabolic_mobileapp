import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/candle.dart';
import '../providers/auth_provider.dart';
import '../services/chart_service.dart';
import '../services/cross_detection_service.dart';
import '../services/memo_service.dart';
import '../theme/app_colors.dart';
import '../widgets/chart_painters.dart';
import 'memo_screen.dart';
import 'home_screen.dart' show MarketCategory;

enum ChartType { line, candlestick, heikinAshi }

class IndicatorSettings {
  bool enabled;
  final Map<String, dynamic> params;
  IndicatorSettings({this.enabled = false, Map<String, dynamic>? params}) : params = params ?? {};
  IndicatorSettings copyWith({bool? enabled, Map<String, dynamic>? params}) =>
      IndicatorSettings(enabled: enabled ?? this.enabled, params: params ?? Map.from(this.params));
}

class DetailScreen extends StatefulWidget {
  final String symbol;
  final MarketCategory category;
  const DetailScreen({super.key, required this.symbol, this.category = MarketCategory.crypto});
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> with SingleTickerProviderStateMixin {
  final ChartService _chartService = ChartService();
  final MemoService _memoService = MemoService();
  List<Candle> _candles = [];
  bool _isLoading = true;
  String? _error;
  String _interval = '1d';
  ChartType _chartType = ChartType.candlestick;

  late AnimationController _scrollAnimationController;
  double _scrollVelocity = 0.0;
  static const int _refreshIntervalSeconds = 60;
  Timer? _countdownTimer;
  int _secondsUntilRefresh = _refreshIntervalSeconds;

  double _chartZoom = 1.0;
  double _chartPanOffsetX = 1.0;
  double _chartPanOffsetY = 0.0;
  static const double _minZoom = 1.0;
  static const double _maxZoom = 8.0;
  double? _lastScaleStart;
  Offset? _lastFocalPoint;

  Offset? _crosshairPosition;
  int? _crosshairIndex;
    bool _showCrosshair = false;
    double? _touchedPrice;
    DateTime? _touchedDateTime;
    Map<String, double?> _touchedIndicatorLevels = {}; 
   // 各インジケーターごとのタッチ位置
  int _memoCount = 0;
  final Set<String> _sentNotifications = {};
  Map<String, double> _allIntervalThresholds = {};

  final Map<String, IndicatorSettings> _indicators = {
    'bb': IndicatorSettings(enabled: false, params: {'period': 20, 'stdDev1': 1.0, 'stdDev2': 2.0}),
    'ema': IndicatorSettings(enabled: false, params: {'period1': 10, 'period2': 25, 'period3': 50}),
    'rsi': IndicatorSettings(enabled: false, params: {'period': 14}),
    'macd': IndicatorSettings(enabled: false, params: {'fast': 12, 'slow': 26, 'signal': 9}),
    'stochastic': IndicatorSettings(enabled: false, params: {'kPeriod': 14, 'dPeriod': 3, 'smooth': 3}),
    'cci': IndicatorSettings(enabled: false, params: {'period': 20}),
  };

  final List<String> _intervals = ['5m', '15m', '30m', '1h', '4h', '1d', '1wk', '1mo'];
  bool _showJPY = false;
  double _usdJpyRate = 155.0;

  bool get _showBB => _indicators['bb']?.enabled ?? false;
  bool get _showEMA => _indicators['ema']?.enabled ?? false;
  bool get _showRSI => _indicators['rsi']?.enabled ?? false;
  bool get _showMACD => _indicators['macd']?.enabled ?? false;
  bool get _showStochastic => _indicators['stochastic']?.enabled ?? false;
  bool get _showCCI => _indicators['cci']?.enabled ?? false;

  int get _bbPeriod => _safeInt(_indicators['bb']?.params['period'], 20);
  double get _bbStdDev1 => _safeDouble(_indicators['bb']?.params['stdDev1'], 1.0);
  double get _bbStdDev2 => _safeDouble(_indicators['bb']?.params['stdDev2'], 2.0);
  int get _emaPeriod1 => _safeInt(_indicators['ema']?.params['period1'], 10);
  int get _emaPeriod2 => _safeInt(_indicators['ema']?.params['period2'], 25);
  int get _emaPeriod3 => _safeInt(_indicators['ema']?.params['period3'], 50);
  int get _rsiPeriod => _safeInt(_indicators['rsi']?.params['period'], 14);
  int get _macdFast => _safeInt(_indicators['macd']?.params['fast'], 12);
  int get _macdSlow => _safeInt(_indicators['macd']?.params['slow'], 26);
  int get _macdSignal => _safeInt(_indicators['macd']?.params['signal'], 9);
  int get _stochKPeriod => _safeInt(_indicators['stochastic']?.params['kPeriod'], 14);
  int get _stochDPeriod => _safeInt(_indicators['stochastic']?.params['dPeriod'], 3);
  int get _stochSmooth => _safeInt(_indicators['stochastic']?.params['smooth'], 3);
  int get _cciPeriod => _safeInt(_indicators['cci']?.params['period'], 20);

  static int _safeInt(dynamic v, int d) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? d : d));
  static double _safeDouble(dynamic v, double d) => v is double ? v : (v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? d : d));

  int get _activeIndicatorCount => _indicators.values.where((v) => v.enabled).length;
  List<CrossEvent> _crossHistory = [];
  double? _threshold;
  bool _emailNotificationEnabled = false;
  bool _isMaximizedChart = false;

  @override
  void initState() {
    super.initState();
    _scrollAnimationController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _scrollAnimationController.addListener(_handleScrollAnimation);
    _loadIndicatorSettingsFromServer();
    _loadData();
    _loadCrossSettings();
    _loadAllIntervalThresholds();
    _loadMemoCount();
    _startRefreshTimer();
  }

  Future<void> _loadAllIntervalThresholds() async {
    final thresholds = await _chartService.getAllThresholdsFromServer(widget.symbol);
    if (mounted) setState(() => _allIntervalThresholds = thresholds);
  }

  Future<void> _loadMemoCount() async {
    try {
      final memos = await _memoService.getMemos(widget.symbol);
      if (mounted) setState(() => _memoCount = memos.length);
    } catch (e) {
      debugPrint('Error loading memo count: $e');
    }
  }

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

  void _handleScrollAnimation() {
    if (_scrollAnimationController.isAnimating) {
      setState(() { _chartPanOffsetX = (_chartPanOffsetX + _scrollVelocity).clamp(0.0, 1.0); });
      _scrollVelocity *= 0.92;
      if (_scrollVelocity.abs() < 0.0001) _scrollAnimationController.stop();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _scrollAnimationController.dispose();
    super.dispose();
  }

  void _startRefreshTimer() {
    _countdownTimer?.cancel();
    _secondsUntilRefresh = _refreshIntervalSeconds;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isRefreshing) return;
      _secondsUntilRefresh--;
      if (_secondsUntilRefresh <= 0) {
        _isRefreshing = true;
        setState(() {});
        _refreshChartData().then((_) {
          if (mounted) setState(() { _secondsUntilRefresh = _refreshIntervalSeconds; _isRefreshing = false; });
        });
      } else { setState(() {}); }
    });
  }

  bool _isRefreshing = false;

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final results = await Future.wait([_chartService.getChartData(widget.symbol, interval: _interval), _chartService.getUsdJpyRate()]);
      if (mounted) {
        setState(() {
          _candles = results[0] as List<Candle>;
          if (results[1] != null) _usdJpyRate = results[1] as double;
          _chartPanOffsetX = 1.0;
          _isLoading = false;
        });
        _refreshCrossHistory();
      }
    } catch (e) { if (mounted) setState(() { _error = e.toString(); _isLoading = false; }); }
  }

  Future<void> _refreshChartData() async {
    try {
      final results = await Future.wait([_chartService.getChartData(widget.symbol, interval: _interval), _chartService.getUsdJpyRate()]);
      if (mounted && (results[0] as List<Candle>).isNotEmpty) {
        setState(() {
          _candles = results[0] as List<Candle>;
          if (results[1] != null) _usdJpyRate = results[1] as double;
        });
        _refreshCrossHistory();
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _loadCrossSettings() async {
    final threshold = await _chartService.getThresholdFromServer(symbol: widget.symbol, interval: _interval);
    final serverHistory = await _chartService.getCrossHistoryFromServer(widget.symbol);
    if (mounted) setState(() { _threshold = threshold; _crossHistory = _parseServerCrossHistory(serverHistory, _interval); });
  }

  List<CrossEvent> _parseServerCrossHistory(Map<String, dynamic> serverHistory, String interval) {
    final events = <CrossEvent>[];
    final intervalData = serverHistory[interval] as Map<String, dynamic>?;
    if (intervalData == null) return events;
    for (final entry in intervalData.entries) {
      final data = entry.value as Map<String, dynamic>?;
      if (data == null) continue;
      final price = (data['price'] as num?)?.toDouble();
      final timestamp = data['timestamp'] as String?;
      if (price == null || timestamp == null) continue;
      events.add(CrossEvent(
        symbol: widget.symbol, interval: interval, type: entry.key.startsWith('ema') ? CrossType.ema : CrossType.bb,
        indicatorName: entry.key, price: price, lineValue: (data['lineValue'] as num?)?.toDouble() ?? price,
        direction: data['direction'] == 'up' ? CrossDirection.up : CrossDirection.down, timestamp: DateTime.parse(timestamp),
      ));
    }
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events;
  }

  Future<void> _refreshCrossHistory() async {
    final serverHistory = await _chartService.getCrossHistoryFromServer(widget.symbol);
    if (mounted) {
      setState(() { _crossHistory = _parseServerCrossHistory(serverHistory, _interval); });
      _checkThresholdAndNotify();
    }
  }

  void _checkThresholdAndNotify() {
    if (_threshold == null || !_emailNotificationEnabled || _candles.isEmpty) return;
    final currentPrice = _candles.last.close;
    for (final event in _crossHistory) {
      if (CrossDetectionService.checkThresholdReached(event, currentPrice, _threshold!)) {
        final key = '${event.timestamp.millisecondsSinceEpoch}_${event.indicatorName}';
        if (!_sentNotifications.contains(key)) {
          _chartService.sendThresholdEmail(
            symbol: widget.symbol, interval: _interval, crossEvent: event,
            currentPrice: currentPrice, threshold: _threshold!,
          );
          _sentNotifications.add(key);
        }
      }
    }
  }

  Future<void> _syncIndicatorSettingsToServer() async {
    await _chartService.saveIndicatorSettingsToServer(
      symbol: widget.symbol, bbEnabled: _showBB, emaEnabled: _showEMA, bbPeriod: _bbPeriod, bbStdDev: _bbStdDev2,
      emaPeriod1: _emaPeriod1, emaPeriod2: _emaPeriod2, emaPeriod3: _emaPeriod3, emailAlertsEnabled: _emailNotificationEnabled,
      rsiEnabled: _showRSI, rsiPeriod: _rsiPeriod, macdEnabled: _showMACD, macdFast: _macdFast, macdSlow: _macdSlow, macdSignal: _macdSignal,
      stochasticEnabled: _showStochastic, stochKPeriod: _stochKPeriod, stochDPeriod: _stochDPeriod, stochSmooth: _stochSmooth,
      cciEnabled: _showCCI, cciPeriod: _cciPeriod,
    );
  }

  Future<void> _handleLogout() async {
    await context.read<AuthProvider>().logout();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Color _getCategoryColor() {
    switch (widget.category) {
      case MarketCategory.crypto: return AppColors.crypto;
      case MarketCategory.forex: return AppColors.forex;
      case MarketCategory.stock: return AppColors.stock;
    }
  }

  Widget _buildTimerWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _isRefreshing ? AppColors.info : (_secondsUntilRefresh <= 10 ? AppColors.warning : AppColors.success),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isRefreshing) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          else const Icon(Icons.timer, size: 16, color: Colors.white),
          const SizedBox(width: 4),
          Text(_isRefreshing ? '更新中' : '${_secondsUntilRefresh}s', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.chartBackground,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(_isMaximizedChart ? 0 : kToolbarHeight),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _isMaximizedChart ? 0 : 1,
          child: _isMaximizedChart 
              ? const SizedBox.shrink() 
              : AppBar(
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  backgroundColor: AppColors.chartBackground,
                  titleSpacing: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  title: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Text(
                      '${widget.category.label}一覧',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _buildTimerWidget(),
                    ),
                    IconButton(icon: const Icon(Icons.logout), tooltip: 'ログアウト', onPressed: () => _handleLogout()),
                  ],
                ),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildFooter(),
    );
  }

  String _getIntervalLabel(String i) {
    switch (i) {
      case '5m': return '5分'; case '15m': return '15分'; case '30m': return '30分'; case '1h': return '1時間';
      case '4h': return '4時間'; case '1d': return '1日'; case '1wk': return '1週間'; case '1mo': return '1ヶ月';
      default: return i;
    }
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.error_outline, size: 48, color: AppColors.error), const SizedBox(height: 16),
      Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 16),
      ElevatedButton(onPressed: _loadData, child: const Text('再試行')),
    ]));
    if (_candles.isEmpty) return const Center(child: Text('データがないため、現在表示できません'));

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: SizedBox(
              height: _isMaximizedChart ? 0 : null,
              child: _isMaximizedChart ? const SizedBox.shrink() : _buildSymbolHeader(),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _buildChart()),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: _isMaximizedChart ? 0 : 60,
                  decoration: const BoxDecoration(), // clipBehavior使用時はdecorationが必要
                  clipBehavior: Clip.antiAlias,
                  child: _buildRightToolbar(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSymbolHeader() {
    String displayName;
    switch (widget.category) {
      case MarketCategory.crypto: displayName = widget.symbol.replaceAll('-USD', ''); break;
      case MarketCategory.forex: displayName = widget.symbol.replaceAll('=X', '').replaceAllMapped(RegExp(r'([A-Z]{3})([A-Z]{3})'), (m) => '${m[1]}/${m[2]}'); break;
      case MarketCategory.stock: displayName = widget.symbol; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.chartBackground,
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: _getCategoryColor().withAlpha(30), borderRadius: BorderRadius.circular(8)),
            child: Icon(widget.category.icon, size: 22, color: _getCategoryColor()),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text('${widget.category.label} • ${widget.symbol}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ]),
          ),
          // 時間足選択ボタン
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: _showIntervalSettings,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2C38),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF4D88FF), width: 1.2),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 1))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_getIntervalLabel(_interval), style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, color: Color(0xFFFFD54F), size: 20),
                  ],
                ),
              ),
            ),
          ),
          // ベルマーク
          SizedBox(
            width: 60, height: 48,
            child: Center(
              child: GestureDetector(
                onTap: _showCrossSettings,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF57C00), Color(0xFFE65100)]),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFD54F), width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.notifications_active, size: 24, color: Color(0xFFFFE082)),
                    ),
                    if (_crossHistory.isNotEmpty)
                      Positioned(
                        right: -4, top: -4,
                        child: Container(
                          width: 14, height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30), shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.0),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 2)],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChartTypeSettings() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('チャートタイプ選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildChartTypeOption(type: ChartType.line, label: '折れ線', icon: Icons.show_chart),
                  _buildChartTypeOption(type: ChartType.candlestick, label: 'ローソク足', icon: Icons.candlestick_chart),
                  _buildChartTypeOption(type: ChartType.heikinAshi, label: '平均足', icon: Icons.bar_chart),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showIntervalSettings() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.access_time, color: AppColors.primaryLight, size: 20),
                  SizedBox(width: 8),
                  Text('時間足選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 12, runSpacing: 16,
                alignment: WrapAlignment.center,
                children: _intervals.map((i) => _buildIntervalOption(i)).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntervalOption(String i) {
    final bool isSelected = _interval == i;
    final bool hasThreshold = _allIntervalThresholds.containsKey(i);
    return GestureDetector(
      onTap: () {
        setState(() { _interval = i; _chartPanOffsetX = 1.0; });
        _loadData();
        _loadCrossSettings();
        Navigator.pop(context);
      },
      child: Container(
        width: (MediaQuery.of(context).size.width - 100) / 3,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withAlpha(40) : Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : (hasThreshold ? AppColors.warning.withAlpha(100) : Colors.transparent),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _getIntervalLabel(i),
              style: TextStyle(
                color: isSelected ? Colors.white : (hasThreshold ? AppColors.warning : AppColors.textSecondary),
                fontWeight: isSelected || hasThreshold ? FontWeight.bold : FontWeight.normal,
                fontSize: 15,
              ),
            ),
            if (hasThreshold) ...[
              const SizedBox(width: 4),
              const Icon(Icons.notifications_active, size: 16, color: AppColors.warning),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChartTypeOption({required ChartType type, required String label, required IconData icon}) {
    final bool isSelected = _chartType == type;
    return GestureDetector(
      onTap: () { setState(() { _chartType = type; }); Navigator.pop(context); },
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: isSelected ? AppColors.primary.withOpacity(0.2) : Colors.transparent, borderRadius: BorderRadius.circular(16), border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: 2)),
          child: Icon(icon, size: 32, color: isSelected ? AppColors.primary : AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? AppColors.primary : AppColors.textSecondary)),
      ]),
    );
  }

  void _showIndicatorSettings() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: _IndicatorSettingsSheet(
          indicators: _indicators,
          onChanged: (k, s) { setState(() => _indicators[k] = s); _syncIndicatorSettingsToServer(); },
          onToggle: (k, e) {
            setState(() {
              final isOsc = ['rsi', 'macd', 'stochastic', 'cci'].contains(k);
              if (e && isOsc) {
                _indicators.forEach((key, value) {
                  if (['rsi', 'macd', 'stochastic', 'cci'].contains(key) && key != k) {
                    value.enabled = false;
                  }
                });
              }
              _indicators[k]!.enabled = e;
            });
            _syncIndicatorSettingsToServer();
          },
        ),
      ),
    );
  }

  void _showCrossSettings() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: _CrossSettingsSheet(
          symbol: widget.symbol, interval: _interval, crossHistory: _crossHistory, threshold: _threshold, emailNotificationEnabled: _emailNotificationEnabled,
          currentPrice: _candles.isNotEmpty ? _candles.last.close : null,
          onThresholdChanged: (v) async {
            setState(() => _threshold = v);
            await _chartService.saveThresholdToServer(symbol: widget.symbol, interval: _interval, threshold: v);
            _loadAllIntervalThresholds();
          },
          onEmailNotificationChanged: (v) { setState(() => _emailNotificationEnabled = v); _syncIndicatorSettingsToServer(); },
          onClearHistory: () async { await _chartService.clearCrossHistoryOnServer(widget.symbol); await _refreshCrossHistory(); },
        ),
      ),
    );
  }

  _IndicatorConfig _getIndicatorConfig(String k) {
    switch (k) {
      case 'bb': return _IndicatorConfig(key: 'bb', name: 'BB', fullName: 'ボリンジャーバンド', description: '±1σ, ±2σ', color: AppColors.bbMiddle, icon: Icons.stacked_line_chart);
      case 'ema': return _IndicatorConfig(key: 'ema', name: 'EMA', fullName: '指数移動平均', description: 'EMA(10,25,50)', color: AppColors.emaMedium, icon: Icons.show_chart);
      case 'rsi': return _IndicatorConfig(key: 'rsi', name: 'RSI', fullName: '相対力指数', description: '70/30', color: AppColors.rsiLine, icon: Icons.trending_up);
      case 'macd': return _IndicatorConfig(key: 'macd', name: 'MACD', fullName: '移動平均収束拡散', description: 'シグナルクロス', color: AppColors.macdLine, icon: Icons.bar_chart);
      case 'stochastic': return _IndicatorConfig(key: 'stochastic', name: 'Stoch', fullName: 'ストキャスティクス', description: '80/20', color: AppColors.stochK, icon: Icons.ssid_chart);
      case 'cci': return _IndicatorConfig(key: 'cci', name: 'CCI', fullName: '商品チャンネル指数', description: '±100', color: AppColors.cciLine, icon: Icons.multiline_chart);
      default: return _IndicatorConfig(key: k, name: k.toUpperCase(), fullName: k, description: '', color: AppColors.textSecondary, icon: Icons.analytics);
    }
  }

  Widget _buildChart() {
    switch (_chartType) {
      case ChartType.line: return _buildLineChart(_candles);
      case ChartType.candlestick: return _buildCandlestickChart(_candles);
      case ChartType.heikinAshi: return _buildCandlestickChart(Candle.toHeikinAshi(_candles));
    }
  }

  Widget _buildLineChart(List<Candle> candles) {
    int maxP = 0; if (_showBB) maxP = math.max(maxP, _bbPeriod); if (_showEMA) maxP = math.max(maxP, math.max(_emaPeriod1, math.max(_emaPeriod2, _emaPeriod3)));
    final int startO = (maxP > 0) ? maxP - 1 : 0;
    final display = (startO > 0 && candles.length > startO) ? candles.sublist(startO) : candles;
    if (display.isEmpty) return const Center(child: Text('データ不足'));
    final total = display.length.toDouble();
    final visible = (_getBaseVisibleDataPoints() / _chartZoom).clamp(1.0, total);
    final pan = (_chartPanOffsetX * (total - visible)).clamp(0.0, total - visible);
    final visibleStart = pan.floor().clamp(0, display.length - 1);
    final visibleEnd = (pan + visible).ceil().clamp(visibleStart, display.length - 1);
    final visibleCandles = display.sublist(visibleStart, visibleEnd + 1);
    double vMinY = visibleCandles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    double vMaxY = visibleCandles.map((c) => c.high).reduce((a, b) => a > b ? a : b);

    if (_showBB) {
      final bb = TechnicalIndicators.calculateBollingerBands(candles.map((c) => c.close).toList(), period: _bbPeriod, stdDev1: _bbStdDev1, stdDev2: _bbStdDev2);
      final vUpper = _safeSublist(bb.upper2, visibleStart + startO, visibleEnd + startO + 1);
      final vLower = _safeSublist(bb.lower2, visibleStart + startO, visibleEnd + startO + 1);
      for (final v in vUpper) if (v != null && v > vMaxY) vMaxY = v;
      for (final v in vLower) if (v != null && v < vMinY) vMinY = v;
    }
    if (_showEMA) {
      final prices = candles.map((c) => c.close).toList();
      final e1 = TechnicalIndicators.calculateEMA(prices, _emaPeriod1);
      final e2 = TechnicalIndicators.calculateEMA(prices, _emaPeriod2);
      final e3 = TechnicalIndicators.calculateEMA(prices, _emaPeriod3);
      for (final e in [e1, e2, e3]) {
        final ve = _safeSublist(e, visibleStart + startO, visibleEnd + startO + 1);
        for (final v in ve) if (v != null) { if (v > vMaxY) vMaxY = v; if (v < vMinY) vMinY = v; }
      }
    }

    final pad = (vMaxY - vMinY) * 0.1;
    final yR = vMaxY - vMinY + pad * 2;
    final adjMinY = vMinY - pad + (yR * _chartPanOffsetY * 0.5);
    final adjMaxY = vMaxY + pad + (yR * _chartPanOffsetY * 0.5);
    final xInt = _calculateXLabelInterval(visibleCandles.length);
    final originalStart = (visibleStart + startO).clamp(0, candles.length);
    final originalEnd = (visibleEnd + startO + 1).clamp(originalStart, candles.length);
    final spots = display.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.close)).toList();
    final isPos = display.last.close >= display.first.close;
    final color = isPos ? AppColors.rise : AppColors.fall;
    final lineBars = [LineChartBarData(spots: spots, isCurved: true, curveSmoothness: 0.2, color: color, barWidth: 2, isStrokeCapRound: true, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: color.withAlpha(30)))];
    if (_showBB) {
      final bb = TechnicalIndicators.calculateBollingerBands(candles.map((c) => c.close).toList(), period: _bbPeriod, stdDev1: _bbStdDev1, stdDev2: _bbStdDev2);
      lineBars.add(_createIndicatorLine(bb.middle.sublist(startO), display.length, Colors.pink.shade700.withOpacity(0.6), 1.0));
      lineBars.add(_createIndicatorLine(bb.upper1.sublist(startO), display.length, Colors.purple.withOpacity(0.6), 0.75));
      lineBars.add(_createIndicatorLine(bb.lower1.sublist(startO), display.length, Colors.purple.withOpacity(0.6), 0.75));
      lineBars.add(_createIndicatorLine(bb.upper2.sublist(startO), display.length, Colors.pink.withOpacity(0.6), 0.75));
      lineBars.add(_createIndicatorLine(bb.lower2.sublist(startO), display.length, Colors.pink.withOpacity(0.6), 0.75));
    }
    if (_showEMA) {
      final prices = candles.map((c) => c.close).toList();
      lineBars.add(_createIndicatorLine(TechnicalIndicators.calculateEMA(prices, _emaPeriod1).sublist(startO), display.length, AppColors.emaShort, 1.2));
      lineBars.add(_createIndicatorLine(TechnicalIndicators.calculateEMA(prices, _emaPeriod2).sublist(startO), display.length, AppColors.emaMedium, 1.2));
      lineBars.add(_createIndicatorLine(TechnicalIndicators.calculateEMA(prices, _emaPeriod3).sublist(startO), display.length, AppColors.emaLong, 1.2));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, right: 8),
      child: Column(children: [
        Expanded(flex: 3, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _buildInteractiveChartWrapper(chartHeight: double.infinity, visibleCandles: visibleCandles, visibleStartIdx: visibleStart, child: LayoutBuilder(builder: (c, cs) => Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.chartGrid, width: 1.2),
            ),
          ),
          child: Stack(children: [
            CustomPaint(size: Size(cs.maxWidth, cs.maxHeight), painter: ChartGridPainter(dataLength: visibleCandles.length, xLabelInterval: xInt, minY: adjMinY, maxY: adjMaxY, startIndex: visibleStart, latestPrice: _candles.isNotEmpty ? _candles.last.close : null, touchedPrice: _touchedPrice, touchedDateTime: _touchedDateTime, candles: visibleCandles)),
            LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), minX: pan, maxX: pan + visible - 1, minY: adjMinY, maxY: adjMaxY, lineBarsData: lineBars, clipData: const FlClipData.all(), lineTouchData: const LineTouchData(enabled: false))),
          ]),
        )))),
        _buildYAxisLabels(adjMinY, adjMaxY),
      ])),
      if (_hasActiveOscillator) Flexible(flex: 1, child: ScrollConfiguration(behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false), child: SingleChildScrollView(child: _buildOscillatorPanels(candles, originalStart, originalEnd, xInt, visibleStart)))),
      Row(children: [
        Expanded(child: _buildXAxisLabels(visibleCandles, xInt, visibleStart)),
        const SizedBox(width: 55),
      ]),
      if (_showCrosshair && _crosshairIndex != null && _crosshairIndex! < visibleCandles.length) _buildCrosshairInfo(visibleCandles[_crosshairIndex!]),
    ]));
  }

  Widget _buildCandlestickChart(List<Candle> candles) {
    int maxP = 0; if (_showBB) maxP = math.max(maxP, _bbPeriod); if (_showEMA) maxP = math.max(maxP, math.max(_emaPeriod1, math.max(_emaPeriod2, _emaPeriod3)));
    final int startO = (maxP > 0) ? maxP - 1 : 0;
    final display = (startO > 0 && candles.length > startO) ? candles.sublist(startO) : candles;
    if (display.isEmpty) return const Center(child: Text('データ不足'));
    final total = display.length.toDouble();
    final visible = (_getBaseVisibleDataPoints() / _chartZoom).clamp(1.0, total).round();
    final maxPan = (display.length - visible).clamp(0, display.length);
    final pan = (_chartPanOffsetX * maxPan).round().clamp(0, maxPan);
    final visibleStart = pan.clamp(0, display.length - 1);
    final visibleEnd = (pan + visible).clamp(visibleStart + 1, display.length);
    final visibleCandles = display.sublist(visibleStart, visibleEnd);
    double vMinY = visibleCandles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    double vMaxY = visibleCandles.map((c) => c.high).reduce((a, b) => a > b ? a : b);

    final originalStart = (visibleStart + startO).clamp(0, candles.length);
    final originalEnd = (visibleEnd + startO).clamp(originalStart, candles.length);
    BollingerBandsResult? vBB; List<List<double?>>? vEMA;

    if (_showBB) {
      final bb = TechnicalIndicators.calculateBollingerBands(candles.map((c) => c.close).toList(), period: _bbPeriod, stdDev1: _bbStdDev1, stdDev2: _bbStdDev2);
      vBB = BollingerBandsResult(middle: _safeSublist(bb.middle, originalStart, originalEnd), upper1: _safeSublist(bb.upper1, originalStart, originalEnd), lower1: _safeSublist(bb.lower1, originalStart, originalEnd), upper2: _safeSublist(bb.upper2, originalStart, originalEnd), lower2: _safeSublist(bb.lower2, originalStart, originalEnd));
      for (final v in vBB.upper2) if (v != null && v > vMaxY) vMaxY = v;
      for (final v in vBB.lower2) if (v != null && v < vMinY) vMinY = v;
    }
    if (_showEMA) {
      final prices = candles.map((c) => c.close).toList();
      vEMA = [_safeSublist(TechnicalIndicators.calculateEMA(prices, _emaPeriod1), originalStart, originalEnd), _safeSublist(TechnicalIndicators.calculateEMA(prices, _emaPeriod2), originalStart, originalEnd), _safeSublist(TechnicalIndicators.calculateEMA(prices, _emaPeriod3), originalStart, originalEnd)];
      for (final e in vEMA) for (final v in e) if (v != null) { if (v > vMaxY) vMaxY = v; if (v < vMinY) vMinY = v; }
    }

    final pad = (vMaxY - vMinY) * 0.1;
    final yR = vMaxY - vMinY + pad * 2;
    final adjMinY = vMinY - pad + (yR * _chartPanOffsetY * 0.5);
    final adjMaxY = vMaxY + pad + (yR * _chartPanOffsetY * 0.5);
    final xInt = _calculateXLabelInterval(visibleCandles.length);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, right: 8),
      child: Column(children: [
        Expanded(flex: 3, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _buildInteractiveChartWrapper(chartHeight: double.infinity, visibleCandles: visibleCandles, visibleStartIdx: visibleStart, child: LayoutBuilder(builder: (c, cs) => Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.chartGrid, width: 1.2),
            ),
          ),
          child: Stack(children: [
            CustomPaint(size: Size(cs.maxWidth, cs.maxHeight), painter: ChartGridPainter(dataLength: visibleCandles.length, xLabelInterval: xInt, minY: adjMinY, maxY: adjMaxY, startIndex: visibleStart, latestPrice: _candles.isNotEmpty ? _candles.last.close : null, touchedPrice: _touchedPrice, touchedDateTime: _touchedDateTime, candles: visibleCandles)),
            CustomPaint(size: Size(cs.maxWidth, cs.maxHeight), painter: CandlestickPainter(candles: visibleCandles, minY: adjMinY, maxY: adjMaxY, bb: vBB, emaLines: vEMA, startIndex: visibleStart, xLabelInterval: xInt, indicatorStartIndex: 0)),
          ]),
        )))),
        _buildYAxisLabels(adjMinY, adjMaxY),
      ])),
      if (_hasActiveOscillator) Flexible(flex: 1, child: ScrollConfiguration(behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false), child: SingleChildScrollView(child: _buildOscillatorPanels(candles, originalStart, originalEnd, xInt, visibleStart)))),
      Row(children: [
        Expanded(child: _buildXAxisLabels(visibleCandles, xInt, visibleStart)),
        const SizedBox(width: 55),
      ]),
      if (_showCrosshair && _crosshairIndex != null && _crosshairIndex! < visibleCandles.length) _buildCrosshairInfo(visibleCandles[_crosshairIndex!]),
    ]));
  }

  Widget _buildInteractiveChartWrapper({required double chartHeight, required List<Candle> visibleCandles, required int visibleStartIdx, required Widget child}) {
    return Listener(
      onPointerDown: (event) {
        final x = event.localPosition.dx;
        final w = MediaQuery.of(context).size.width - 120;
        if (visibleCandles.isNotEmpty && w > 0) {
          final int idx = (x / (w / visibleCandles.length)).floor().clamp(0, visibleCandles.length - 1);
          setState(() {
            _touchedDateTime = visibleCandles[idx].date;
          });
        }
      },
      onPointerMove: (event) {
        final x = event.localPosition.dx;
        final w = MediaQuery.of(context).size.width - 120;
        if (visibleCandles.isNotEmpty && w > 0) {
          final int idx = (x / (w / visibleCandles.length)).floor().clamp(0, visibleCandles.length - 1);
          setState(() {
            _touchedDateTime = visibleCandles[idx].date;
          });
        }
      },
      child: GestureDetector(
        onVerticalDragStart: (d) {},
        onScaleStart: (d) { _scrollAnimationController.stop(); _lastScaleStart = _chartZoom; _lastFocalPoint = d.focalPoint; },
        onScaleUpdate: (d) {
          setState(() {
            if (_lastScaleStart != null && d.scale != 1.0) _chartZoom = (_lastScaleStart! * d.scale).clamp(_minZoom, _maxZoom);
            if (d.scale == 1.0 && _lastFocalPoint != null) {
              final double dx = d.focalPoint.dx - _lastFocalPoint!.dx;
              final double dy = d.focalPoint.dy - _lastFocalPoint!.dy;
              final double w = MediaQuery.of(context).size.width - 120;
              if (w > 0) { _chartPanOffsetX = (_chartPanOffsetX - (dx / w) / _chartZoom).clamp(0.0, 1.0); _scrollVelocity = -(dx / w) / _chartZoom; }
              // 縦方向のスクロール感度と範囲を向上
              _chartPanOffsetY = (_chartPanOffsetY + (dy / 150 / _chartZoom)).clamp(-10.0, 10.0);
            }
            _lastFocalPoint = d.focalPoint;
          });
        },
        onScaleEnd: (d) { _lastScaleStart = null; _lastFocalPoint = null; if (_scrollVelocity.abs() > 0.001) _scrollAnimationController.repeat(); },
        onDoubleTap: () { _scrollAnimationController.stop(); setState(() { if (_chartZoom < 2.0) _chartZoom = 3.0; else { _chartZoom = 1.0; _chartPanOffsetX = 1.0; _chartPanOffsetY = 0.0; } }); },
        onLongPressStart: (d) { _scrollAnimationController.stop(); _updateCrosshair(d.localPosition, visibleCandles, chartHeight); },
        onLongPressMoveUpdate: (d) => _updateCrosshair(d.localPosition, visibleCandles, chartHeight),
        onLongPressEnd: (d) => setState(() { _showCrosshair = false; _crosshairPosition = null; _crosshairIndex = null; }),
        child: SizedBox(height: chartHeight, child: ClipRect(child: RepaintBoundary(child: Container(decoration: const BoxDecoration(color: AppColors.chartBackground), child: Stack(children: [
          child, if (_showCrosshair && _crosshairPosition != null) Positioned.fill(child: CustomPaint(painter: CrosshairPainter(position: _crosshairPosition!, color: AppColors.axisLabel.withOpacity(0.7)))),
        ]))))),
      ),
    );
  }

  void _updateCrosshair(Offset p, List<Candle> c, double h) {
    if (c.isEmpty) return;
    final w = MediaQuery.of(context).size.width - 120;
    final i = ((p.dx / w) * c.length).floor().clamp(0, c.length - 1);
    setState(() { _showCrosshair = true; _crosshairPosition = p; _crosshairIndex = i; });
  }

  Widget _buildCrosshairInfo(Candle c) {
    return Container(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      _buildInfoItem('日付', DateFormat('MM/dd').format(c.date)), _buildInfoItem('始値', _formatPriceWithCurrency(c.open)), _buildInfoItem('高値', _formatPriceWithCurrency(c.high)), _buildInfoItem('安値', _formatPriceWithCurrency(c.low)), _buildInfoItem('終値', _formatPriceWithCurrency(c.close)),
    ]));
  }

  Widget _buildInfoItem(String l, String v) => Column(mainAxisSize: MainAxisSize.min, children: [Text(l, style: const TextStyle(color: Colors.grey, fontSize: 10)), Text(v, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))]);

  Widget _buildRightToolbar() {
    return Container(
      width: 60,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE0E0E0), width: 1.0)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildToolbarButton(icon: Icons.tune, onPressed: _showIndicatorSettings, isActive: _activeIndicatorCount > 0),
          _buildToolbarButton(icon: Icons.bar_chart, onPressed: _showChartTypeSettings),
          _buildToolbarButton(
            icon: Icons.note_alt_outlined,
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemoScreen(symbol: widget.symbol)));
              _loadMemoCount();
            },
            badgeCount: _memoCount,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F3F5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFD0D0D0)),
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _chartZoom = (_chartZoom + 0.5).clamp(_minZoom, _maxZoom)),
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFD0D0D0)))),
                        child: const Icon(Icons.add, color: Color(0xFF444444), size: 24),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 46,
                              activeTrackColor: const Color(0xFF00B5AD),
                              inactiveTrackColor: const Color(0xFF1E222D),
                              thumbShape: SliderComponentShape.noThumb,
                              overlayShape: SliderComponentShape.noOverlay,
                              trackShape: const RectangularSliderTrackShape(),
                            ),
                            child: Slider(
                              value: _chartZoom,
                              min: _minZoom,
                              max: _maxZoom,
                              onChanged: (v) => setState(() => _chartZoom = v),
                            ),
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _chartZoom = (_chartZoom - 0.5).clamp(_minZoom, _maxZoom)),
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFD0D0D0)))),
                        child: const Icon(Icons.remove, color: Color(0xFF444444), size: 24),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildToolbarButton(icon: Icons.restart_alt, onPressed: () => setState(() { _chartZoom = 1.0; _chartPanOffsetX = 1.0; _chartPanOffsetY = 0.0; })),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({required IconData icon, required VoidCallback onPressed, bool isActive = false, int? badgeCount}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3F5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFD0D0D0)),
            ),
            child: Icon(icon, size: 26, color: isActive ? AppColors.primary : const Color(0xFF333333)),
          ),
          if (badgeCount != null && badgeCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  badgeCount > 99 ? '99+' : badgeCount.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  LineChartBarData _createIndicatorLine(List<double?> data, int length, Color color, double width) {
    final spots = <FlSpot>[];
    for (int i = 0; i < length; i++) if (data[i] != null) spots.add(FlSpot(i.toDouble(), data[i]!));
    return LineChartBarData(spots: spots, isCurved: true, curveSmoothness: 0.2, color: color, barWidth: width, isStrokeCapRound: true, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: false));
  }

  bool get _hasActiveOscillator => _showRSI || _showMACD || _showStochastic || _showCCI;
  List<T> _safeSublist<T>(List<T> list, int s, int e) { final se = e.clamp(0, list.length); final ss = s.clamp(0, se); return list.sublist(ss, se); }

  Widget _buildOscillatorPanels(List<Candle> candles, int visibleStartIdx, int visibleEndIdx, int xInt, int panelStartIndex) {
    final prices = candles.map((c) => c.close).toList();
    final panels = <Widget>[];
    final visibleCandlesSubset = _safeSublist(candles, visibleStartIdx, visibleEndIdx);

    if (_showRSI) {
      final rsi = OscillatorIndicators.calculateRSI(prices, period: _rsiPeriod);
      final v = _safeSublist(rsi.values, visibleStartIdx, visibleEndIdx);
      if (v.isNotEmpty) panels.add(_buildSingleOscillatorPanel(title: 'RSI($_rsiPeriod)', values: v, minY: 0, maxY: 100, lineColor: AppColors.rsiLine, oscillatorType: 'rsi', startIndex: panelStartIndex, xLabelInterval: xInt, visibleCandles: visibleCandlesSubset));
    }
    if (_showMACD) {
      final m = OscillatorIndicators.calculateMACD(prices, fastPeriod: _macdFast, slowPeriod: _macdSlow, signalPeriod: _macdSignal);
      final vm = _safeSublist(m.macdLine, visibleStartIdx, visibleEndIdx);
      final vs = _safeSublist(m.signalLine, visibleStartIdx, visibleEndIdx);
      final vh = _safeSublist(m.histogram, visibleStartIdx, visibleEndIdx);
      if (vm.isNotEmpty) {
        double mn = 0, mx = 0; for (final x in vm) if (x != null) { mn = math.min(mn, x); mx = math.max(mx, x); }
        for (final x in vs) if (x != null) { mn = math.min(mn, x); mx = math.max(mx, x); }
        final p = (mx - mn) * 0.1;
        panels.add(_buildSingleOscillatorPanel(title: 'MACD', values: vm, minY: mn - p, maxY: mx + p, lineColor: AppColors.macdLine, oscillatorType: 'macd', signalLine: vs, histogram: vh, startIndex: panelStartIndex, xLabelInterval: xInt, visibleCandles: visibleCandlesSubset));
      }
    }
    if (_showStochastic) {
      final s = OscillatorIndicators.calculateStochastic(candles, kPeriod: _stochKPeriod, dPeriod: _stochDPeriod, smooth: _stochSmooth);
      final vk = _safeSublist(s.percentK, visibleStartIdx, visibleEndIdx);
      final vd = _safeSublist(s.percentD, visibleStartIdx, visibleEndIdx);
      if (vk.isNotEmpty) panels.add(_buildSingleOscillatorPanel(title: 'Stoch', values: vk, minY: 0, maxY: 100, lineColor: AppColors.stochK, oscillatorType: 'stochastic', signalLine: vd, startIndex: panelStartIndex, xLabelInterval: xInt, visibleCandles: visibleCandlesSubset));
    }
    if (_showCCI) {
      final c = OscillatorIndicators.calculateCCI(candles, period: _cciPeriod);
      final vc = _safeSublist(c.values, visibleStartIdx, visibleEndIdx);
      if (vc.isNotEmpty) {
        double mn = -100, mx = 100; for (final x in vc) if (x != null) { mn = math.min(mn, x); mx = math.max(mx, x); }
        final p = (mx - mn) * 0.1;
        panels.add(_buildSingleOscillatorPanel(title: 'CCI', values: vc, minY: mn - p, maxY: mx + p, lineColor: AppColors.cciLine, oscillatorType: 'cci', startIndex: panelStartIndex, xLabelInterval: xInt, visibleCandles: visibleCandlesSubset));
      }
    }
    return Column(children: panels);
  }

  Widget _buildSingleOscillatorPanel({required String title, required List<double?> values, required double minY, required double maxY, required Color lineColor, required String oscillatorType, List<double?> signalLine = const [], List<double?> histogram = const [], required int startIndex, required int xLabelInterval, required List<Candle> visibleCandles}) {
    const double h = 140.0;
    
    // オシレーターごとの固定目盛り設定
    List<double>? fixedLevels;
    if (oscillatorType == 'rsi') fixedLevels = [70, 50, 30];
    else if (oscillatorType == 'macd') fixedLevels = [0];
    else if (oscillatorType == 'stochastic') fixedLevels = [80, 50, 20];
    else if (oscillatorType == 'cci') fixedLevels = [100, 0, -100];

    return SizedBox(
      height: h,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.chartGrid, width: 1.2),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: OscillatorPainter(
                        values: values, minY: minY, maxY: maxY, lineColor: lineColor, oscillatorType: oscillatorType, signalLine: signalLine, histogram: histogram, startIndex: startIndex, xLabelInterval: xLabelInterval,
                        touchedLevel: _touchedIndicatorLevels[oscillatorType],
                        touchedDateTime: _touchedDateTime,
                        candles: visibleCandles,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4, left: 4,
                    child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: lineColor.withOpacity(0.9), backgroundColor: AppColors.chartBackground.withOpacity(0.5))),
                  ),
                ],
              ),
            ),
          ),
          _buildYAxisLabels(minY, maxY, fixedLevels: fixedLevels, oscillatorType: oscillatorType),
        ],
      ),
    );
  }

  double _calculatePriceStep(double r) {
    if (r <= 0) return 1.0;
    double s = r / 12; double e = (math.log(s) / math.ln10).floorToDouble(); double m = math.pow(10, e).toDouble(); double rs = s / m;
    if (rs < 1.5) return 1.0 * m; if (rs < 3.0) return 2.0 * m; if (rs < 7.0) return 5.0 * m; return 10.0 * m;
  }

  int _calculateXLabelInterval(int d) {
    int interval;
    if (d <= 15) interval = 2;
    else if (d <= 40) interval = 5;
    else if (d <= 80) interval = 10;
    else if (d <= 150) interval = 20;
    else if (d <= 300) interval = 40;
    else interval = (d / 6).ceil();
    
    // 描画間隔を0.95倍にする（より細かく表示する）
    return (interval * 0.95).round().clamp(1, d);
  }

  int _getBaseVisibleDataPoints() => 100;

  Widget _buildYAxisLabels(double minY, double maxY, {List<double>? fixedLevels, String? oscillatorType}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final currentTouchedValue = oscillatorType != null 
            ? _touchedIndicatorLevels[oscillatorType] 
            : _touchedPrice;

        return Listener(
          onPointerDown: (event) {
            final y = event.localPosition.dy;
            final range = maxY - minY;
            final value = maxY - (y / constraints.maxHeight) * range;
            setState(() {
              if (oscillatorType != null) {
                _touchedIndicatorLevels[oscillatorType] = value;
              } else {
                _touchedPrice = value;
              }
            });
          },
          onPointerMove: (event) {
            final y = event.localPosition.dy;
            final range = maxY - minY;
            final value = maxY - (y / constraints.maxHeight) * range;
            setState(() {
              if (oscillatorType != null) {
                _touchedIndicatorLevels[oscillatorType] = value;
              } else {
                _touchedPrice = value;
              }
            });
          },
          child: Container(
            width: 55,
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.chartGrid, width: 1.2),
              ),
            ),
            child: CustomPaint(
              painter: YAxisLabelPainter(
                minY: minY, 
                maxY: maxY, 
                latestPrice: oscillatorType == null && _candles.isNotEmpty ? _candles.last.close : null,
                touchedPrice: currentTouchedValue,
                fixedLevels: fixedLevels,
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildXAxisLabels(List<Candle> vc, int interval, int startIndex) {
    if (vc.isEmpty) return const SizedBox();
    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          onPointerDown: (event) {
            final x = event.localPosition.dx;
            final double cw = constraints.maxWidth / vc.length;
            final int idx = (x / cw).floor().clamp(0, vc.length - 1);
            setState(() => _touchedDateTime = vc[idx].date);
          },
          onPointerMove: (event) {
            final x = event.localPosition.dx;
            final double cw = constraints.maxWidth / vc.length;
            final int idx = (x / cw).floor().clamp(0, vc.length - 1);
            setState(() => _touchedDateTime = vc[idx].date);
          },
          child: SizedBox(
            height: 25, 
            width: double.infinity, 
            child: CustomPaint(
              painter: XAxisLabelPainter(
                visibleCandles: vc, 
                interval: interval, 
                startIndex: startIndex, 
                intervalType: _interval,
                touchedDateTime: _touchedDateTime,
              )
            )
          ),
        );
      }
    );
  }

  String _formatPriceWithCurrency(double p) {
    if (widget.category == MarketCategory.forex) {
      final s = widget.symbol.replaceAll('=X', '');
      final q = s.endsWith('JPY') ? '¥' : (s.endsWith('USD') ? '\$' : (s.endsWith('EUR') ? '€' : (s.endsWith('GBP') ? '£' : '\$')));
      return '$q${_formatPrice(p)}';
    }
    if (widget.category == MarketCategory.stock && widget.symbol.endsWith('.T')) return '¥${_formatPrice(p)}';
    final cp = _showJPY ? p * _usdJpyRate : p;
    return '${_showJPY ? '¥' : '\$'}${_formatPrice(cp)}';
  }
  String _formatPrice(double p) => NumberFormat('#,##0').format(p.round());

  Widget _buildFooter() {
    return Container(
      height: 100, 
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface, 
        border: Border(top: BorderSide(color: AppColors.divider, width: 1.0))
      ),
      child: Row(
        children: [
          _buildFooterItem(icon: Icons.grid_view, label: 'ホーム', badge: '18', onTap: () => Navigator.of(context).popUntil((r) => r.isFirst)),
          _buildFooterItem(
            icon: Icons.stacked_line_chart, 
            label: 'チャート', 
            isSelected: true,
            onTap: () {
              setState(() {
                _isMaximizedChart = !_isMaximizedChart;
              });
            },
          ),
          _buildFooterItem(icon: Icons.category_outlined, label: 'カテゴリー', onTap: _showCategorySettings),
        ],
      ),
    );
  }

  void _showCategorySettings() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.category_outlined, color: AppColors.primaryLight, size: 20),
                  SizedBox(width: 8),
                  Text('カテゴリー選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              const SizedBox(height: 32),
              Column(
                children: MarketCategory.values.map((cat) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pop(); // モーダルを閉じる
                      Navigator.of(context).pop(cat); // ホーム画面に戻りつつカテゴリを渡す
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        color: widget.category == cat ? AppColors.primary.withAlpha(40) : Colors.white.withAlpha(10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.category == cat ? AppColors.primaryLight : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(cat.icon, color: widget.category == cat ? Colors.white : AppColors.textSecondary, size: 24),
                          const SizedBox(width: 16),
                          Text(
                            cat.label,
                            style: TextStyle(
                              color: widget.category == cat ? Colors.white : AppColors.textSecondary,
                              fontWeight: widget.category == cat ? FontWeight.bold : FontWeight.normal,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          if (widget.category == cat)
                            const Icon(Icons.check_circle, color: AppColors.primaryLight, size: 20),
                        ],
                      ),
                    ),
                  ),
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterItem({required IconData icon, required String label, bool isSelected = false, String? badge, VoidCallback? onTap}) {
    final color = isSelected ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 28),
                if (badge != null)
                  Positioned(
                    right: -8, top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.surface, width: 1.5)),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

class _IndicatorConfig {
  final String key, name, fullName, description; final Color color; final IconData icon;
  _IndicatorConfig({required this.key, required this.name, required this.fullName, required this.description, required this.color, required this.icon});
}


class OscillatorYAxisLabelPainter extends CustomPainter {
  final double minY, maxY; final String oscillatorType;
  OscillatorYAxisLabelPainter({required this.minY, required this.maxY, required this.oscillatorType});
  @override
  void paint(Canvas cv, ui.Size s) {
    final vr = maxY - minY; if (vr <= 0) return;
    final levels = <double>[];
    switch (oscillatorType) {
      case 'rsi': levels.addAll([70, 50, 30]); break;
      case 'macd': levels.add(0); break;
      case 'stochastic': levels.addAll([80, 50, 20]); break;
      case 'cci': levels.addAll([100, 0, -100]); break;
    }
    final ts = TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.bold);
    for (final l in levels) {
      final double y = s.height - ((l - minY) / vr * s.height);
      if (y >= 0 && y <= s.height) {
        TextPainter(text: TextSpan(text: l.toStringAsFixed(0), style: ts), textDirection: ui.TextDirection.ltr, textAlign: TextAlign.left)..layout()..paint(cv, Offset(8, y - 6));
      }
    }
  }
  @override bool shouldRepaint(covariant OscillatorYAxisLabelPainter old) => old.minY != minY || old.maxY != maxY || old.oscillatorType != oscillatorType;
}

class _IndicatorSettingsSheet extends StatefulWidget {
  final Map<String, IndicatorSettings> indicators; final Function(String, IndicatorSettings) onChanged; final Function(String, bool) onToggle;
  const _IndicatorSettingsSheet({required this.indicators, required this.onChanged, required this.onToggle});
  @override State<_IndicatorSettingsSheet> createState() => _IndicatorSettingsSheetState();
}
class _IndicatorSettingsSheetState extends State<_IndicatorSettingsSheet> {
  late Map<String, IndicatorSettings> _local;
  @override void initState() { super.initState(); _local = {}; widget.indicators.forEach((k, v) => _local[k] = v.copyWith()); }
  @override Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85, maxWidth: 500),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('インジケーター設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                TextButton(
                  onPressed: () => setState(() { for (final k in _local.keys) { _local[k]!.enabled = false; widget.onToggle(k, false); } }),
                  child: Text('すべてオフ', style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Flexible(
            child: SingleChildScrollView(
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    _buildSectionHeader('トレンド系', 'チャート上に表示', Icons.show_chart, AppColors.primary),
                    ..._IndicatorSettingsSheetState._trend.map((c) => _buildIndicatorTile(c)),
                    const SizedBox(height: 16),
                    _buildSectionHeader('オシレーター系', 'サブチャートに表示', Icons.ssid_chart, AppColors.rsiLine),
                    ..._IndicatorSettingsSheetState._osc.map((c) => _buildIndicatorTile(c)),
                    const SizedBox(height: 40), // 十分な下部パディング
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildSectionHeader(String t, String s, IconData i, Color c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: BoxDecoration(color: c.withAlpha(20)),
    child: Row(
      children: [
        Icon(i, color: c, size: 22),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c)),
            Text(s, style: TextStyle(fontSize: 11, color: c.withAlpha(180))),
          ],
        )
      ],
    ),
  );
  Widget _buildIndicatorTile(_IndicatorConfig config) {
    final s = _local[config.key]; final isE = s?.enabled ?? false;
    final isOsc = _IndicatorSettingsSheetState._osc.any((c) => c.key == config.key);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isE ? config.color.withAlpha(15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isE ? config.color.withAlpha(50) : Colors.transparent),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: config.color.withAlpha(30), borderRadius: BorderRadius.circular(10)),
          child: Icon(config.icon, color: config.color, size: 24),
        ),
        title: Text(config.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
        subtitle: Text(config.fullName, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: Switch(
          value: isE,
          activeTrackColor: config.color.withAlpha(100),
          activeThumbColor: config.color,
          onChanged: (v) {
            setState(() {
              if (v && isOsc) {
                for (final c in _IndicatorSettingsSheetState._osc) {
                  _local[c.key]?.enabled = false;
                  if (c.key != config.key) widget.onToggle(c.key, false);
                }
              }
              _local[config.key]!.enabled = v;
            });
            widget.onToggle(config.key, v);
          },
        ),
        onTap: () {
          final nv = !isE;
          setState(() {
            if (nv && isOsc) {
              for (final c in _IndicatorSettingsSheetState._osc) {
                _local[c.key]?.enabled = false;
                if (c.key != config.key) widget.onToggle(c.key, false);
              }
            }
            _local[config.key]!.enabled = nv;
          });
          widget.onToggle(config.key, nv);
        },
      ),
    );
  }
  static final _trend = [_IndicatorConfig(key: 'bb', name: 'BB', fullName: 'ボリンジャーバンド', description: '価格の変動範囲', color: Colors.blue, icon: Icons.stacked_line_chart), _IndicatorConfig(key: 'ema', name: 'EMA', fullName: '指数移動平均線', description: '3本の移動平均', color: Colors.orange, icon: Icons.show_chart)];
  static final _osc = [_IndicatorConfig(key: 'rsi', name: 'RSI', fullName: '相対力指数', description: '買われすぎ/売られすぎ', color: AppColors.rsiLine, icon: Icons.trending_up), _IndicatorConfig(key: 'macd', name: 'MACD', fullName: '移動平均収束拡散', description: 'トレンドの勢い', color: AppColors.macdLine, icon: Icons.bar_chart), _IndicatorConfig(key: 'stochastic', name: 'Stoch', fullName: 'ストキャスティクス', description: '逆張りの指標', color: AppColors.stochK, icon: Icons.ssid_chart), _IndicatorConfig(key: 'cci', name: 'CCI', fullName: '商品チャンネル指数', description: '平均価格からの乖離', color: AppColors.cciLine, icon: Icons.multiline_chart)];
}

class _CrossSettingsSheet extends StatefulWidget {
  final String symbol, interval; final List<CrossEvent> crossHistory; final double? threshold; final bool emailNotificationEnabled; final double? currentPrice; final Function(double?) onThresholdChanged; final Function(bool) onEmailNotificationChanged; final VoidCallback onClearHistory;
  const _CrossSettingsSheet({required this.symbol, required this.interval, required this.crossHistory, required this.threshold, required this.emailNotificationEnabled, required this.currentPrice, required this.onThresholdChanged, required this.onEmailNotificationChanged, required this.onClearHistory});
  @override State<_CrossSettingsSheet> createState() => _CrossSettingsSheetState();
}
class _CrossSettingsSheetState extends State<_CrossSettingsSheet> {
  final ChartService _cs = ChartService(); late TextEditingController _tc, _ec; late bool _ee; List<String> _emails = []; bool _le = false;
  @override void initState() { super.initState(); _tc = TextEditingController(text: widget.threshold?.toStringAsFixed(2) ?? ''); _ec = TextEditingController(); _ee = widget.emailNotificationEnabled; _load(); }
  @override void dispose() { _tc.dispose(); _ec.dispose(); super.dispose(); }
  Future<void> _load() async { setState(() => _le = true); final es = await _cs.getEmails(symbol: widget.symbol); if (mounted) setState(() { _emails = es; _le = false; }); }

  Future<bool> _showConfirm({required String title, required String message, Color? confirmColor}) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor ?? AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('実行', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _showEmailContentDialog(CrossEvent e) async {
    final isUp = e.direction == CrossDirection.up;
    final directionText = isUp ? '上抜け' : '下抜け';
    final subject = '【Parabolic】${e.symbol} シグナル検知 (${e.displayName} $directionText)';
    final body = '''
${e.symbol} においてテクニカル指標のシグナルを検知しました。

■銘柄: ${e.symbol}
■時間足: ${e.interval}
■指標: ${e.displayName}
■方向（交差）: $directionText
■検知時価格: ${e.price.toStringAsFixed(e.symbol.contains('JPY') ? 1 : 4)}
■検知時刻: ${DateFormat('yyyy/MM/dd HH:mm:ss').format(e.timestamp)}

${e.displayName} のラインを価格が【$directionText】しました。
設定された閾値（${widget.threshold?.toStringAsFixed(2) ?? '未設定'}）に基づき、この価格から指定以上の変動があった場合に再度メール通知が行われます。
''';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            const Icon(Icons.mark_email_unread_outlined, color: AppColors.primaryLight),
            const SizedBox(width: 12),
            const Text('通知メール内容', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('SUBJECT:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text(subject, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Colors.white10),
              ),
              const Text('BODY:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withAlpha(10)),
                ),
                child: Text(
                  body,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる', style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85, maxWidth: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
                    child: Row(
                      children: [
                        const Text('通知・閾値設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (await _showConfirm(title: '閾値クリア', message: '登録されている閾値を削除しますか？', confirmColor: AppColors.rise)) {
                                widget.onThresholdChanged(null);
                                _tc.clear();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                                          const SizedBox(width: 12),
                                          const Text('閾値をクリアしました', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                        ],
                                      ),
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: AppColors.rise.withOpacity(0.9),
                                      elevation: 8,
                                      margin: const EdgeInsets.all(20),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(color: Colors.white.withAlpha(40), width: 1),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('閾値削除', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.rise,
                              foregroundColor: Colors.white,
                              elevation: 4,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      children: [
                        _buildSectionLabel('アラート閾値設定'),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withAlpha(20)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'クロス検知時の価格から指定した変動幅（閾値）以上の動きがあった場合に通知します',
                                style: TextStyle(color: AppColors.textSecondary.withOpacity(0.9), fontSize: 13, height: 1.5),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _tc,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        labelText: 'ターゲット変動幅',
                                        labelStyle: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                                        hintText: widget.symbol.endsWith('JPY') || widget.symbol.endsWith('.T') ? '例: 500' : '例: 1.50',
                                        hintStyle: const TextStyle(color: Colors.white24),
                                        prefixIcon: const Icon(Icons.notifications_active, color: AppColors.warning),
                                        suffixText: widget.symbol.endsWith('JPY') || widget.symbol.endsWith('.T') ? '円' : 'USD',
                                        suffixStyle: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                                        filled: true,
                                        fillColor: Colors.black38,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                                      ),
                                      onSubmitted: (v) => widget.onThresholdChanged(double.tryParse(v)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    height: 64,
                                    child: ElevatedButton(
                                      onPressed: () async {
                                        if (await _showConfirm(title: '閾値更新', message: '通知する価格変動幅を更新しますか？')) {
                                          widget.onThresholdChanged(double.tryParse(_tc.text));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                                                  const SizedBox(width: 12),
                                                  const Text('閾値を更新しました', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                                ],
                                              ),
                                              duration: const Duration(seconds: 2),
                                              behavior: SnackBarBehavior.floating,
                                              backgroundColor: AppColors.success.withOpacity(0.9),
                                              elevation: 8,
                                              margin: const EdgeInsets.all(20),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                side: BorderSide(color: Colors.white.withAlpha(40), width: 1),
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(horizontal: 24),
                                        elevation: 4,
                                      ),
                                      child: const Text('更新', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        _buildSectionLabel('メール通知・テスト送信'),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withAlpha(20)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('メール通知', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                      Text('シグナル検知を即座にメールでお知らせ', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                    ],
                                  ),
                                  Switch.adaptive(
                                    value: _ee,
                                    activeColor: AppColors.success,
                                    activeTrackColor: AppColors.success.withAlpha(100),
                                    onChanged: (v) {
                                      setState(() => _ee = v);
                                      widget.onEmailNotificationChanged(v);
                                    },
                                  ),
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Divider(height: 1, color: Colors.white10),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('設定のテスト', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      if (await _showConfirm(title: 'テスト送信', message: '設定確認用のテストメールを送信しますか？')) {
                                        final success = await _cs.sendTestEmail(symbol: widget.symbol);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(
                                                    success ? Icons.mark_email_read_outlined : Icons.mail_lock_outlined,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    success ? 'テストメールを送信しました' : '送信に失敗しました',
                                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                                  ),
                                                ],
                                              ),
                                              backgroundColor: (success ? AppColors.success : AppColors.error).withOpacity(0.9),
                                              behavior: SnackBarBehavior.floating,
                                              elevation: 8,
                                              margin: const EdgeInsets.all(20),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                side: BorderSide(color: Colors.white.withAlpha(40), width: 1),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.send_rounded, size: 16),
                                    label: const Text('送信テスト', style: TextStyle(fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white.withAlpha(20),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              const Text('配信先アドレスの登録', style: TextStyle(color: AppColors.primaryLight, fontSize: 13, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _ec,
                                      style: const TextStyle(color: Colors.white, fontSize: 15),
                                      decoration: InputDecoration(
                                        hintText: 'example@mail.com',
                                        hintStyle: const TextStyle(color: Colors.white24),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                        filled: true,
                                        fillColor: Colors.black38,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        prefixIcon: const Icon(Icons.alternate_email, color: AppColors.textSecondary, size: 20),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  IconButton.filled(
                                    onPressed: () async {
                                      if (_ec.text.isEmpty) return;
                                      if (await _showConfirm(title: 'アドレス登録', message: 'このメールアドレスを通知先として登録しますか？')) {
                                        final success = await _cs.registerEmail(email: _ec.text, symbol: widget.symbol);
                                        if (success) {
                                          _ec.clear();
                                          _load();
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.add),
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.all(14),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_le)
                                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                              else
                                ..._emails.map((e) => Container(
                                      margin: const EdgeInsets.only(top: 8),
                                      decoration: BoxDecoration(color: Colors.white.withAlpha(5), borderRadius: BorderRadius.circular(8)),
                                      child: ListTile(
                                        dense: true,
                                                                          title: Text(e, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                                                          trailing: Transform.translate(
                                                                            offset: const Offset(8, 0),
                                                                            child: IconButton(
                                                                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 18),
                                                                              onPressed: () async {
                                                                                if (await _showConfirm(title: 'アドレス削除', message: 'このメールアドレスを通知先から削除しますか？', confirmColor: AppColors.rise)) {
                                                                                  final success = await _cs.deleteEmail(email: e, symbol: widget.symbol);
                                                                                  if (success) _load();
                                                                                }
                                                                              },
                                                                              style: IconButton.styleFrom(
                                                                                backgroundColor: AppColors.rise,
                                                                                elevation: 2,
                                                                                padding: const EdgeInsets.all(10),
                                                                                shape: RoundedRectangleBorder(
                                                                                  borderRadius: BorderRadius.circular(8),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          ),                                      ),
                                    )),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildSectionLabel('検知履歴 (${widget.interval})'),
                        if (widget.crossHistory.where((e) => e.interval == widget.interval).isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withAlpha(5)),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.history_toggle_off, color: Colors.white.withAlpha(20), size: 48),
                                const SizedBox(height: 12),
                                const Text('履歴はありません', style: TextStyle(color: Colors.white24, fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        else
                          ...widget.crossHistory.where((e) => e.interval == widget.interval).take(5).map((e) {
                            final isUp = e.direction == CrossDirection.up;
                            final color = isUp ? AppColors.rise : AppColors.fall;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: color.withAlpha(40), width: 1),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  onTap: () => _showEmailContentDialog(e),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        right: -10,
                                        top: -10,
                                        child: Icon(isUp ? Icons.trending_up : Icons.trending_down, color: color.withAlpha(15), size: 80),
                                      ),
                                      ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        leading: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle),
                                          child: Icon(isUp ? Icons.arrow_upward : Icons.arrow_downward, color: color, size: 20),
                                        ),
                                        title: Row(
                                          children: [
                                            Text(e.indicatorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(4)),
                                              child: Text(isUp ? '上昇' : '下落', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            '価格: ${e.price.toStringAsFixed(widget.symbol.contains('JPY') ? 1 : 4)}',
                                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                          ),
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(DateFormat('MM/dd').format(e.timestamp), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                            Text(DateFormat('HH:mm').format(e.timestamp), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 40),
                        const SafeArea(child: SizedBox(height: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white54, size: 20),
                ),
                tooltip: '閉じる',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 12, top: 8),
    child: Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
      ],
    ),
  );
}
