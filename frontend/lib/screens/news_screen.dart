import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/app_header.dart';

class NewsScreen extends StatelessWidget {
  final String symbol;
  const NewsScreen({super.key, required this.symbol});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppHeader(
        title: 'ニュース - $symbol',
        showBackButton: true,
      ),
      body: const Center(
        child: Text('最新ニュース一覧 (準備中)', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
