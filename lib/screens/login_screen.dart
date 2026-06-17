import 'dart:async';

import 'package:flutter/material.dart';

import '../app_strings.dart';
import '../models.dart';
import 'shared/paper_background.dart';

typedef LoginHandler = Future<void> Function(
  AppAccount account,
  String password,
);

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onLogin,
    this.accounts = appAccounts,
  });

  final LoginHandler onLogin;
  final List<AppAccount> accounts;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _passwordController = TextEditingController();
  AppAccount? _selectedAccount;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: PaperBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final account in widget.accounts) ...[
                      _AccountChoice(
                        account: account,
                        isSelected: account == _selectedAccount,
                        onPressed: _isSubmitting
                            ? null
                            : () => _selectAccount(account),
                      ),
                      if (account != widget.accounts.last)
                        const SizedBox(height: 12),
                    ],
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _selectedAccount == null
                          ? const SizedBox.shrink()
                          : Padding(
                              key: ValueKey(_selectedAccount!.id),
                              padding: const EdgeInsets.only(top: 20),
                              child: Column(
                                children: [
                                  TextField(
                                    key: const ValueKey('login-password-field'),
                                    controller: _passwordController,
                                    enabled: !_isSubmitting,
                                    obscureText: true,
                                    textInputAction: TextInputAction.done,
                                    decoration: InputDecoration(
                                      labelText: strings.password,
                                      errorText: _errorMessage,
                                    ),
                                    onSubmitted: (_) =>
                                        unawaited(_submitLogin()),
                                  ),
                                  const SizedBox(height: 14),
                                  FilledButton(
                                    key: const ValueKey('login-submit-button'),
                                    onPressed: _isSubmitting
                                        ? null
                                        : () => unawaited(_submitLogin()),
                                    child: _isSubmitting
                                        ? SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color:
                                                  theme.colorScheme.onPrimary,
                                            ),
                                          )
                                        : Text(strings.login),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectAccount(AppAccount account) {
    setState(() {
      _selectedAccount = account;
      _errorMessage = null;
      _passwordController.clear();
    });
  }

  Future<void> _submitLogin() async {
    final account = _selectedAccount;
    if (account == null || _isSubmitting) return;

    final strings = AppStrings.of(context);
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = strings.passwordRequired);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.onLogin(account, password);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = strings.loginFailed);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _AccountChoice extends StatelessWidget {
  const _AccountChoice({
    required this.account,
    required this.isSelected,
    required this.onPressed,
  });

  final AppAccount account;
  final bool isSelected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      height: 64,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor:
              isSelected ? theme.colorScheme.surface : Colors.transparent,
          foregroundColor: theme.colorScheme.onSurface,
          side: BorderSide(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          account.label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
