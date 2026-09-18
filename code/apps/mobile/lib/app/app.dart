import 'dart:async';

import 'package:flutter/material.dart';

import '../application/backend/ai_recipe_backend_facade.dart';
import '../data/llm_config_repository.dart';
import '../features/llm_settings/llm_settings_page.dart';
import '../features/session/session_gate.dart';
import 'ai_recipe_backend_composition_root.dart';
import 'app_theme.dart';
import 'ocr_model_catalog.dart';

class AiRecipeApp extends StatefulWidget {
  const AiRecipeApp({
    super.key,
    this.backend,
    this.compositionRootFactory,
    this.repository,
  });

  final AiRecipeBackendFacade? backend;
  final AiRecipeBackendCompositionRoot Function()? compositionRootFactory;

  /// 保留给早期 LLM 设置页测试与独立调试入口；仅作为组合根依赖注入。
  final LlmConfigRepository? repository;

  @override
  State<AiRecipeApp> createState() => _AiRecipeAppState();
}

class _AiRecipeAppState extends State<AiRecipeApp> {
  AiRecipeBackendCompositionRoot? _ownedRoot;
  AiRecipeBackendFacade? _backend;
  Object? _startupError;

  @override
  void initState() {
    super.initState();
    if (widget.backend != null) {
      _backend = widget.backend;
      return;
    }
    try {
      _ownedRoot =
          widget.compositionRootFactory?.call() ??
          AiRecipeBackendCompositionRoot.device(
            llmConfigRepository: widget.repository,
            // 允许从官方 ModelScope 仓库下载 PP-OCRv5 mobile 模型（OCR-003）。
            trustedOcrModelHosts: ocrTrustedModelHosts,
          );
      _backend = _ownedRoot!.backend;
    } catch (error) {
      _startupError = error;
    }
  }

  @override
  void dispose() {
    final root = _ownedRoot;
    if (root != null) unawaited(root.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = _backend;
    return MaterialApp(
      title: '巴食',
      debugShowCheckedModeBanner: false,
      theme: buildAiRecipeTheme(),
      // 全局纸张背景：米白渐变 + 8px 圆点纹理（prototype.css body）。
      builder: (context, child) => _PixelPaperBackground(child: child ?? const SizedBox.shrink()),
      home: backend != null
          ? widget.repository != null
                ? LlmSettingsPage(backend: backend)
                : SessionGate(backend: backend)
          : _StartupErrorPage(error: _startupError),
    );
  }
}

/// 纸张背景：#F3F1E9（--paper）+ 8px 网格圆点（prototype.css body）。
class _PixelPaperBackground extends StatelessWidget {
  const _PixelPaperBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF3F1E9),
      ),
      child: CustomPaint(
        painter: const _DotGridPainter(),
        child: child,
      ),
    );
  }
}

/// 8px 网格上的 1px 圆点（rgba(54,64,58,.05)）。
class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  static const double _spacing = 8;
  static const Color _dot = Color(0x0D36403A); // 5% 墨色

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _dot;
    for (var y = _spacing / 2; y < size.height; y += _spacing) {
      for (var x = _spacing / 2; x < size.width; x += _spacing) {
        // 原型 radial-gradient(rgba(54,64,58,.05) 1px, ...)：1px 圆点。
        canvas.drawCircle(Offset(x, y), 0.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StartupErrorPage extends StatelessWidget {
  const _StartupErrorPage({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline_rounded, size: 48),
                const SizedBox(height: 16),
                Text(
                  '本地数据服务启动失败',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('请重新启动应用；你的本地数据不会因此被上传。'),
                if (error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    error.runtimeType.toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
