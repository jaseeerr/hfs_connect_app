import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../services/auth_storage.dart';

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({super.key, required this.currentIndex});

  final int currentIndex;

  bool _isDashboardRoute(String? routeName) {
    return routeName == AppRoutes.dashboard || routeName == AppRoutes.home;
  }

  Future<void> _navigateToIndex(BuildContext context, int index) async {
    final String targetRoute;
    switch (index) {
      case 0:
        targetRoute = AppRoutes.dashboard;
        break;
      case 1:
        targetRoute = AppRoutes.roster;
        break;
      case 2:
        targetRoute = AppRoutes.guards;
        break;
      case 3:
        targetRoute = AppRoutes.clients;
        break;
      default:
        targetRoute = AppRoutes.dashboard;
    }

    final String? currentRoute = ModalRoute.of(context)?.settings.name;
    final bool isAlreadyOnTarget =
        currentRoute == targetRoute ||
        (_isDashboardRoute(currentRoute) && _isDashboardRoute(targetRoute));

    if (isAlreadyOnTarget) {
      return;
    }

    Navigator.pushNamed(context, targetRoute);
  }

  Future<void> _logout(BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context);
    final bool shouldLogout =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('Logout'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLogout) {
      return;
    }

    await AuthStorage.clear();
    if (!context.mounted) {
      return;
    }
    navigator.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  Future<void> _openMenuSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _logout(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required String label,
  }) {
    final bool selected = currentIndex == index;
    final Color activeColor = Theme.of(context).colorScheme.primary;
    final Color color = selected ? activeColor : Colors.black54;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToIndex(context, index),
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: Colors.white,
      elevation: 8,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      clipBehavior: Clip.none,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  _buildNavItem(
                    context: context,
                    index: 0,
                    icon: Icons.dashboard_outlined,
                    label: 'Dashboard',
                  ),
                  _buildNavItem(
                    context: context,
                    index: 1,
                    icon: Icons.calendar_month_outlined,
                    label: 'Roster',
                  ),
                  const SizedBox(width: 56),
                  _buildNavItem(
                    context: context,
                    index: 2,
                    icon: Icons.security_outlined,
                    label: 'Guards',
                  ),
                  _buildNavItem(
                    context: context,
                    index: 3,
                    icon: Icons.business_outlined,
                    label: 'Clients',
                  ),
                ],
              ),
              Positioned(
                top: -20,
                child: Material(
                  color: Theme.of(context).colorScheme.primary,
                  shape: const CircleBorder(),
                  elevation: 6,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _openMenuSheet(context),
                    child: const SizedBox(
                      width: 56,
                      height: 56,
                      child: Icon(Icons.menu, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
