class Candle {
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;

  Candle({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  factory Candle.fromJson(Map<String, dynamic> json) {
    return Candle(
      date: DateTime.parse(json['date'] as String),
      open: (json['open'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
      low: (json['low'] as num).toDouble(),
      close: (json['close'] as num).toDouble(),
    );
  }

  // 変動率を計算
  double get changePercent => ((close - open) / open) * 100;

  bool get isPositive => close >= open;

  // 平均足（Heikin-Ashi）を計算
  static List<Candle> toHeikinAshi(List<Candle> candles) {
    if (candles.isEmpty) return [];

    final result = <Candle>[];

    for (int i = 0; i < candles.length; i++) {
      final current = candles[i];

      // HA Close = (Open + High + Low + Close) / 4
      final haClose = (current.open + current.high + current.low + current.close) / 4;

      // HA Open = (前のHA Open + 前のHA Close) / 2
      final haOpen = i == 0
          ? (current.open + current.close) / 2
          : (result[i - 1].open + result[i - 1].close) / 2;

      // HA High = max(High, HA Open, HA Close)
      final haHigh = [current.high, haOpen, haClose].reduce((a, b) => a > b ? a : b);

      // HA Low = min(Low, HA Open, HA Close)
      final haLow = [current.low, haOpen, haClose].reduce((a, b) => a < b ? a : b);

      result.add(Candle(
        date: current.date,
        open: haOpen,
        high: haHigh,
        low: haLow,
        close: haClose,
      ));
    }

    return result;
  }
}
