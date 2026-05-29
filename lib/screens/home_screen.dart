import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/device_approval_provider.dart';
import '../utils/constants.dart';
import '../widgets/approval_overlay.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'device_manager_page.dart';
import '../services/device_navigation_bridge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _titles = ['Dashboard', 'Profile', 'Devices'];

  @override
  void initState() {
    super.initState();
    DeviceNavigationBridge.openTab = (i) {
      if (!mounted) return;
      setState(() => _index = i.clamp(0, 2));
    };
  }

  Widget _tabBody(int index) {
    switch (index) {
      case 1:
        return const ProfileScreen();
      case 2:
        return const DeviceManagerPage();
      case 0:
      default:
        return const DashboardScreen();
    }
  }

  @override
  void dispose() {
    if (DeviceNavigationBridge.openTab != null) {
      DeviceNavigationBridge.openTab = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final dev = context.watch<DeviceApprovalProvider>();
    final locked = dev.isAwaitingApproval || dev.registrationRejected;
    final maintenance = dev.serverMaintenance && dev.isAwaitingApproval;

    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
          appBar: locked
              ? null
              : AppBar(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  title: Text(_titles[_index]),
                  actions: [
                    if (user != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Center(
                          child: Text(
                            user.name.isNotEmpty
                                ? user.name.split(' ').first
                                : 'User',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
          body: locked ? const SizedBox.shrink() : _tabBody(_index),
          bottomNavigationBar: locked
              ? null
              : BottomNavigationBar(
                  currentIndex: _index,
                  onTap: (i) => setState(() => _index = i),
                  selectedItemColor: AppColors.primary,
                  unselectedItemColor: Colors.grey,
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.dashboard_outlined),
                      activeIcon: Icon(Icons.dashboard),
                      label: 'Dashboard',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.person_outline),
                      activeIcon: Icon(Icons.person),
                      label: 'Profile',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.devices_outlined),
                      activeIcon: Icon(Icons.devices),
                      label: 'Devices',
                    ),
                  ],
                ),
        ),
        if (dev.isAwaitingApproval)
          ApprovalOverlay(
            title: 'Waiting for Parent Approval...',
            message:
                'Ask the account owner to open the Devices tab on the parent phone and tap Approve.',
            maintenanceMessage:
                maintenance ? (dev.statusMessage ?? 'Server Under Maintenance') : null,
            refreshing: dev.statusRefreshing,
            onRefresh: () => dev.refreshStatusNow(),
          ),
        if (dev.registrationRejected)
          ApprovalOverlay(
            title: 'Device registration rejected',
            message: 'The parent device rejected this login.',
            footer: FilledButton(
              onPressed: () => context.read<AuthProvider>().signOut(),
              child: const Text('Sign out'),
            ),
          ),
      ],
    );
  }
}
