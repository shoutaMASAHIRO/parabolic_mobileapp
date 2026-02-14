import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/candle.dart';
import '../models/chart_configs.dart';
import '../theme/app_colors.dart';
import '../widgets/chart_painters.dart';

class FinancialChart extends StatefulWidget {
  final List<Candle> candles;
  final ChartType chartType;
  final Map<String, IndicatorSettings> indicators;
  final String interval;
  final String symbol;
  final int memoCount;
  final bool isMaximized;
  final VoidCallback onShowIndicatorSettings;
  final VoidCallback onShowChartTypeSettings;
  final VoidCallback onMemoPressed;

  const FinancialChart({
    super.key,
    required this.candles,
    required this.chartType,
    required this.indicators,
    required this.interval,
    required this.symbol,
    required this.memoCount,
    required this.isMaximized,
    required this.onShowIndicatorSettings,
    required this.onShowChartTypeSettings,
    required this.onMemoPressed,
  });

  @override
  State<FinancialChart> createState() => _FinancialChartState();
}

class _FinancialChartState extends State<FinancialChart> with SingleTickerProviderStateMixin {
  late AnimationController _scrollAnimationController;
  double _scrollVelocity = 0.0;
  
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
  final Map<String, double?> _touchedIndicatorLevels = {};

  bool get _showBB => widget.indicators['bb']?.enabled ?? false;
  bool get _showEMA => widget.indicators['ema']?.enabled ?? false;
  bool get _showRSI => widget.indicators['rsi']?.enabled ?? false;
  bool get _showMACD => widget.indicators['macd']?.enabled ?? false;
  bool get _showStochastic => widget.indicators['stochastic']?.enabled ?? false;
  bool get _showCCI => widget.indicators['cci']?.enabled ?? false;

  int get _bbPeriod => _safeInt(widget.indicators['bb']?.params['period'], 20);
  double get _bbStdDev1 => _safeDouble(widget.indicators['bb']?.params['stdDev1'], 1.0);
  double get _bbStdDev2 => _safeDouble(widget.indicators['bb']?.params['stdDev2'], 2.0);
  int get _emaPeriod1 => _safeInt(widget.indicators['ema']?.params['period1'], 10);
  int get _emaPeriod2 => _safeInt(widget.indicators['ema']?.params['period2'], 25);
  int get _emaPeriod3 => _safeInt(widget.indicators['ema']?.params['period3'], 50);
  int get _rsiPeriod => _safeInt(widget.indicators['rsi']?.params['period'], 14);
  int get _macdFast => _safeInt(widget.indicators['macd']?.params['fast'], 12);
  int get _macdSlow => _safeInt(widget.indicators['macd']?.params['slow'], 26);
  int get _macdSignal => _safeInt(widget.indicators['macd']?.params['signal'], 9);
  int get _stochKPeriod => _safeInt(widget.indicators['stochastic']?.params['kPeriod'], 14);
  int get _stochDPeriod => _safeInt(widget.indicators['stochastic']?.params['dPeriod'], 3);
  int get _stochSmooth => _safeInt(widget.indicators['stochastic']?.params['smooth'], 3);
  int get _cciPeriod => _safeInt(widget.indicators['cci']?.params['period'], 20);

  static int _safeInt(dynamic v, int d) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? d : d));
  static double _safeDouble(dynamic v, double d) => v is double ? v : (v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? d : d));

  int get _activeIndicatorCount => widget.indicators.values.where((v) => v.enabled).length;

  @override
  void initState() {
    super.initState();
    _scrollAnimationController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _scrollAnimationController.addListener(_handleScrollAnimation);
  }

  @override
  void dispose() {
    _scrollAnimationController.dispose();
    super.dispose();
  }

  void _handleScrollAnimation() {
    if (_scrollAnimationController.isAnimating) {
      setState(() { _chartPanOffsetX = (_chartPanOffsetX + _scrollVelocity).clamp(0.0, 1.0); });
      _scrollVelocity *= 0.92;
      if (_scrollVelocity.abs() < 0.0001) _scrollAnimationController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
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
          width: widget.isMaximized ? 0 : 60,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(),
          child: _buildRightToolbar(),
        ),
      ],
    );
  }

  Widget _buildChart() {
    switch (widget.chartType) {
      case ChartType.line: return _buildLineChart(widget.candles);
      case ChartType.candlestick: return _buildCandlestickChart(widget.candles);
      case ChartType.heikinAshi: return _buildCandlestickChart(Candle.toHeikinAshi(widget.candles));
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
            CustomPaint(size: Size(cs.maxWidth, cs.maxHeight), painter: ChartGridPainter(dataLength: visibleCandles.length, xLabelInterval: xInt, minY: adjMinY, maxY: adjMaxY, startIndex: visibleStart, latestPrice: widget.candles.isNotEmpty ? widget.candles.last.close : null, touchedPrice: _touchedPrice, touchedDateTime: _touchedDateTime, candles: visibleCandles)),
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
            CustomPaint(size: Size(cs.maxWidth, cs.maxHeight), painter: ChartGridPainter(dataLength: visibleCandles.length, xLabelInterval: xInt, minY: adjMinY, maxY: adjMaxY, startIndex: visibleStart, latestPrice: widget.candles.isNotEmpty ? widget.candles.last.close : null, touchedPrice: _touchedPrice, touchedDateTime: _touchedDateTime, candles: visibleCandles)),
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
          _buildToolbarButton(icon: Icons.tune, onPressed: widget.onShowIndicatorSettings, isActive: _activeIndicatorCount > 0),
          _buildToolbarButton(icon: Icons.bar_chart, onPressed: widget.onShowChartTypeSettings),
          _buildToolbarButton(
            icon: Icons.note_alt_outlined,
            onPressed: widget.onMemoPressed,
            badgeCount: widget.memoCount,
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

  int _calculateXLabelInterval(int d) {
    int interval;
    if (d <= 15) interval = 2;
    else if (d <= 40) interval = 5;
    else if (d <= 80) interval = 10;
    else if (d <= 150) interval = 20;
    else if (d <= 300) interval = 40;
    else interval = (d / 6).ceil();
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
                latestPrice: oscillatorType == null && widget.candles.isNotEmpty ? widget.candles.last.close : null,
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
                intervalType: widget.interval,
                touchedDateTime: _touchedDateTime,
              )
            )
          ),
        );
      }
    );
  }

  String _formatPriceWithCurrency(double p) {
    // Note: MarketCategory and symbol-based logic might need refinement if passed as props
    final cp = p; // Simplification, can be improved with JPY rate if needed
    return "\$${_formatPrice(cp)}";
  }
  String _formatPrice(double p) => NumberFormat('#,##0').format(p.round());
}
