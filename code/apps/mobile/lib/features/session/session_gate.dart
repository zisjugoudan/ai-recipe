import 'package:flutter/material.dart';

import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../domain/access/app_session.dart';
import '../../domain/access/onboarding_state.dart';
import '../../shared/widgets/app_states.dart';
import '../shell/app_shell.dart';
import 'welcome_page.dart';

class SessionGate extends StatefulWidget {
  const SessionGate({super.key, required this.backend});

  final AiRecipeBackendFacade backend;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  AppSession? _session;
  Object? _error;
  bool _loading = true;
  OnboardingState? _onboardingState;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>(<Future<Object>>[
        widget.backend.loadSession(),
        widget.backend.loadOnboardingState(),
      ]);
      final session = results[0] as AppSession;
      final onboardingState = results[1] as OnboardingState;
      if (!mounted) return;
      setState(() {
        _session = session;
        _onboardingState = onboardingState;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _continueAsGuest() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await widget.backend.continueAsGuest();
      final onboardingState = await widget.backend.completeOnboarding();
      if (!mounted) return;
      setState(() {
        _session = session;
        _onboardingState = onboardingState;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _showLoginUnavailable() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('服务器登录暂未接入，现在可以先使用游客模式。')));
  }

  void _returnToWelcome(AppSession session) {
    setState(() {
      _session = session;
      _onboardingState = const OnboardingState.pending();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _session == null) {
      return const Scaffold(body: AppLoadingState(label: '正在读取本地会话…'));
    }
    final session = _session;
    final onboardingState = _onboardingState;
    if (session != null &&
        (session.isAuthenticated || onboardingState?.isCompleted == true)) {
      return AppShell(
        backend: widget.backend,
        session: session,
        onSignedOut: _returnToWelcome,
      );
    }
    return WelcomePage(
      busy: _loading,
      errorMessage: _error == null ? null : '本地会话暂时无法读取，请重试。',
      onContinueAsGuest: _continueAsGuest,
      onLogin: _showLoginUnavailable,
      onRetry: _load,
    );
  }
}
