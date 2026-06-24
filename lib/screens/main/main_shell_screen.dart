import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:convex_bottom_bar/convex_bottom_bar.dart';
import '../../theme/app_theme.dart';
import '../../widgets/global_search.dart';
import '../../widgets/router_switcher.dart';
import '../../l10n/translations.dart';
import '../../services/onboarding_service.dart';
import '../../services/cache_service.dart';
import '../../providers/app_providers.dart';

final isDemoModeProvider = FutureProvider<bool>((ref) async {
  return await OnboardingService.isDemoMode();
});

class MainShellScreen extends ConsumerStatefulWidget {
  final Widget child;

  const MainShellScreen({super.key, required this.child});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  static const _routes = [
    '/main/dashboard',
    '/main/users',
    '/main/profiles',
    '/main/hosts',
    '/main/settings',
    '/main/feedback',
  ];

  int _getTabFromPath(String path) {
    if (path == '/main/dashboard' || path.startsWith('/main/dashboard')) {
      return 0;
    }
    if (path == '/main/users' ||
        path.startsWith('/main/users') ||
        path.startsWith('/main/vouchers')) {
      return 1;
    }
    if (path == '/main/profiles' || path.startsWith('/main/profiles')) {
      return 2;
    }
    if (path == '/main/hosts' || path.startsWith('/main/hosts')) {
      return 3;
    }
    if (path == '/main/settings' || path.startsWith('/main/settings')) {
      return 4;
    }
    if (path == '/main/feedback' || path.startsWith('/main/feedback')) {
      return 5;
    }
    return 0;
  }

  void _navigateToTab(int index) {
    final currentPath = GoRouterState.of(context).uri.path;
    final targetPath = _routes[index];
    if (!currentPath.contains(targetPath)) {
      context.go(targetPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Always get current tab from route
    final location = GoRouterState.of(context).uri.path;
    final computedTab = _getTabFromPath(location);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (computedTab != 0) {
          _navigateToTab(0);
        }
      },
      child: Scaffold(
        backgroundColor: context.appBackground,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: _buildAppBar(context),
        ),
        body: Column(
          children: [
            // Demo mode banner
            Consumer(
              builder: (context, ref, _) {
                final isDemoAsync = ref.watch(isDemoModeProvider);
                return isDemoAsync.when(
                  data: (isDemo) {
                    if (!isDemo) return const SizedBox.shrink();
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      color: Colors.orange.withValues(alpha: 0.9),
                      child: Row(
                        children: [
                          Icon(Icons.science_rounded,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Demo Mode - Data is simulated',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _showLogoutDialog(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('Exit',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollUpdateNotification) {
                    if (notification.scrollDelta != null &&
                        notification.scrollDelta! > 0 &&
                        notification.metrics.pixels == 0) {
                      showGlobalSearch(context);
                      return true;
                    }
                  }
                  return false;
                },
                child: widget.child,
              ),
            ),
          ],
        ),
        bottomNavigationBar: ConvexAppBar(
          key: ValueKey('nav_$computedTab'),
          style: TabStyle.reactCircle,
          backgroundColor: context.appSurface,
          activeColor: context.appPrimary,
          color: context.appOnSurface.withValues(alpha: 0.5),
          initialActiveIndex: computedTab,
          height: 65,
          top: -30,
          curveSize: 90,
          onTap: (index) {
            _navigateToTab(index);
          },
          items: [
            TabItem(icon: Icons.dashboard_rounded),
            TabItem(icon: Icons.people_rounded),
            TabItem(icon: Icons.add_rounded),
            TabItem(icon: Icons.router_rounded),
            TabItem(icon: Icons.settings_rounded),
            TabItem(icon: Icons.feedback_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: context.appSurface,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Center(
          child: Text(
            'Ω',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: context.appPrimary,
            ),
          ),
        ),
      ),
      title: Consumer(
        builder: (context, ref, _) {
          final savedConnectionsAsync = ref.watch(savedConnectionsProvider);
          return savedConnectionsAsync.when(
            data: (connections) {
              if (connections.length <= 1) {
                return Text(
                  'ΩMMON',
                  style: TextStyle(
                    color: context.appOnSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                );
              }
              return const RouterSwitcher();
            },
            loading: () => Text(
              'ΩMMON',
              style: TextStyle(
                color: context.appOnSurface,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            error: (_, __) => Text(
              'ΩMMON',
              style: TextStyle(
                color: context.appOnSurface,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          );
        },
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.search, color: context.appOnSurface),
          onPressed: () => showGlobalSearch(context),
          tooltip: 'Search',
        ),
        IconButton(
          icon: const Icon(Icons.monitor_heart_outlined),
          onPressed: () => context.go('/main/command-center'),
          tooltip: 'Command Center',
        ),
      ],
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Exit Demo Mode?'),
        content: Text('You will be redirected to the login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await OnboardingService.setDemoMode(false);
              await OnboardingService.clearAll();
              // Clear demo data from cache
              final cache = CacheService();
              await cache.clearAllDemoData();
              if (context.mounted) {
                context.go('/');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text('Exit Demo'),
          ),
        ],
      ),
    );
  }
}
