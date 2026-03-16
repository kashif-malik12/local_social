import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Transparent shell that hosts the four persistent tab branches.
/// Each branch screen manages its own Scaffold + GlobalBottomNav.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) => navigationShell;
}
