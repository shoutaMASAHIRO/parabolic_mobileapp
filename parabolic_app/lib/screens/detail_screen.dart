import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/candle.dart';
import '../services/chart_service.dart';
import 'memo_screen.dart';

// チャートタイプ
enum ChartType { line, candlestick, heikinAshi }

class DetailScreen extends StatefulWidget {
  final String symbol;

  const DetailScreen({super.key, required this.symbol});

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

  final List<String> _intervals = ['1h', '4h', '1d', '1wk', '1mo'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

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

  @override
  Widget build(BuildContext context) {
    final displayName = widget.symbol.replaceAll('-USD', '');

    return Scaffold(
      appBar: AppBar(
        title: Text(displayName),
        actions: [
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
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(_getIntervalLabel(_interval)),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  String _getIntervalLabel(String interval) {
    switch (interval) {
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
              _buildPriceHeader(),
              const SizedBox(height: 16),
              _buildChartTypeSelector(),
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

  Widget _buildChartTypeSelector() {
    return SegmentedButton<ChartType>(
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
    );
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
          '\$${_formatPrice(latestCandle.close)}',
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
              '${isPositive ? '+' : ''}\$${_formatPrice(priceChange.abs())} (${changePercent.toStringAsFixed(2)}%)',
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
    final spots = candles.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.close);
    }).toList();

    final minY = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final maxY = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.1;

    final isPositive = candles.last.close >= candles.first.close;
    final chartColor = isPositive ? Colors.green : Colors.red;

    return SizedBox(
      height: 300,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY) / 5,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey.withAlpha(50),
                strokeWidth: 1,
              );
            },
          ),
          titlesData: _buildTitlesData(candles, minY, maxY),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (candles.length - 1).toDouble(),
          minY: minY - padding,
          maxY: maxY + padding,
          lineBarsData: [
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
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final index = spot.x.toInt();
                  if (index < 0 || index >= candles.length) return null;
                  final candle = candles[index];
                  return LineTooltipItem(
                    '${DateFormat('yyyy/MM/dd').format(candle.date)}\n\$${_formatPrice(candle.close)}',
                    const TextStyle(color: Colors.white),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCandlestickChart(List<Candle> candles) {
    final minY = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final maxY = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.1;

    return SizedBox(
      height: 300,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTapDown: (details) {
              _showCandleTooltip(context, details, candles, constraints.maxWidth);
            },
            child: CustomPaint(
              size: Size(constraints.maxWidth, 300),
              painter: CandlestickPainter(
                candles: candles,
                minY: minY - padding,
                maxY: maxY + padding,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCandleTooltip(BuildContext context, TapDownDetails details, List<Candle> candles, double width) {
    final candleWidth = width / candles.length;
    final index = (details.localPosition.dx / candleWidth).floor();

    if (index < 0 || index >= candles.length) return;

    final candle = candles[index];
    final isHeikinAshi = _chartType == ChartType.heikinAshi;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${DateFormat('yyyy/MM/dd').format(candle.date)} | '
          '始: \$${_formatPrice(candle.open)} '
          '高: \$${_formatPrice(candle.high)} '
          '安: \$${_formatPrice(candle.low)} '
          '終: \$${_formatPrice(candle.close)}'
          '${isHeikinAshi ? ' (平均足)' : ''}',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  FlTitlesData _buildTitlesData(List<Candle> candles, double minY, double maxY) {
    return FlTitlesData(
      show: true,
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          interval: (candles.length / 5).ceilToDouble(),
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index < 0 || index >= candles.length) {
              return const SizedBox.shrink();
            }
            final date = candles[index].date;
            final format = _interval == '1h' || _interval == '4h'
                ? DateFormat('MM/dd HH:mm')
                : DateFormat('MM/dd');
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                format.format(date),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 60,
          getTitlesWidget: (value, meta) {
            return Text(
              _formatPrice(value),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            );
          },
        ),
      ),
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
            _buildStatRow('始値', '\$${_formatPrice(open)}'),
            _buildStatRow('終値', '\$${_formatPrice(close)}'),
            _buildStatRow('高値', '\$${_formatPrice(high)}'),
            _buildStatRow('安値', '\$${_formatPrice(low)}'),
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

// ローソク足チャートを描画するCustomPainter
class CandlestickPainter extends CustomPainter {
  final List<Candle> candles;
  final double minY;
  final double maxY;

  CandlestickPainter({
    required this.candles,
    required this.minY,
    required this.maxY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final candleWidth = size.width / candles.length;
    final priceRange = maxY - minY;

    // グリッド線を描画
    final gridPaint = Paint()
      ..color = Colors.grey.withAlpha(50)
      ..strokeWidth = 1;

    for (int i = 0; i <= 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
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

  @override
  bool shouldRepaint(covariant CandlestickPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.minY != minY ||
        oldDelegate.maxY != maxY;
  }
}
