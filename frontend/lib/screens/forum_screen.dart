import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/app_header.dart';

class ForumScreen extends StatelessWidget {
  final String symbol;
  const ForumScreen({super.key, required this.symbol});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppHeader(
        title: '掲示板 - $symbol',
        showBackButton: true,
      ),
      body: const Center(
        child: Text('投資家掲示板 (準備中)', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
