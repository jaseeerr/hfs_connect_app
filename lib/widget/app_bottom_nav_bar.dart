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
                Theme(
                  data: Theme.of(
                    sheetContext,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                    childrenPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.summarize_outlined,
                      color: Colors.grey.shade600,
                    ),
                    title: Text(
                      'Report',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      _buildSubMenuItem(
                        context: sheetContext,
                        icon: Icons.fact_check_outlined,
                        label: 'Attendance',
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          Navigator.of(context).pushNamed(AppRoutes.attendance);
                        },
                        disabled: false,
                      ),
                      _buildSubMenuItem(
                        context: sheetContext,
                        icon: Icons.assignment_outlined,
                        label: 'AttendanceV2',
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          Navigator.of(
                            context,
                          ).pushNamed(AppRoutes.attendanceV2);
                        },
                        disabled: false,
                      ),
                    ],
                  ),
                ),
                Theme(
                  data: Theme.of(
                    sheetContext,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                    childrenPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Colors.grey.shade600,
                    ),
                    title: Text(
                      'Finance',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      _buildSubMenuItem(
                        context: sheetContext,
                        icon: Icons.receipt_long_outlined,
                        label: 'Invoice',
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          Navigator.of(
                            context,
                          ).pushNamed(AppRoutes.invoiceList);
                        },
                        disabled: false,
                      ),
                      _buildSubMenuItem(
                        context: sheetContext,
                        icon: Icons.description_outlined,
                        label: 'Receipt',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Not yet ready'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        disabled: true,
                      ),
                      _buildSubMenuItem(
                        context: sheetContext,
                        icon: Icons.payments_outlined,
                        label: 'Payment',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Not yet ready'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        disabled: true,
                      ),
                    ],
                  ),
                ),
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

  Widget _buildSubMenuItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool disabled,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 22, right: 6),
      visualDensity: VisualDensity.compact,
      leading: Icon(
        icon,
        color: disabled ? Colors.grey.shade500 : Colors.blueGrey.shade700,
        size: 20,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: disabled ? Colors.grey.shade600 : Colors.blueGrey.shade800,
          fontSize: 14,
          fontWeight: disabled ? FontWeight.w400 : FontWeight.w600,
        ),
      ),
      trailing: Text(
        disabled ? 'Disabled' : '',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
      ),
      onTap: onTap,
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
