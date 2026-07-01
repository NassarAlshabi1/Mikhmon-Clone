import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../utils/network_scanner.dart';
import '../../services/onboarding_service.dart';
import '../../providers/app_providers.dart';
import '../../services/models.dart';
import '../../l10n/translations.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  static const Color primaryColor = Color(0xFF7B61FF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OnboardingService.showWhatsNewIfNeeded(context);
    });
  }

  Future<void> _navigateAfterLogin() async {
    final setupDone = await OnboardingService.isSetupCompleted();
    if (mounted) {
      if (setupDone) {
        context.go('/main/dashboard');
      } else {
        context.go('/setup');
      }
    }
  }

  Future<void> _scanNetwork() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        content: Row(
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
            const SizedBox(width: 16),
            const Text('Scanning network...',
                style: TextStyle(color: Color(0xFF1E293B))),
          ],
        ),
      ),
    );
    try {
      final results = await NetworkScanner.scanForRouters();
      if (!mounted) return;
      Navigator.of(context).pop();
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No MikroTik routers found on network')),
        );
        return;
      }
      _showRouterListDialog(results);
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    }
  }

  void _showRouterListDialog(List<NetworkScannerResult> results) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Icon(Icons.wifi_tethering_rounded, size: 22, color: primaryColor),
            const SizedBox(width: 8),
            Text(
              'Found ${results.length} Router${results.length > 1 ? 's' : ''}',
              style: const TextStyle(color: Color(0xFF1E293B), fontSize: 18),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: results.length,
            itemBuilder: (_, i) {
              final r = results[i];
              return ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.router_rounded, color: primaryColor, size: 22),
                ),
                title: Text(r.ip, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Port ${r.port}${r.isRestApi ? ' (REST)' : ' (API)'}'),
                trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/login');
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: Colors.grey[600])),
          ),
        ],
      ),
    );
  }

  Future<void> _quickLogin(RouterConnection connection, String password) async {
    _showLoadingDialog();

    try {
      await ref.read(authStateProvider.notifier).login(
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: password,
            rememberMe: false,
          );

      if (mounted) {
        _hideLoadingDialog();
        _navigateAfterLogin();
      }
    } catch (e) {
      if (mounted) {
        _hideLoadingDialog();
        _showErrorDialog(e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingContext) => AlertDialog(
        backgroundColor: Colors.white,
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
            const SizedBox(width: 16),
            Text(
              AppStrings.of(context).connecting,
              style: TextStyle(color: Color(0xFF1E293B)),
            ),
          ],
        ),
      ),
    );
  }

  void _hideLoadingDialog() {
    Navigator.of(context).pop();
  }

  void _showErrorDialog(String message, {VoidCallback? onRetry}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFF43F5E)),
            const SizedBox(width: 12),
            Text(
              AppStrings.of(context).connectionFailed,
              style: const TextStyle(color: Color(0xFF1E293B)),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (onRetry != null) {
                Future.delayed(const Duration(milliseconds: 100), () {
                  _scanNetwork();
                });
              }
            },
            child: Text('Find Router',
                style: TextStyle(color: Colors.green[700])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
            ),
            child: Text(AppStrings.of(context).ok),
          ),
        ],
      ),
    );
  }

  void _showQuickLoginDialog(RouterConnection connection) {
    showDialog(
      context: context,
      builder: (dialogContext) => _QuickLoginDialog(
        connection: connection,
        onConnect: (password) => _quickLogin(connection, password),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: primaryColor,
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(top: topPadding + 16, bottom: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.router_rounded,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "\u03A9MMON",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.of(context).onboardingSubtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(30, 30, 30, bottomPadding + 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.of(context).welcomeBack,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppStrings.of(context).selectRouter,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Saved connections
                      _buildSavedConnectionsSection(),
                      const SizedBox(height: 12),
                      // Connect to new router button
                      GestureDetector(
                        onTap: () => context.push('/login'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: primaryColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_rounded,
                                  color: primaryColor, size: 22),
                              const SizedBox(width: 12),
                              Text(
                                AppStrings.of(context).connectNewRouter,
                                style: TextStyle(
                                  color: primaryColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _scanNetwork(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.wifi_find_rounded,
                                  color: Colors.green, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                'Find Router on Network',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Consumer(
                        builder: (context, ref, _) {
                          final service = ref.watch(routerOSServiceProvider);
                          if (!service.isConnected) {
                            return const SizedBox.shrink();
                          }
                          return Center(
                            child: TextButton(
                              onPressed: () => context.go('/main/dashboard'),
                              child: Text(
                                AppStrings.of(context).enterApp,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedConnectionsSection() {
    final connectionsAsync = ref.watch(savedConnectionsProvider);

    return connectionsAsync.when(
      data: (connections) {
        if (connections.isEmpty) {
          return _buildEmptyConnections();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.flash_on_rounded,
                  size: 16,
                  color: Colors.amber,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    AppStrings.of(context).myRouters,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${connections.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: connections.length,
                itemBuilder: (context, index) {
                  return _buildConnectionTile(connections[index]);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _buildEmptyConnections(),
    );
  }

  Widget _buildEmptyConnections() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFE2E8F0),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_tethering_off_rounded,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.of(context).noRoutersSaved,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.of(context).tapToConnectFirstRouter,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionTile(RouterConnection connection) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showQuickLoginDialog(connection),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryColor,
                        primaryColor.withValues(alpha: 0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      connection.name.isNotEmpty
                          ? connection.name[0].toUpperCase()
                          : 'R',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.name,
                        style: const TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.dns_rounded,
                            size: 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${connection.host}:${connection.port}',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.person_rounded,
                            size: 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 2),
                          Text(
                            connection.username,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.login_rounded,
                    size: 20,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickLoginDialog extends StatefulWidget {
  final RouterConnection connection;
  final Function(String password) onConnect;

  const _QuickLoginDialog({
    required this.connection,
    required this.onConnect,
  });

  @override
  State<_QuickLoginDialog> createState() => _QuickLoginDialogState();
}

class _QuickLoginDialogState extends State<_QuickLoginDialog> {
  late final TextEditingController _passwordController;
  static const Color primaryColor = Color(0xFF7B61FF);

  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
        'Connect to ${widget.connection.name}',
        style: const TextStyle(
          color: Color(0xFF1E293B),
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(Icons.dns_rounded,
              '${widget.connection.host}:${widget.connection.port}'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.person_rounded, widget.connection.username),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              hintText: 'Enter router password',
              prefixIcon: const Icon(Icons.lock_rounded, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: primaryColor),
              ),
            ),
            autofocus: true,
            onSubmitted: (value) {
              Navigator.pop(context);
              widget.onConnect(value);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onConnect(_passwordController.text);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
          child: Text(AppStrings.of(context).connect),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
      ],
    );
  }
}
