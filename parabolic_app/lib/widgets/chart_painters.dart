import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/candle.dart';
import '../theme/app_colors.dart';

// Note: BollingerBandsResult, TechnicalIndicators, OscillatorIndicators, etc. 
// are imported from ../models/candle.dart

class ChartGridPainter extends CustomPainter {
  final int dataLength; final int xLabelInterval; final double minY; final double maxY; final int startIndex;
  final double? latestPrice;
  final double? touchedPrice;
  final DateTime? touchedDateTime;
  final List<Candle>? candles;

  ChartGridPainter({
    required this.dataLength, 
    required this.xLabelInterval, 
    required this.minY, 
    required this.maxY, 
    required this.startIndex,
    this.latestPrice,
    this.touchedPrice,
    this.touchedDateTime,
    this.candles,
  });

  double _calculatePriceStep(double r) {
    if (r <= 0) return 1.0;
    double s = r / 12; double e = (math.log(s) / math.ln10).floorToDouble(); double m = math.pow(10, e).toDouble(); double rs = s / m;
    if (rs < 1.5) return 1.0 * m; if (rs < 3.0) return 2.0 * m; if (rs < 7.0) return 5.0 * m; return 10.0 * m;
  }
  @override
  void paint(Canvas canvas, Size size) {
    if (dataLength == 0) return;
    final dw = size.width / dataLength; final pr = maxY - minY; final p = Paint()..color = AppColors.chartGrid.withOpacity(0.8)..strokeWidth = 0.7;
    double ps = _calculatePriceStep(pr); double fl = (minY / ps).ceil() * ps;
    for (double v = fl; v <= maxY; v += ps) {
      final double y = size.height - ((v - minY) / pr * size.height);
      double curX = 0; while (curX < size.width) { canvas.drawLine(Offset(curX, y), Offset(math.min(curX + 4, size.width), y), p); curX += 8; }
    }
    for (int i = 0; i < dataLength; i++) {
      if ((startIndex + i) % xLabelInterval == 0) {
        final x = i * dw + dw / 2;
        double curY = 0; while (curY < size.height) { canvas.drawLine(Offset(x, curY), Offset(x, math.min(curY + 4, size.height)), p); curY += 8; }
      }
    }

    // 現在値の水平ライン（点線）
    if (latestPrice != null && latestPrice! >= minY && latestPrice! <= maxY) {
      final y = size.height - ((latestPrice! - minY) / pr * size.height);
      final lp = Paint()
        ..color = AppColors.primary.withOpacity(0.6)
        ..strokeWidth = 1.0;
      
      double curX = 0;
      while (curX < size.width) {
        canvas.drawLine(Offset(curX, y), Offset(math.min(curX + 4, size.width), y), lp);
        curX += 8;
      }
    }

    // タッチされた位置の水平ライン（黄色の点線）
    if (touchedPrice != null && touchedPrice! >= minY && touchedPrice! <= maxY) {
      final y = size.height - ((touchedPrice! - minY) / pr * size.height);
      final tp = Paint()
        ..color = Colors.yellow.shade700.withOpacity(0.6)
        ..strokeWidth = 1.0;
      
      double curX = 0;
      while (curX < size.width) {
        canvas.drawLine(Offset(curX, y), Offset(math.min(curX + 4, size.width), y), tp);
        curX += 8;
      }
    }

    // タッチされた日時の垂直ライン（オレンジ色の点線）
    if (touchedDateTime != null && candles != null) {
      int idx = -1;
      for (int i = 0; i < candles!.length; i++) {
        if (candles![i].date == touchedDateTime) {
          idx = i;
          break;
        }
      }
      if (idx != -1) {
        final x = idx * dw + dw / 2;
        final tp = Paint()
          ..color = Colors.orange.shade700.withOpacity(0.6)
          ..strokeWidth = 1.0;
        
        double curY = 0;
        while (curY < size.height) {
          canvas.drawLine(Offset(x, curY), Offset(x, math.min(curY + 4, size.height)), tp);
          curY += 8;
        }
      }
    }
  }
  @override bool shouldRepaint(covariant ChartGridPainter old) => true;
}

class TrendIndicatorData {
  final List<double?> values;
  final Color color;
  final double width;
  final bool isDotted;
  final bool isArea;
  final Color? areaColor;
  
  TrendIndicatorData({
    required this.values,
    required this.color,
    this.width = 1.0,
    this.isDotted = false,
    this.isArea = false,
    this.areaColor,
  });
}

class CandlestickPainter extends CustomPainter {
  final List<Candle> candles; 
  final double minY; 
  final double maxY; 
  final List<TrendIndicatorData>? trendIndicators;
  final List<double?>? parabolicSAR;
  final List<bool>? supertrendIsBull; // For coloring supertrend line
  final int startIndex; 
  final int xLabelInterval; 
  final int indicatorStartIndex;

  CandlestickPainter({
    required this.candles, 
    required this.minY, 
    required this.maxY, 
    this.trendIndicators,
    this.parabolicSAR,
    this.supertrendIsBull,
    this.startIndex = 0, 
    this.xLabelInterval = 5, 
    this.indicatorStartIndex = 0
  });

  double _calculatePriceStep(double r) {
    if (r <= 0) return 1.0;
    double s = r / 12; double e = (math.log(s) / math.ln10).floorToDouble(); double m = math.pow(10, e).toDouble(); double rs = s / m;
    if (rs < 1.5) return 1.0 * m; if (rs < 3.0) return 2.0 * m; if (rs < 7.0) return 5.0 * m; return 10.0 * m;
  }
  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final cw = size.width / candles.length; final pr = maxY - minY; final gp = Paint()..color = AppColors.chartGrid.withOpacity(0.8)..strokeWidth = 0.7;
    double ps = _calculatePriceStep(pr); double fl = (minY / ps).ceil() * ps;
    for (double v = fl; v <= maxY; v += ps) {
      final double y = size.height - ((v - minY) / pr * size.height);
      double curX = 0; while (curX < size.width) { canvas.drawLine(Offset(curX, y), Offset(math.min(curX + 4, size.width), y), gp); curX += 8; }
    }
    for (int i = 0; i < candles.length; i++) {
      if ((startIndex + i) % xLabelInterval == 0) {
        final x = i * cw + cw / 2;
        double curY = 0; while (curY < size.height) { canvas.drawLine(Offset(x, curY), Offset(x, math.min(curY + 4, size.height)), gp); curY += 8; }
      }
    }

    // トレンド系インジケーターの描画
    if (trendIndicators != null) {
      for (final indicator in trendIndicators!) {
        _drawTrendLine(canvas, size, indicator, pr);
      }
    }

    // パラボリックSARの描画（ドット）
    if (parabolicSAR != null) {
      final p = Paint()..style = PaintingStyle.fill;
      for (int i = 0; i < parabolicSAR!.length; i++) {
        final val = parabolicSAR![i];
        if (val != null) {
          final x = i * cw + cw / 2;
          final y = size.height - ((val - minY) / pr * size.height);
          if (y >= 0 && y <= size.height) {
            p.color = candles[i].close >= val ? AppColors.rise : AppColors.fall;
            canvas.drawCircle(Offset(x, y), 2.0, p);
          }
        }
      }
    }

    // ローソク足の描画
    for (int i = indicatorStartIndex; i < candles.length; i++) {
      final c = candles[i]; 
      // ピクセルグリッドに合わせるためX座標を丸める
      final double x = (i * cw + cw / 2).roundToDouble();
      final hy = size.height - ((c.high - minY) / pr * size.height); final ly = size.height - ((c.low - minY) / pr * size.height);
      final oy = size.height - ((c.open - minY) / pr * size.height); final cy = size.height - ((c.close - minY) / pr * size.height);
      final pos = c.close >= c.open; final color = pos ? AppColors.rise : AppColors.fall;
      // ひげ（高値・安値）を白色で均一な太さで描画（透過度で細さを表現）
      canvas.drawLine(Offset(x, hy), Offset(x, ly), Paint()..color = Colors.white.withOpacity(0.6)..strokeWidth = 1.0);
      final bt = pos ? cy : oy; final bb = pos ? oy : cy;
      canvas.drawRect(Rect.fromCenter(center: Offset(x, (bt + bb) / 2), width: (cw * 0.8).clamp(1.0, 20.0), height: (bb - bt).abs().clamp(1.0, size.height)), Paint()..color = color..style = PaintingStyle.fill);
    }
  }

  void _drawTrendLine(Canvas cv, Size s, TrendIndicatorData data, double pr) {
    final p = Paint()
      ..color = data.color
      ..strokeWidth = data.width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    bool started = false;
    final cw = s.width / candles.length;

    for (int i = 0; i < data.values.length; i++) {
      final val = data.values[i];
      if (val != null) {
        final x = i * cw + cw / 2;
        final y = s.height - ((val - minY) / pr * s.height);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      } else {
        started = false;
      }
    }

    if (data.isDotted) {
      // 簡易的な点線実装
      final dashPath = Path();
      double dashWidth = 5.0;
      double dashSpace = 3.0;
      double distance = 0.0;
      for (ui.PathMetric measurePath in path.computeMetrics()) {
        while (distance < measurePath.length) {
          dashPath.addPath(measurePath.extractPath(distance, distance + dashWidth), Offset.zero);
          distance += dashWidth + dashSpace;
        }
        distance = 0.0;
      }
      cv.drawPath(dashPath, p);
    } else {
      cv.drawPath(path, p);
    }
  }

  @override bool shouldRepaint(covariant CandlestickPainter old) => true;
}


class YAxisLabelPainter extends CustomPainter {
  final double minY, maxY;
  final double? latestPrice;
  final double? touchedPrice;
  final List<double>? fixedLevels;

  YAxisLabelPainter({
    required this.minY,
    required this.maxY,
    this.latestPrice,
    this.touchedPrice,
    this.fixedLevels,
  });

  @override
  void paint(Canvas canvas, ui.Size size) {
    final range = maxY - minY;
    if (range <= 0) return;

    final ts = const TextStyle(
      fontSize: 10,
      color: Colors.white70,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    );

    final List<double> valuesToDraw = [];

    if (fixedLevels != null) {
      valuesToDraw.addAll(fixedLevels!.where((v) => v >= minY && v <= maxY));
    } else {
      double s = range / 10;
      if (s == 0) s = 1.0;
      double e = (math.log(s) / math.ln10).floorToDouble();
      double m = math.pow(10, e).toDouble();
      double rs = s / m;
      double ps = (rs < 1.5) ? 1.0 * m : (rs < 3.0) ? 2.0 * m : (rs < 7.0) ? 5.0 * m : 10.0 * m;
      if (ps == 0) ps = 1.0;

      double fl = (minY / ps).ceil() * ps;
      for (double v = fl; v <= maxY; v += ps) {
        valuesToDraw.add(v);
      }
    }

    for (final v in valuesToDraw) {
      final double y = size.height - ((v - minY) / range * size.height);
      if (y >= 0 && y <= size.height) {
        String label = v.toStringAsFixed(v < 0.1 ? 4 : (v < 1 ? 3 : (v < 100 ? 2 : 0)));
        final tp = TextPainter(
          text: TextSpan(text: label, style: ts),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(6, y - tp.height / 2));
      }
    }

    // タッチされた位置の価格ラベルの描画（黄色 or 黄緑色）
    if (touchedPrice != null && touchedPrice! >= minY && touchedPrice! <= maxY) {
      final y = size.height - ((touchedPrice! - minY) / range * size.height);
      String priceLabel = touchedPrice!.toStringAsFixed(touchedPrice! < 1 ? 4 : (touchedPrice! < 100 ? 2 : 0));
      final tp = TextPainter(
        text: TextSpan(text: priceLabel, style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      // 背景色の切り替え（メインは黄色、インジケーターは黄緑）
      final bgPaint = Paint()..color = latestPrice == null ? Colors.lightGreen.shade700 : Colors.yellow.shade700;
      final double labelHeight = 18; 
      final double labelWidth = size.width - 4;
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(2, y - labelHeight / 2, labelWidth, labelHeight), 
          const Radius.circular(4)
        ), 
        bgPaint
      );
      
      tp.paint(canvas, Offset(labelWidth / 2 - tp.width / 2 + 2, y - tp.height / 2));
    }

    // 現在価格ラベルと水平ラインの描画（メインチャート用）
    if (latestPrice != null && latestPrice! >= minY && latestPrice! <= maxY) {
      final y = size.height - ((latestPrice! - minY) / range * size.height);
      final tp = TextPainter(
        text: TextSpan(text: latestPrice!.toStringAsFixed(latestPrice! < 1 ? 4 : (latestPrice! < 100 ? 2 : 0)), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      final bgPaint = Paint()..color = AppColors.primary;
      final double labelHeight = 18;
      final double labelWidth = size.width - 4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(2, y - labelHeight / 2, labelWidth, labelHeight), 
          const Radius.circular(4)
        ), 
        bgPaint
      );
      tp.paint(canvas, Offset(labelWidth / 2 - tp.width / 2 + 2, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant YAxisLabelPainter old) => true;
}

class XAxisLabelPainter extends CustomPainter {
  final List<Candle> visibleCandles; final int interval; final int startIndex; final String intervalType;
  final DateTime? touchedDateTime;

  XAxisLabelPainter({
    required this.visibleCandles, 
    required this.interval, 
    required this.startIndex, 
    required this.intervalType,
    this.touchedDateTime,
  });

  @override
  void paint(Canvas canvas, ui.Size size) {
    if (visibleCandles.isEmpty) return; final double cw = size.width / visibleCandles.length;
    final ts = TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.bold);
    
    for (int i = 0; i < visibleCandles.length; i++) {
      if ((startIndex + i) % interval == 0) {
        final x = i * cw + cw / 2; final c = visibleCandles[i];
        String label = (intervalType.contains('m') || intervalType.contains('h')) ? DateFormat('HH:mm').format(c.date) : DateFormat('MM/dd').format(c.date);
        final tp = TextPainter(text: TextSpan(text: label, style: ts), textDirection: ui.TextDirection.ltr)..layout();
        if (x + tp.width / 2 < size.width) {
          tp.paint(canvas, Offset(x - tp.width / 2, 4));
        } else if (x - tp.width / 2 < size.width) {
          tp.paint(canvas, Offset(size.width - tp.width - 2, 4));
        }
      }
    }

    // タッチされた日時のラベル描画（黄色）
    if (touchedDateTime != null) {
      int idx = -1;
      for (int i = 0; i < visibleCandles.length; i++) {
        if (visibleCandles[i].date == touchedDateTime) {
          idx = i;
          break;
        }
      }
      if (idx != -1) {
        final x = idx * cw + cw / 2;
        String label = (intervalType.contains('m') || intervalType.contains('h')) ? DateFormat('MM/dd HH:mm').format(touchedDateTime!) : DateFormat('yyyy/MM/dd').format(touchedDateTime!);
        final tp = TextPainter(
          text: TextSpan(text: label, style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
          textDirection: ui.TextDirection.ltr,
        )..layout();

        final bgPaint = Paint()..color = Colors.orange.shade700;
        final double labelHeight = 18;
        final double labelWidth = tp.width + 12;
        
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - labelWidth / 2, 2, labelWidth, labelHeight), 
            const Radius.circular(4)
          ), 
          bgPaint
        );
        
        tp.paint(canvas, Offset(x - tp.width / 2, 2 + (labelHeight - tp.height) / 2));
      }
    }
  }
  @override bool shouldRepaint(covariant XAxisLabelPainter old) => true;
}

class OscillatorPainter extends CustomPainter {
  final List<double?> values; final double minY, maxY; final Color lineColor; final String oscillatorType; final List<double?>? signalLine; final List<double?>? histogram; final int startIndex; final int xLabelInterval;
  final double? touchedLevel;
  final DateTime? touchedDateTime;
  final List<Candle>? candles;

  OscillatorPainter({
    required this.values, 
    required this.minY, 
    required this.maxY, 
    required this.lineColor, 
    required this.oscillatorType, 
    this.signalLine, 
    this.histogram, 
    required this.startIndex, 
    required this.xLabelInterval,
    this.touchedLevel,
    this.touchedDateTime,
    this.candles,
  });
  @override
  void paint(Canvas canvas, ui.Size size) {
    if (values.isEmpty) return; final double cw = size.width / values.length; final double range = maxY - minY; if (range <= 0) return;
    final gridPaint = Paint()..color = AppColors.chartGrid.withOpacity(0.8)..strokeWidth = 0.7;
    
    for (int i = 0; i < values.length; i++) {
      if ((startIndex + i) % xLabelInterval == 0) {
        final x = i * cw + cw / 2;
        double curY = 0; while (curY < size.height) { canvas.drawLine(Offset(x, curY), Offset(x, math.min(curY + 4, size.height)), gridPaint); curY += 8; }
      }
    }

    final levels = <double>[];
    if (oscillatorType == 'rsi') levels.addAll([70, 50, 30]);
    else if (oscillatorType == 'macd') levels.add(0);
    else if (oscillatorType == 'stochastic') levels.addAll([80, 50, 20]);
    else if (oscillatorType == 'cci') levels.addAll([100, 0, -100]);
    for (final l in levels) {
      final y = size.height - ((l - minY) / range * size.height);
      if (y >= 0 && y <= size.height) {
        double curX = 0; while (curX < size.width) { canvas.drawLine(Offset(curX, y), Offset(math.min(curX + 4, size.width), y), gridPaint); curX += 8; }
      }
    }

    // タッチされた位置のガイドライン（黄緑色の点線）
    if (touchedLevel != null && touchedLevel! >= minY && touchedLevel! <= maxY) {
      final y = size.height - ((touchedLevel! - minY) / range * size.height);
      final tp = Paint()
        ..color = Colors.lightGreen.shade700.withOpacity(0.6)
        ..strokeWidth = 1.0;
      
      double curX = 0;
      while (curX < size.width) {
        canvas.drawLine(Offset(curX, y), Offset(math.min(curX + 4, size.width), y), tp);
        curX += 8;
      }
    }

    // タッチされた日時の垂直ライン（黄色の点線）
    if (touchedDateTime != null && candles != null) {
      int idx = -1;
      for (int i = 0; i < candles!.length; i++) {
        if (candles![i].date == touchedDateTime) {
          idx = i;
          break;
        }
      }
      if (idx != -1) {
        final x = idx * cw + cw / 2;
        final tp = Paint()
          ..color = Colors.orange.shade700.withOpacity(0.6)
          ..strokeWidth = 1.0;
        
        double curY = 0;
        while (curY < size.height) {
          canvas.drawLine(Offset(x, curY), Offset(x, math.min(curY + 4, size.height)), tp);
          curY += 8;
        }
      }
    }

    if (histogram != null) {
      final histPaint = Paint()..style = PaintingStyle.fill;
      for (int i = 0; i < histogram!.length; i++) {
        final val = histogram![i]; if (val == null) continue;
        final x = i * cw + cw / 2; final y0 = size.height - ((0 - minY) / range * size.height); final y = size.height - ((val - minY) / range * size.height);
        histPaint.color = val >= 0 ? AppColors.rise.withOpacity(0.6) : AppColors.fall.withOpacity(0.6);
        canvas.drawRect(Rect.fromLTRB(x - cw * 0.4, math.min(y, y0), x + cw * 0.4, math.max(y, y0)), histPaint);
      }
    }
    _drawLine(canvas, size, values, lineColor, 1.5, range, cw);
    if (signalLine != null) _drawLine(canvas, size, signalLine!, AppColors.macdSignal, 1.2, range, cw);
  }
  void _drawLine(Canvas canvas, ui.Size size, List<double?> data, Color color, double width, double range, double cw) {
    final paint = Paint()..color = color..strokeWidth = width..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final path = Path(); bool started = false;
    for (int i = 0; i < data.length; i++) {
      final val = data[i]; if (val == null) { started = false; continue; }
      final x = i * cw + cw / 2; final y = size.height - ((val - minY) / range * size.height);
      if (!started) { path.moveTo(x, y); started = true; } else path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(covariant OscillatorPainter old) => true;
}

class CrosshairPainter extends CustomPainter {
  final Offset position; final Color color;
  CrosshairPainter({required this.position, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 1..style = PaintingStyle.stroke;
    final dp = Paint()..color = color.withAlpha(150)..strokeWidth = 1;
    double y = 0; while (y < size.height) { canvas.drawLine(Offset(position.dx, y), Offset(position.dx, y + 4), dp); y += 8; }
    double x = 0; while (x < size.width) { canvas.drawLine(Offset(x, position.dy), Offset(x + 4, position.dy), dp); x += 8; }
    canvas.drawCircle(position, 6, p); canvas.drawCircle(position, 3, Paint()..color = color);
  }
  @override bool shouldRepaint(covariant CrosshairPainter old) => position != old.position;
}
