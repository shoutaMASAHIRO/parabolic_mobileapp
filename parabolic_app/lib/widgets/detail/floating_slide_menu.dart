import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../screens/option_screen.dart';
import '../../screens/analysis_screen.dart';
import '../../screens/news_screen.dart';
import '../../screens/forum_screen.dart';

class FloatingSlideMenu extends StatefulWidget {
  final String symbol;
  const FloatingSlideMenu({super.key, required this.symbol});

  @override
  State<FloatingSlideMenu> createState() => _FloatingSlideMenuState();
}

class _FloatingSlideMenuState extends State<FloatingSlideMenu> {
  bool _isExpanded = false;

  void _navigateTo(Widget screen) {
    setState(() => _isExpanded = false);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      bottom: 90, 
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              width: 56, 
              height: 56,
              decoration: BoxDecoration(
                color: (_isExpanded ? AppColors.error : AppColors.surface).withOpacity(0.6),
                shape: BoxShape.circle,
                border: Border.all(
                  color: (_isExpanded ? AppColors.error : AppColors.primaryLight).withOpacity(0.6), 
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isExpanded ? AppColors.error : AppColors.primary).withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                _isExpanded ? Icons.close : Icons.menu_open,
                color: _isExpanded ? AppColors.error : Colors.white,
                size: 28,
              ),
            ),
          ),
          
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            margin: EdgeInsets.only(left: _isExpanded ? 16 : 0),
            height: 56, 
            width: _isExpanded ? 280 : 0, 
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.6),
              borderRadius: BorderRadius.circular(28),
              border: _isExpanded 
                  ? Border.all(color: AppColors.primaryLight.withOpacity(0.6), width: 1.5) 
                  : null,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _buildMenuItem(
                      Icons.settings_outlined, 
                      'オプション', 
                      () => _navigateTo(OptionScreen(symbol: widget.symbol))
                    ),
                    _buildDivider(),
                    _buildMenuItem(
                      Icons.analytics_outlined, 
                      '分析', 
                      () => _navigateTo(AnalysisScreen(symbol: widget.symbol))
                    ),
                    _buildDivider(),
                    _buildMenuItem(
                      Icons.newspaper_outlined, 
                      'ニュース', 
                      () => _navigateTo(NewsScreen(symbol: widget.symbol))
                    ),
                    _buildDivider(),
                    _buildMenuItem(
                      Icons.forum_outlined, 
                      '掲示板', 
                      () => _navigateTo(ForumScreen(symbol: widget.symbol))
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

  Widget _buildMenuItem(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 10, 
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withOpacity(0.1),
    );
  }
}
