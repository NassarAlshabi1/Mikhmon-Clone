import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../utils/validators.dart';
import '../../utils/network_scanner.dart';
import '../../providers/app_providers.dart';
import '../../services/models.dart';
import '../../l10n/translations.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portController = TextEditingController(text: '8728');

  final _ipFocusNode = FocusNode();
  final _portFocusNode = FocusNode();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isScanning = false;
  String? _errorMessage;
  bool _saveConnection = true;
  bool _useRestApi = false;

  static const Color primaryColor = Color(0xFF7B61FF);

  @override
  void dispose() {
    _ipController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    _ipFocusNode.dispose();
    _portFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
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
            const Text(
              'Connecting...',
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

  Future<void> _scanNetwork() async {
    setState(() => _isScanning = true);
    try {
      final results = await NetworkScanner.scanForRouters();
      if (!mounted) return;
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No MikroTik routers found on network')),
        );
        return;
      }
      _showRouterListDialog(results);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
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
                trailing: Icon(Icons.add_rounded, color: primaryColor),
                onTap: () {
                  Navigator.pop(ctx);
                  _ipController.text = r.ip;
                  _portController.text = r.port.toString();
                  setState(() => _useRestApi = r.isRestApi);
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

  Future<void> _login({RouterConnection? savedConnection}) async {
    if (!_formKey.currentState!.validate() && savedConnection == null) {
      return;
    }

    _showLoadingDialog();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String host, port, username, password;

      if (savedConnection != null) {
        host = savedConnection.host;
        port = savedConnection.port;
        username = savedConnection.username;
        password = _passwordController.text;
      } else {
        host = _ipController.text;
        port = _portController.text.trim().isEmpty
            ? '8728'
            : _portController.text.trim();
        username = _usernameController.text;
        password = _passwordController.text;
      }

      await ref.read(authStateProvider.notifier).login(
            host: host,
            port: port,
            username: username,
            password: password,
            rememberMe: false,
            useRest: _useRestApi,
          );

      if (_saveConnection && savedConnection == null) {
        final connections = ref.read(savedConnectionsProvider);
        final connectionsList = connections.value ?? [];

        final exists = connectionsList.any(
            (c) => c.host == host && c.port == port && c.username == username);

        if (!exists) {
          final name = '$username@${host}_$port';
          await ref.read(savedConnectionsProvider.notifier).addConnection(
                name: name,
                host: host,
                port: port,
                username: username,
              );
        }
      }

      if (mounted) {
        _hideLoadingDialog();
        if (mounted) {
          context.go('/main/dashboard');
        }
      }
    } catch (e) {
      if (mounted) {
        _hideLoadingDialog();
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: primaryColor,
      body: Stack(
        children: [
          SafeArea(
            child: SizedBox(
              width: double.infinity,
              height: size.height * 0.18,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => context.go('/'),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.router_rounded,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "ΩMMON",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppStrings.of(context).onboardingSubtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: size.height * 0.78,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(30),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      const Text(
                        "Add New Router",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Enter your Mikrotik router details",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 24),
                        if (_errorMessage != null)
                          Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Color(0xFFF43F5E),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!.replaceAll('Exception: ', ''),
                                        style: const TextStyle(
                                          color: Color(0xFFF43F5E),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () {
                                    setState(() => _errorMessage = null);
                                    _scanNetwork();
                                  },
                                  icon: Icon(Icons.wifi_find_rounded,
                                      size: 16, color: Colors.green[700]),
                                  label: Text(
                                    'Find Router on Network',
                                    style: TextStyle(
                                      color: Colors.green[700],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _ipController,
                              focusNode: _ipFocusNode,
                              onFieldSubmitted: (_) =>
                                  _portFocusNode.requestFocus(),
                              decoration: InputDecoration(
                                labelText: AppStrings.of(context).routerIP,
                                hintText: AppStrings.of(context).hostHint,
                                prefixIcon:
                                    const Icon(Icons.router_rounded, size: 20),
                                suffixIcon: IconButton(
                                  icon: _isScanning
                                      ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: primaryColor,
                                          ),
                                        )
                                      : Icon(Icons.wifi_find_rounded,
                                          color: primaryColor, size: 20),
                                  tooltip: 'Find Router',
                                  onPressed: _isScanning ? null : _scanNetwork,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: primaryColor),
                                ),
                              ),
                              validator: Validators.validateIP,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              controller: _portController,
                              focusNode: _portFocusNode,
                              decoration: InputDecoration(
                                labelText: AppStrings.of(context).port,
                                hintText: '8728',
                                prefixIcon: Tooltip(
                                  message: 'RouterOS API port (default: 8728)',
                                  child: Icon(Icons.info_outline_rounded,
                                      size: 18),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: primaryColor),
                                ),
                              ),
                              validator: Validators.validatePort,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _usernameController,
                        focusNode: _usernameFocusNode,
                        onFieldSubmitted: (_) =>
                            _passwordFocusNode.requestFocus(),
                        decoration: InputDecoration(
                          labelText: AppStrings.of(context).usernameField,
                          hintText: AppStrings.of(context).usernameHint,
                          prefixIcon:
                              const Icon(Icons.person_rounded, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: primaryColor),
                          ),
                        ),
                        validator: Validators.validateUsername,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocusNode,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: AppStrings.of(context).password,
                          hintText: AppStrings.of(context).optional,
                          prefixIcon: const Icon(Icons.lock_rounded, size: 20),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(
                                  () => _obscurePassword = !_obscurePassword);
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: primaryColor),
                          ),
                        ),
                        validator: Validators.validateOptionalPassword,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _useRestApi
                              ? const Color(0xFF10B981).withValues(alpha: 0.1)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _useRestApi
                                ? const Color(0xFF10B981)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _useRestApi
                                  ? Icons.check_circle
                                  : Icons.cloud_outlined,
                              color: _useRestApi
                                  ? const Color(0xFF10B981)
                                  : Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _useRestApi ? 'REST API (Active)' : 'Legacy API',
                                    style: TextStyle(
                                      color: Color(0xFF1E293B),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    _useRestApi
                                        ? 'HTTP-based (faster, ROS7 recommended)'
                                        : 'Socket-based (ROS6)',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _useRestApi,
                              onChanged: (value) {
                                setState(() => _useRestApi = value);
                                if (value) {
                                  _portController.text = '80';
                                } else {
                                  _portController.text = '8728';
                                }
                              },
                              activeThumbColor: const Color(0xFF10B981),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Checkbox(
                            value: _saveConnection,
                            onChanged: (value) {
                              setState(() => _saveConnection = value ?? false);
                            },
                            activeColor: primaryColor,
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(
                                  () => _saveConnection = !_saveConnection);
                            },
                            child: const Text(
                              'Save this router',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : () => _login(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.login_rounded),
                                    SizedBox(width: 8),
                                    Text(
                                      'Connect',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 16),
                      _buildSavedConnectionsSection(),
                      const SizedBox(height: 20),
                      Center(
                        child: TextButton(
                          onPressed: () => context.go('/'),
                          child: Text(
                            "BACK TO HOME",
                            style: TextStyle(
                              color: Colors.grey[500],
                              letterSpacing: 2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
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
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.flash_on_rounded,
                  size: 18,
                  color: Colors.amber,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Saved Routers',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                Text(
                  '${connections.length} saved',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...connections.map((conn) => _buildConnectionCard(conn)),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildConnectionCard(RouterConnection connection) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : () => _showQuickLoginDialog(connection),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryColor,
                        primaryColor.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      connection.name.isNotEmpty
                          ? connection.name[0].toUpperCase()
                          : 'R',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.name,
                        style: const TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${connection.host}:${connection.port}',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.login_rounded,
                  size: 18,
                  color: primaryColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showQuickLoginDialog(RouterConnection connection) {
    showDialog(
      context: context,
      builder: (dialogContext) => _QuickLoginDialog(
        connection: connection,
        onConnect: (password) {
          _passwordController.text = password;
          _login(savedConnection: connection);
        },
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
              labelText: AppStrings.of(context).password,
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
          child: Text(AppStrings.of(context).cancel,
              style: TextStyle(color: Colors.grey[600])),
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
        Text(text, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
      ],
    );
  }
}
