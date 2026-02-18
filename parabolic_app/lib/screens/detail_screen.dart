import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/candle.dart';
import '../models/chart_configs.dart';
import '../providers/auth_provider.dart';
import '../providers/market_data_provider.dart';
import '../services/chart_service.dart';
import '../services/cross_detection_service.dart';
import '../widgets/cross_settings_modal.dart';
import '../services/memo_service.dart';
import '../theme/app_colors.dart';
import '../widgets/financial_chart.dart';
import '../widgets/indicator_settings_sheet.dart';
import '../widgets/detail/chart_timer_widget.dart';
import '../widgets/detail/detail_symbol_header.dart';
import '../widgets/detail/detail_footer.dart';
import 'market_list_screen.dart';
import 'memo_screen.dart';
import 'home_screen.dart';

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

  static const int _refreshIntervalSeconds = 60;
  Timer? _countdownTimer;
  int _secondsUntilRefresh = _refreshIntervalSeconds;
  bool _isRefreshing = false;

  int _memoCount = 0;
  final Set<String> _sentNotifications = {};
  Map<String, double> _allIntervalThresholds = {};
  late final Map<String, IndicatorSettings> _indicators = _getDefaultIndicators();

  final List<String> _intervals = ['5m', '15m', '30m', '1h', '4h', '1d', '1wk', '1mo'];
  List<CrossEvent> _crossHistory = [];
  double? _threshold;
  List<String> _alertTargetIndicators = ['ema']; 
  bool _emailNotificationEnabled = false;
  bool _isMaximizedChart = false;

  @override
  void initState() {
    super.initState();
    _loadIndicatorSettingsFromServer();
    _loadData();
    _loadCrossSettings();
    _loadAllIntervalThresholds();
    _loadMemoCount();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // --- Data Loading & Sync Logic ---

  Future<void> _loadAllIntervalThresholds() async {
    final thresholds = await _chartService.getAllThresholdsFromServer(widget.symbol);
    if (mounted) setState(() => _allIntervalThresholds = thresholds);
  }

  Future<void> _loadMemoCount() async {
    try {
      final memos = await _memoService.getMemos(widget.symbol);
      if (mounted) setState(() => _memoCount = memos.length);
    } catch (e) { debugPrint('Error loading memo count: $e'); }
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
        if (settings['alertTargetIndicators'] != null) {
          _alertTargetIndicators = List<String>.from(settings['alertTargetIndicators']);
        }
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

  Future<void> _syncIndicatorSettingsToServer() async {
    final Map<String, dynamic> allParams = {};
    _indicators.forEach((key, settings) { allParams[key] = settings.params; });
    await _chartService.saveIndicatorSettingsToServer(
      symbol: widget.symbol, 
      bbEnabled: _indicators['bb']?.enabled ?? false, 
      emaEnabled: _indicators['ema']?.enabled ?? false, 
      bbPeriod: _safeInt(_indicators['bb']?.params['period'], 20), 
      bbStdDev: _safeDouble(_indicators['bb']?.params['stdDev2'], 2.0),
      emaPeriod1: _safeInt(_indicators['ema']?.params['period1'], 10), 
      emaPeriod2: _safeInt(_indicators['ema']?.params['period2'], 25), 
      emaPeriod3: _safeInt(_indicators['ema']?.params['period3'], 50), 
      emailAlertsEnabled: _emailNotificationEnabled,
      alertTargetIndicators: _alertTargetIndicators,
      allParams: allParams,
      rsiEnabled: _indicators['rsi']?.enabled ?? false, 
      rsiPeriod: _safeInt(_indicators['rsi']?.params['period'], 14), 
      macdEnabled: _indicators['macd']?.enabled ?? false, 
      macdFast: _safeInt(_indicators['macd']?.params['fast'], 12), 
      macdSlow: _safeInt(_indicators['macd']?.params['slow'], 26), 
      macdSignal: _safeInt(_indicators['macd']?.params['signal'], 9),
      stochasticEnabled: _indicators['stochastic']?.enabled ?? false, 
      stochKPeriod: _safeInt(_indicators['stochastic']?.params['kPeriod'], 14), 
      stochDPeriod: _safeInt(_indicators['stochastic']?.params['dPeriod'], 3), 
      stochSmooth: _safeInt(_indicators['stochastic']?.params['smooth'], 3),
      cciEnabled: _indicators['cci']?.enabled ?? false, 
      cciPeriod: _safeInt(_indicators['cci']?.params['period'], 20),
    );
    final thresholds = await _chartService.getAllThresholdsFromServer(widget.symbol);
    if (mounted) context.read<MarketDataProvider>().updateSymbolCache(widget.symbol, thresholds);
  }

  // --- Refresh Timer Logic ---

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

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final data = await _chartService.getChartData(widget.symbol, interval: _interval);
      if (mounted) {
        setState(() { _candles = data; _isLoading = false; });
        _refreshCrossHistory();
      }
    } catch (e) { if (mounted) setState(() { _error = e.toString(); _isLoading = false; }); }
  }

  Future<void> _refreshChartData() async {
    try {
      final data = await _chartService.getChartData(widget.symbol, interval: _interval);
      if (mounted && data.isNotEmpty) {
        setState(() { _candles = data; });
        final localCrosses = CrossDetectionService.detectCrosses(
          symbol: widget.symbol, interval: _interval, candles: _candles, targetIndicators: _alertTargetIndicators, settings: _indicators,
        );
        for (final cross in localCrosses) {
          final String notificationKey = '${cross.type.name}_${cross.indicatorName}_${cross.interval}';
          _sentNotifications.remove(notificationKey);
          await CrossDetectionService.saveCrossEvent(cross);
        }
        final history = await CrossDetectionService.getCrossHistory(widget.symbol);
        final currentPrice = _candles.last.close;
        if (_threshold != null && _emailNotificationEnabled) {
          for (final event in history) {
            if (!_alertTargetIndicators.contains(event.type.name) && 
                !(event.type == CrossType.ema && _alertTargetIndicators.contains('ema')) &&
                !(event.type == CrossType.bb && _alertTargetIndicators.contains('bb'))) {
              continue;
            }
            final String notificationKey = '${event.type.name}_${event.indicatorName}_${event.interval}';
            if (_sentNotifications.contains(notificationKey)) continue;
            if (CrossDetectionService.checkThresholdReached(event, currentPrice, _threshold!)) {
              final success = await _chartService.sendThresholdEmail(
                symbol: widget.symbol, interval: event.interval, crossEvent: event, currentPrice: currentPrice, threshold: _threshold!,
              );
              if (success) _sentNotifications.add(notificationKey);
            }
          }
        }
        _refreshCrossHistory();
      }
    } catch (e) { debugPrint('Error in refreshChartData: $e'); }
  }

  // --- UI Action Handlers ---

  void _showIntervalSettings() {
    showDialog(
      context: context, 
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent, 
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), 
        child: Stack(
          clipBehavior: Clip.none, 
          children: [
            Container(
              decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.all(Radius.circular(20))), 
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), 
              child: Column(
                mainAxisSize: MainAxisSize.min, 
                children: [
                  Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))), 
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.access_time, color: AppColors.primaryLight, size: 20), SizedBox(width: 8), Text('時間足選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))]), 
                  const SizedBox(height: 32), 
                  Wrap(spacing: 12, runSpacing: 16, alignment: WrapAlignment.center, children: _intervals.map((i) => _buildIntervalOption(i)).toList())
                ]
              )
            ), 
            Positioned(top: 8, right: 8, child: IconButton(onPressed: () => Navigator.pop(context), icon: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white.withAlpha(20), shape: BoxShape.circle), child: const Icon(Icons.close, color: Colors.white54, size: 20)), tooltip: '閉じる'))
          ]
        )
      )
    );
  }

  Widget _buildIntervalOption(String i) {
    final bool isSelected = _interval == i;
    final bool hasThreshold = _allIntervalThresholds.containsKey(i);
    return GestureDetector(
      onTap: () { setState(() { _interval = i; }); _loadData(); _loadCrossSettings(); Navigator.pop(context); },
      child: Container(
        width: (MediaQuery.of(context).size.width - 100) / 3, 
        padding: const EdgeInsets.symmetric(vertical: 14), 
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withAlpha(40) : Colors.white.withAlpha(10), 
          borderRadius: BorderRadius.circular(12), 
          border: Border.all(color: isSelected ? AppColors.primaryLight : (hasThreshold ? AppColors.warning.withAlpha(100) : Colors.transparent), width: 1.5)
        ), 
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, 
          children: [
            Text(_getIntervalLabel(i), style: TextStyle(color: isSelected ? Colors.white : (hasThreshold ? AppColors.warning : AppColors.textSecondary), fontWeight: isSelected || hasThreshold ? FontWeight.bold : FontWeight.normal, fontSize: 15)), 
            if (hasThreshold) ...[const SizedBox(width: 4), const Icon(Icons.notifications_active, size: 16, color: AppColors.warning)]
          ]
        )
      ),
    );
  }

  void _showChartTypeSettings() {
    showDialog(
      context: context, 
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent, 
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), 
        child: Stack(
          clipBehavior: Clip.none, 
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), 
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)), 
              child: Column(
                mainAxisSize: MainAxisSize.min, 
                children: [
                  Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))), 
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.bar_chart, color: AppColors.primaryLight, size: 22), SizedBox(width: 8), Text('チャートタイプ選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))]), 
                  const SizedBox(height: 32), 
                  LayoutBuilder(builder: (context, constraints) { 
                    final itemWidth = (constraints.maxWidth - 12) / 2; 
                    return Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
                      _buildChartTypeOption(type: ChartType.heikinAshi, label: '平均足', icon: Icons.bar_chart, width: itemWidth), 
                      _buildChartTypeOption(type: ChartType.candlestick, label: 'ローソク足', icon: Icons.candlestick_chart, width: itemWidth), 
                      _buildChartTypeOption(type: ChartType.dot, label: 'ドット', icon: Icons.scatter_plot, width: itemWidth), 
                      _buildChartTypeOption(type: ChartType.line, label: '折れ線', icon: Icons.show_chart, width: itemWidth)
                    ]); 
                  })
                ]
              )
            ), 
            Positioned(top: 8, right: 8, child: IconButton(onPressed: () => Navigator.pop(context), icon: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white.withAlpha(20), shape: BoxShape.circle), child: const Icon(Icons.close, color: Colors.white54, size: 20)), tooltip: '閉じる'))
          ]
        )
      )
    );
  }

  Widget _buildChartTypeOption({required ChartType type, required String label, required IconData icon, required double width}) {
    final bool isSelected = _chartType == type;
    return GestureDetector(
      onTap: () { setState(() { _chartType = type; }); Navigator.pop(context); },
      child: Container(
        width: width, 
        padding: const EdgeInsets.symmetric(vertical: 20), 
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withAlpha(40) : Colors.white.withAlpha(5), 
          borderRadius: BorderRadius.circular(16), 
          border: Border.all(color: isSelected ? AppColors.primaryLight : Colors.white.withAlpha(10), width: isSelected ? 2.0 : 1.0), 
          boxShadow: isSelected ? [BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))] : null
        ), 
        child: Column(
          children: [
            Icon(icon, size: 36, color: isSelected ? AppColors.primaryLight : AppColors.textSecondary), 
            const SizedBox(height: 12), 
            Text(label, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : AppColors.textSecondary))
          ]
        )
      ),
    );
  }

  void _showIndicatorSettings() {
    showDialog(
      context: context, 
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent, 
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), 
        child: IndicatorSettingsSheet(
          indicators: _indicators, 
          onChanged: (k, s) { setState(() => _indicators[k] = s); _syncIndicatorSettingsToServer(); }, 
          onReset: () { 
            setState(() { 
              final defaults = _getDefaultIndicators(); 
              defaults.forEach((key, value) { 
                if (_indicators.containsKey(key)) { 
                  _indicators[key]!.params.clear(); 
                  _indicators[key]!.params.addAll(value.params); 
                } 
              }); 
            }); 
            _syncIndicatorSettingsToServer(); 
            return _indicators; 
          }, 
          onToggle: (k, e) { 
            setState(() { 
              const oscillators = ['rsi', 'macd', 'stochastic', 'cci', 'ma_dev', 'dmi', 'adx', 'rci', 'momentum', 'roc', 'ultimate', 'trix']; 
              final isOsc = oscillators.contains(k); 
              if (e && isOsc) { 
                _indicators.forEach((key, value) { 
                  if (oscillators.contains(key) && key != k) value.enabled = false; 
                }); 
              } 
              _indicators[k]!.enabled = e; 
            }); 
            _syncIndicatorSettingsToServer(); 
          }
        )
      )
    );
  }

  void _showCrossSettings() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: CrossSettingsModal(
          symbol: widget.symbol, interval: _interval, crossHistory: _crossHistory, threshold: _threshold, targetIndicators: _alertTargetIndicators, indicators: _indicators, emailNotificationEnabled: _emailNotificationEnabled, currentPrice: _candles.isNotEmpty ? _candles.last.close : null,
          onThresholdChanged: (v) async {
            setState(() => _threshold = v);
            await _chartService.saveThresholdToServer(symbol: widget.symbol, interval: _interval, threshold: v);
            final thresholds = await _chartService.getAllThresholdsFromServer(widget.symbol);
            if (mounted) {
              context.read<MarketDataProvider>().updateSymbolCache(widget.symbol, thresholds);
              _loadAllIntervalThresholds();
            }
          },
          onTargetIndicatorsChanged: (v) { setState(() => _alertTargetIndicators = v); _syncIndicatorSettingsToServer(); },
          onEmailNotificationChanged: (v) { setState(() => _emailNotificationEnabled = v); _syncIndicatorSettingsToServer(); },
          onClearHistory: () async { await _chartService.clearCrossHistoryOnServer(widget.symbol); await _refreshCrossHistory(); },
        ),
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
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.all(Radius.circular(20))), 
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), 
          child: Column(
            mainAxisSize: MainAxisSize.min, 
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))), 
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.category_outlined, color: AppColors.primaryLight, size: 20), SizedBox(width: 8), Text('カテゴリー選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))]), 
              const SizedBox(height: 32), 
              Column(
                children: MarketCategory.values.map((cat) => Padding(
                  padding: const EdgeInsets.only(bottom: 12), 
                  child: InkWell(
                    onTap: () { 
                      Navigator.of(context).pop(); 
                      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => HomeScreen(initialCategory: cat)), (route) => false); 
                    }, 
                    borderRadius: BorderRadius.circular(12), 
                    child: Container(
                      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20), 
                      decoration: BoxDecoration(color: widget.category == cat ? AppColors.primary.withAlpha(40) : Colors.white.withAlpha(10), borderRadius: BorderRadius.circular(12), border: Border.all(color: widget.category == cat ? AppColors.primaryLight : Colors.transparent, width: 1.5)), 
                      child: Row(
                        children: [
                          Icon(cat.icon, color: cat == MarketCategory.crypto ? AppColors.crypto : (cat == MarketCategory.forex ? AppColors.forex : AppColors.stock), size: 24), 
                          const SizedBox(width: 16), 
                          Text(cat.label, style: TextStyle(color: widget.category == cat ? Colors.white : AppColors.textSecondary, fontWeight: widget.category == cat ? FontWeight.bold : FontWeight.normal, fontSize: 16)), 
                          const Spacer(), 
                          if (widget.category == cat) const Icon(Icons.check_circle, color: AppColors.primaryLight, size: 20)
                        ]
                      )
                    )
                  )
                )).toList()
              )
            ]
          )
        )
      )
    );
  }

  // --- Helpers ---

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
    if (mounted) setState(() { _crossHistory = _parseServerCrossHistory(serverHistory, _interval); });
  }

  String _getIntervalLabel(String i) {
    switch (i) {
      case '5m': return '5分'; case '15m': return '15分'; case '30m': return '30分'; case '1h': return '1時間';
      case '4h': return '4時間'; case '1d': return '1日'; case '1wk': return '1週間'; case '1mo': return '1ヶ月';
      default: return i;
    }
  }

  static int _safeInt(dynamic v, int d) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? d : d));
  static double _safeDouble(dynamic v, double d) => v is double ? v : (v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? d : d));

  Map<String, IndicatorSettings> _getDefaultIndicators() => {
    'bb': IndicatorSettings(enabled: false, params: {'period': 20, 'stdDev1': 1.0, 'stdDev2': 2.0}),
    'ema': IndicatorSettings(enabled: false, params: {'period1': 10, 'period2': 25, 'period3': 50}),
    'sma': IndicatorSettings(enabled: false, params: {'period': 20}),
    'wma': IndicatorSettings(enabled: false, params: {'period': 20}),
    'ichimoku': IndicatorSettings(enabled: false, params: {'tenkan': 9, 'kijun': 26, 'senkouB': 52, 'displacement': 26}),
    'parabolic': IndicatorSettings(enabled: false, params: {'acceleration': 0.02, 'maxAcceleration': 0.2}),
    'envelope': IndicatorSettings(enabled: false, params: {'period': 20, 'deviation': 2.5}),
    'keltner': IndicatorSettings(enabled: false, params: {'period': 20, 'multiplier': 2.0}),
    'supertrend': IndicatorSettings(enabled: false, params: {'period': 10, 'multiplier': 3.0}),
    'gmma': IndicatorSettings(enabled: false, params: {'short1': 3, 'short2': 5, 'short3': 8, 'short4': 10, 'short5': 12, 'short6': 15, 'long1': 30, 'long2': 35, 'long3': 40, 'long4': 45, 'long5': 50, 'long6': 60}),
    'rsi': IndicatorSettings(enabled: false, params: {'period': 14}),
    'macd': IndicatorSettings(enabled: false, params: {'fast': 12, 'slow': 26, 'signal': 9}),
    'stochastic': IndicatorSettings(enabled: false, params: {'kPeriod': 14, 'dPeriod': 3, 'smooth': 3}),
    'cci': IndicatorSettings(enabled: false, params: {'period': 20}),
    'ma_dev': IndicatorSettings(enabled: false, params: {'period': 25}),
    'dmi': IndicatorSettings(enabled: false, params: {'period': 14}),
    'adx': IndicatorSettings(enabled: false, params: {'period': 14}),
    'rci': IndicatorSettings(enabled: false, params: {'period': 9}),
    'momentum': IndicatorSettings(enabled: false, params: {'period': 10}),
    'roc': IndicatorSettings(enabled: false, params: {'period': 12}),
    'ultimate': IndicatorSettings(enabled: false, params: {'p1': 7, 'p2': 14, 'p3': 28}),
    'trix': IndicatorSettings(enabled: false, params: {'period': 12}),
  };

  // --- Build Methods ---

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
                  elevation: 0, scrolledUnderElevation: 0, backgroundColor: AppColors.chartBackground, titleSpacing: 0,
                  leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), onPressed: () => Navigator.of(context).pop()),
                  title: GestureDetector(onTap: () => Navigator.of(context).pop(), child: Text('${widget.category.label}一覧', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  actions: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: ChartTimerWidget(isRefreshing: _isRefreshing, secondsUntilRefresh: _secondsUntilRefresh)), 
                    IconButton(icon: const Icon(Icons.logout), tooltip: 'ログアウト', onPressed: () => _handleLogout())
                  ],
                ),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: DetailFooter(
        isChartMaximized: _isMaximizedChart, 
        onHomeTap: () => Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => HomeScreen()), (route) => false), 
        onChartMaximizeTap: () => setState(() => _isMaximizedChart = !_isMaximizedChart), 
        onCategoryTap: _showCategorySettings,
      ),
    );
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
              child: _isMaximizedChart 
                  ? const SizedBox.shrink() 
                  : DetailSymbolHeader(
                      symbol: widget.symbol, 
                      category: widget.category, 
                      interval: _interval, 
                      intervalLabel: _getIntervalLabel(_interval), 
                      hasCrossHistory: _crossHistory.isNotEmpty, 
                      onIntervalTap: _showIntervalSettings, 
                      onCrossSettingsTap: _showCrossSettings
                    )
            )
          ),
          Expanded(
            child: FinancialChart(
              candles: _candles, 
              chartType: _chartType, 
              indicators: _indicators, 
              interval: _interval, 
              symbol: widget.symbol, 
              memoCount: _memoCount, 
              isMaximized: _isMaximizedChart, 
              onShowIndicatorSettings: _showIndicatorSettings, 
              onShowChartTypeSettings: _showChartTypeSettings, 
              onMemoPressed: () async { 
                await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => MemoScreen(symbol: widget.symbol))); 
                _loadMemoCount(); 
              }
            )
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    await context.read<AuthProvider>().logout();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
