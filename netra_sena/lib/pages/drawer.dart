// drawer.dart
import 'package:flutter/material.dart';

typedef DrawerSelectCallback = void Function(BuildContext context, int index, String label);

class AppDrawer extends StatelessWidget {
  final String userName;
  final String userEmail;
  final String role;
  final int selectedIndex;
  final bool isActive;
  final DrawerSelectCallback onSelect;

  const AppDrawer({
    super.key,
    required this.userName,
    required this.userEmail,
    required this.role,
    required this.selectedIndex,
    this.isActive = true,
    required this.onSelect,
  });

  // Match colors from your home page
  static const Color _drawerBlue = Color(0xFF162170);
  static const Color _drawerTopBand = Color(0xFF1A2A83);
  static const Color _selectedBand = Color(0xFF0E1A55);

  Widget _buildDrawerTile(
      BuildContext context, {
        required IconData icon,
        required String title,
        required bool selected,
        required VoidCallback onTap,
      }) {
    return Container(
      color: selected ? _selectedBand : Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: Icon(icon, color: Colors.white, size: 22),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          maxLines: 2,
          softWrap: true,
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Define the list of tiles to display based on the user's role
    final List<Widget> drawerTiles = [];

    // All users have access to Home
    drawerTiles.add(_buildDrawerTile(context, icon: Icons.home, title: 'Home', selected: selectedIndex == 0, onTap: () => onSelect(context, 0, 'Home')));

    // Admin and Super Admin roles get these pages
    if (role == 'admin' || role == 'superadmin') {
      drawerTiles.addAll([
        _buildDrawerTile(context, icon: Icons.directions_car, title: 'Vehicle Logs', selected: selectedIndex == 2, onTap: () => onSelect(context, 2, 'Vehicle Logs')),
        _buildDrawerTile(context, icon: Icons.warning_amber_rounded, title: 'Alert Logs', selected: selectedIndex == 3, onTap: () => onSelect(context, 3, 'Alert Logs')),
        _buildDrawerTile(context, icon: Icons.do_not_disturb_on, title: 'Blacklist Management', selected: selectedIndex == 4, onTap: () => onSelect(context, 4, 'Blacklist Management')),
      ]);
    }

    // Only Super Admin gets the User Management page
    if (role == 'superadmin') {
      drawerTiles.add(_buildDrawerTile(context, icon: Icons.group, title: 'User Management', selected: selectedIndex == 1, onTap: () => onSelect(context, 1, 'User Management')));
    }

    // All users have access to Settings
    drawerTiles.addAll([
      const Divider(height: 20, color: Colors.white24, indent: 16, endIndent: 16),
      _buildDrawerTile(context, icon: Icons.settings, title: 'Settings', selected: selectedIndex == 5, onTap: () => onSelect(context, 5, 'Settings')),
    ]);

    return Drawer(
      child: Container(
        color: _drawerBlue,
        child: Column(
          children: [
            Container(height: MediaQuery.of(context).padding.top, color: _drawerTopBand),
            Container(
              color: _drawerBlue,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: SafeArea(
                bottom: false,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.white,
                            child: Icon(Icons.person, size: 34, color: _drawerTopBand),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            userName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            userEmail,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _drawerTopBand.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: isActive ? Colors.greenAccent : Colors.redAccent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (isActive ? Colors.greenAccent : Colors.redAccent).withOpacity(0.6),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isActive ? 'Active' : 'Inactive',
                            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 20, color: Colors.white24, indent: 16, endIndent: 16),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: drawerTiles,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // MoRTH logo on app drawer
                  // SizedBox(
                  //   height: 56,
                  //   width: double.infinity,
                  //   child: Align(
                  //     alignment: Alignment.center,
                  //     child: Image.asset(
                  //       'assets/MoRTH.png',
                  //       fit: BoxFit.contain,
                  //     ),
                  //   ),
                  // ),
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.center,child: Text(
                    'Version 1.0.0',
                    style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
                  ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}