import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/app_header.dart';

class OptionScreen extends StatelessWidget {
  final String symbol;
  const OptionScreen({super.key, required this.symbol});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppHeader(
        title: 'オプション - $symbol',
        showBackButton: true,
      ),
      body: const Center(
        child: Text('オプション設定画面 (準備中)', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
