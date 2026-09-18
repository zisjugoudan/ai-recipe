import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../application/settings/local_app_settings_use_cases.dart';
import '../../domain/access/app_session.dart';
import '../../domain/ocr/ocr_model_manifest.dart';
import '../../domain/ocr/ocr_model_package.dart';
import '../../domain/ocr/ocr_models.dart';
import '../../domain/settings/local_app_settings.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';
import '../importing/import_image_picker.dart';

class OcrSettingsPage extends StatefulWidget {
  const OcrSettingsPage({
    super.key,
    required this.backend,
    required this.session,
    this.packageId = 'paddleocr-ppocrv5-mobile-zh',
    this.installManifest,
  });

  final AiRecipeBackendFacade backend;
  final AppSession session;
  final String packageId;

  /// 正式模型清单尚未验收前保持为空，页面不会构造虚假下载地址或校验值。
  final OcrModelManifest? installManifest;

  @override
  State<OcrSettingsPage> createState() => _OcrSettingsPageState();
}

class _OcrSettingsPageState extends State<OcrSettingsPage> {
  OcrModelPackageStatus? _status;
  LocalAppSettings? _localSettings;
  OcrModelInstallCancellationToken? _cancellationToken;
  final _imagePicker = DeviceImportImagePicker();
  bool _loading = true;
  bool _busy = false;
  String? _errorMessage;

  /// 图片识别方式（识图引擎，IMAGE-001）。
  ImageRecognitionMode _imageRecognitionMode = ImageRecognitionMode.auto;
  bool _savingMode = false;
  String? _modeMessage;
  bool _modeMessageIsError = false;

  /// 测试 OCR：是否正在识别。
  bool _testing = false;

  /// 测试 OCR 的识别结果。
  OcrTestResult? _testResult;

  /// 测试 OCR 的错误提示。
  String? _testError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await widget.backend.recoverLocalOcrModelInstallation();
      final results = await Future.wait<Object>(<Future<Object>>[
        widget.backend.getLocalOcrModelStatus(widget.packageId),
        widget.backend.loadLocalSettings(),
      ]);
      if (!mounted) return;
      setState(() {
        _status = results[0] as OcrModelPackageStatus;
        _localSettings = results[1] as LocalAppSettings;
        _imageRecognitionMode = _localSettings!.imageRecognitionMode;
        _loading = false;
      });
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'OCR 状态暂时无法读取，请稍后重试。';
      });
    }
  }

  Future<void> _install() async {
    final manifest = widget.installManifest;
    if (manifest == null || _busy) return;
    final cancellationToken = OcrModelInstallCancellationToken();
    setState(() {
      _busy = true;
      _errorMessage = null;
      _cancellationToken = cancellationToken;
    });
    try {
      final status = await widget.backend.installLocalOcrModel(
        manifest,
        cancellationToken: cancellationToken,
        onStatusChanged: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      if (!mounted) return;
      setState(() => _status = status);
      _showMessage('本地 OCR 模型已安装。');
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      if (error.code != AiRecipeBackendErrorCode.operationCancelled) {
        setState(() => _errorMessage = error.message);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = '本地 OCR 模型安装失败，请稍后重试。');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancellationToken = null;
        });
      }
    }
  }

  void _cancelInstall() => _cancellationToken?.cancel();

  Future<void> _delete() async {
    final confirmed = await showPixelConfirm(
      context: context,
      title: '删除本地 OCR 模型？',
      message: '删除后图片文字识别将不可用，菜谱和原始图片不会被删除。',
      confirmLabel: '删除模型',
      confirmColor: AppColors.red,
      confirmKey: const Key('confirmDeleteOcrModelButton'),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await widget.backend.deleteLocalOcrModel(widget.packageId);
      final status = await widget.backend.getLocalOcrModelStatus(
        widget.packageId,
      );
      if (!mounted) return;
      setState(() => _status = status);
      _showMessage('本地 OCR 模型已删除。');
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = '本地 OCR 模型暂时无法删除。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 保存图片识别方式（识图引擎，IMAGE-001）。
  Future<void> _saveImageRecognitionMode() async {
    if (_savingMode) return;
    setState(() {
      _savingMode = true;
      _modeMessage = null;
    });
    try {
      final settings = await widget.backend.saveLocalSettings(
        LocalAppSettingsInput(
          recordRecipeHistory: _localSettings?.recordRecipeHistory ?? true,
          allowTextUpload: _localSettings?.allowTextUpload ?? true,
          allowImageUpload: _localSettings?.allowImageUpload ?? false,
          allowVideoUpload: _localSettings?.allowVideoUpload ?? false,
          imageRecognitionMode: _imageRecognitionMode,
        ),
      );
      if (!mounted) return;
      setState(() {
        _localSettings = settings;
        _savingMode = false;
        _modeMessage = '图片识别方式已保存。';
        _modeMessageIsError = false;
      });
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _savingMode = false;
        _modeMessage = error.message;
        _modeMessageIsError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingMode = false;
        _modeMessage = '图片识别方式暂时无法保存，请稍后重试。';
        _modeMessageIsError = true;
      });
    }
  }

  /// 测试 OCR：选择一张本地图片 → 本地识别 → 展示文本与耗时。
  ///
  /// 入口常驻；本地 OCR 模型未就绪时不打开图片选择器，改为中文引导。
  Future<void> _runOcrTest() async {
    if (_testing || _busy) return;
    final status = _status;
    if (status == null || status.state != OcrModelInstallState.installed) {
      final guide = switch (status?.state) {
        OcrModelInstallState.downloading ||
        OcrModelInstallState.verifying =>
          '本地 OCR 模型还在下载/校验中，完成后即可测试。',
        OcrModelInstallState.failed =>
          '本地 OCR 模型安装失败，请先重试下载后再测试。',
        _ => '请先在“模型包”中下载并安装本地 OCR 模型后再测试。',
      };
      _showMessage(guide);
      return;
    }
    setState(() {
      _testError = null;
      _testResult = null;
    });
    final PickedImportImage image;
    try {
      final picked = await _imagePicker.pickImage();
      if (picked == null) return;
      image = picked;
    } on ImportImagePickerException catch (error) {
      if (mounted) setState(() => _testError = error.message);
      return;
    }
    if (!mounted) return;
    setState(() => _testing = true);
    try {
      final result = await widget.backend.testLocalOcrImage(image.localAssetId);
      if (!mounted) return;
      setState(() {
        _testResult = result;
        _testing = false;
      });
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _testError = error.message;
        _testing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _testError = 'OCR 识别暂时失败，请稍后重试。';
        _testing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: const PixelPageAppBar(
        title: '识图引擎',
      ),
      body: _loading
          ? const AppLoadingState(label: '正在检查 OCR 路线…')
          : status == null
          ? Padding(
              padding: const EdgeInsets.all(18),
              child: AppErrorState(
                message: _errorMessage ?? 'OCR 状态暂时无法读取。',
                onRetry: _load,
                retryLabel: '\u91cd\u8bd5',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              children: <Widget>[
                // 图片识别方式：自动 / 仅 OCR / 多模态 LLM（识图引擎，IMAGE-001）。
                _ImageRecognitionModeSection(
                  mode: _imageRecognitionMode,
                  saving: _savingMode,
                  message: _modeMessage,
                  messageIsError: _modeMessageIsError,
                  onChange: (mode) {
                    setState(() {
                      _imageRecognitionMode = mode;
                      _modeMessage = null;
                    });
                  },
                  onSave: _saveImageRecognitionMode,
                ),
                const SizedBox(height: 14),
                const PxLabel('当前 OCR 路线'),
                const SizedBox(height: 8),
                PixelSurface(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Expanded(
                            child: Text(
                              '本地 OCR',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          PixelBadge(
                            label: _statusBadge(status),
                            icon: _statusIcon(status),
                            tone: _statusTone(status),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile。模型包、运行时和真实图片识别全部通过后，才会标记为可用。',
                        style: TextStyle(color: AppColors.ink2, height: 1.55),
                      ),
                      const SizedBox(height: 14),
                      _RuntimeRoute(status: status),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const PxLabel('模型包'),
                const SizedBox(height: 8),
                PixelSurface(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _StatusLine(status: status),
                      const SizedBox(height: 12),
                      // 测试 OCR：选一张图片识别，输出文本与耗时。
                      // 入口常驻（与模型安装状态无关），未安装时点击给出中文引导。
                      OutlinedButton.icon(
                        key: const Key('testOcrButton'),
                        onPressed: _testing || _busy ? null : _runOcrTest,
                        icon: _testing
                            ? const PixelLoader(size: 5, color: AppColors.ink2)
                            : const Icon(Icons.document_scanner_outlined),
                        label: Text(_testing ? '正在识别…' : '测试 OCR'),
                      ),
                      // 测试 OCR 结果 / 错误展示区。
                      if (_testError != null) ...<Widget>[
                        const SizedBox(height: 12),
                        PixelNotice(
                          key: const Key('ocrTestErrorMessage'),
                          title: 'OCR 识别失败',
                          message: _testError!,
                          tone: PixelNoticeTone.red,
                          icon: Icons.error_outline_rounded,
                        ),
                      ] else if (_testResult != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _OcrTestResultCard(result: _testResult!),
                      ],
                      if (_errorMessage != null) ...<Widget>[
                        const SizedBox(height: 12),
                        PixelNotice(
                          key: const Key('ocrErrorMessage'),
                          title: 'OCR 操作未完成',
                          message: _errorMessage,
                          tone: PixelNoticeTone.red,
                          icon: Icons.error_outline_rounded,
                        ),
                      ],
                      if (status.state == OcrModelInstallState.downloading ||
                          status.state ==
                              OcrModelInstallState.verifying) ...<Widget>[
                        const SizedBox(height: 14),
                        PixelProgressBar(
                          key: const Key('ocrInstallProgress'),
                          value: status.state == OcrModelInstallState.verifying
                              ? 1
                              : status.progress,
                          label: status.state == OcrModelInstallState.verifying
                              ? 'VERIFYING'
                              : '${(status.progress * 100).round()}%',
                          color: AppColors.blue,
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          key: const Key('cancelOcrInstallButton'),
                          onPressed: _cancellationToken == null
                              ? null
                              : _cancelInstall,
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('取消下载'),
                        ),
                      ] else if (status.state ==
                          OcrModelInstallState.installed) ...<Widget>[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const Key('deleteOcrModelButton'),
                          onPressed: _busy ? null : _delete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.red,
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('删除本地模型'),
                        ),
                      ] else ...<Widget>[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const Key('installOcrModelButton'),
                          onPressed: _busy || widget.installManifest == null
                              ? null
                              : _install,
                          icon: const Icon(Icons.download_rounded),
                          label: Text(
                            status.state == OcrModelInstallState.failed
                                ? '重试下载'
                                : '下载本地模型',
                          ),
                        ),
                        if (widget.installManifest == null) ...<Widget>[
                          const SizedBox(height: 10),
                          const PixelNotice(
                            key: Key('ocrManifestUnavailableMessage'),
                            title: '正式模型包尚未发布',
                            message: '当前不会启动下载，也不会用测试地址或虚假校验值伪装可用状态。',
                            tone: PixelNoticeTone.amber,
                            icon: Icons.inventory_2_outlined,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const PxLabel('云端路线'),
                const SizedBox(height: 8),
                PixelNotice(
                  key: const Key('cloudOcrStatusMessage'),
                  title: widget.session.isAuthenticated ? '云 OCR 状态' : '游客模式',
                  message: _cloudOcrDescription(widget.session, _localSettings),
                  tone: widget.session.isAuthenticated
                      ? PixelNoticeTone.blue
                      : PixelNoticeTone.amber,
                  icon: widget.session.isAuthenticated
                      ? Icons.cloud_outlined
                      : Icons.person_outline_rounded,
                ),
                const SizedBox(height: 12),
                const PixelNotice(
                  title: '隐私边界',
                  message: '本地 OCR 不上传图片；云端 OCR 必须同时满足登录、用户明确允许图片上传和服务器能力可用。',
                  tone: PixelNoticeTone.green,
                  icon: Icons.shield_outlined,
                ),
              ],
            ),
    );
  }

  static String _cloudOcrDescription(
    AppSession session,
    LocalAppSettings? settings,
  ) {
    if (!session.isAuthenticated) {
      return '游客不能使用平台托管的云 OCR；你仍可安装本地 OCR，且无需上传图片。';
    }
    if (settings?.allowImageUpload != true) {
      return '当前未允许上传图片，云 OCR 不可用。应用不会在这里诱导或自动修改你的隐私设置。';
    }
    return '图片上传已允许，但平台云 OCR 服务器尚未接入。';
  }
}

class _RuntimeRoute extends StatelessWidget {
  const _RuntimeRoute({required this.status});

  final OcrModelPackageStatus status;

  @override
  Widget build(BuildContext context) {
    final installed = status.state == OcrModelInstallState.installed;
    return Column(
      children: <Widget>[
        PixelRowTile(
          title: 'Flutter 插件桥',
          subtitle: '统一 OcrProvider 契约，Android 与 iOS 共享业务接口',
          icon: Icons.extension_outlined,
          trailing: PixelBadge(label: '就绪', tone: PixelNoticeTone.green),
        ),
        const SizedBox(height: 8),
        PixelRowTile(
          title: '端侧识别能力',
          subtitle: installed ? '模型包已就绪，实际可用性仍以运行时探测为准' : '等待模型包安装后启用',
          icon: Icons.document_scanner_outlined,
          trailing: PixelBadge(
            label: installed ? '就绪' : '关闭',
            tone: installed ? PixelNoticeTone.amber : PixelNoticeTone.neutral,
          ),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final OcrModelPackageStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status.state) {
      OcrModelInstallState.notInstalled => '未安装 · 识别能力未启用',
      OcrModelInstallState.downloading =>
        '正在下载 ${(status.progress * 100).round()}%',
      OcrModelInstallState.verifying => '正在校验模型包',
      OcrModelInstallState.installed =>
        '模型已安装 ${status.installedVersion ?? ''} · 运行时能力仍以实际探测为准',
      OcrModelInstallState.failed => '安装失败 · ${status.failureCode ?? '未知错误'}',
    };
    return PixelRowTile(
      key: const Key('ocrModelStatus'),
      title: 'PP-OCRv5 mobile zh',
      subtitle: label,
      icon: _statusIcon(status),
      tone: _statusTone(status),
      trailing: PixelBadge(
        label: _statusBadge(status),
        tone: _statusTone(status),
      ),
    );
  }
}

/// 测试 OCR 的结果卡片：展示识别文本、耗时、文本块数与平均置信度。
class _OcrTestResultCard extends StatelessWidget {
  const _OcrTestResultCard({required this.result});

  final OcrTestResult result;

  @override
  Widget build(BuildContext context) {
    final text = result.text.trim();
    final confidence = result.averageConfidence;
    return PixelSurface(
      key: const Key('ocrTestResultCard'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 标题行：结果 + 识别耗时。
          Row(
            children: <Widget>[
              const Text(
                '识别结果',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                result.durationMs != null
                    ? '耗时 ${result.durationMs} ms'
                    : '耗时未知',
                style: const TextStyle(color: AppColors.ink2, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 识别出的文本（空结果给出明确提示，不渲染空框）。
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.paper2,
              border: Border.all(color: AppColors.line2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              text.isEmpty ? '（这张图片里没有识别出文字）' : text,
              style: const TextStyle(color: AppColors.ink, height: 1.5),
            ),
          ),
          const SizedBox(height: 10),
          // 元信息：文本块数、平均置信度、模型版本、语言。
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: <Widget>[
              _OcrTestMeta(label: '文本块', value: '${result.blockCount}'),
              _OcrTestMeta(
                label: '平均置信度',
                value: confidence != null
                    ? '${(confidence * 100).toStringAsFixed(0)}%'
                    : '—',
              ),
              _OcrTestMeta(label: '模型', value: result.modelVersion),
              _OcrTestMeta(label: '语言', value: result.language),
            ],
          ),
        ],
      ),
    );
  }
}

/// 结果卡片中的小元信息项（标签 + 值）。
class _OcrTestMeta extends StatelessWidget {
  const _OcrTestMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: AppColors.ink3, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: AppColors.ink2, fontSize: 12),
        ),
      ],
    );
  }
}

/// 图片识别方式设置区（识图引擎，IMAGE-001）：自动 / 仅 OCR / 多模态 LLM。
class _ImageRecognitionModeSection extends StatelessWidget {
  const _ImageRecognitionModeSection({
    required this.mode,
    required this.saving,
    required this.message,
    required this.messageIsError,
    required this.onChange,
    required this.onSave,
  });

  final ImageRecognitionMode mode;
  final bool saving;
  final String? message;
  final bool messageIsError;
  final ValueChanged<ImageRecognitionMode> onChange;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PxLabel('图片识别方式'),
        const SizedBox(height: 8),
        PixelSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ModeOption(
                value: ImageRecognitionMode.auto,
                groupValue: mode,
                title: '自动',
                subtitle: '多模态 LLM 可用时优先，否则回退本地 OCR，再否则不识别图片。',
                onChanged: saving ? null : onChange,
              ),
              const SizedBox(height: 4),
              _ModeOption(
                value: ImageRecognitionMode.ocr,
                groupValue: mode,
                title: '仅 OCR',
                subtitle: '只用本地 OCR 模型识别图片中的文字。',
                onChanged: saving ? null : onChange,
              ),
              const SizedBox(height: 4),
              _ModeOption(
                value: ImageRecognitionMode.multimodalLlm,
                groupValue: mode,
                title: '多模态 LLM',
                subtitle: '用下方配置的图片识别 LLM 理解图片整体内容。',
                onChanged: saving ? null : onChange,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      message ?? '',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        height: 1.4,
                        color: messageIsError
                            ? AppColors.red
                            : AppColors.greenDeep,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    key: const Key('saveImageRecognitionModeButton'),
                    onPressed: saving ? null : onSave,
                    icon: saving
                        ? const PixelLoader(size: 5, color: Colors.white)
                        : const Icon(Icons.check_rounded, size: 16),
                    label: Text(saving ? '保存中…' : '保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 识别方式单选行。
class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final ImageRecognitionMode value;
  final ImageRecognitionMode groupValue;
  final String title;
  final String subtitle;
  final ValueChanged<ImageRecognitionMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return InkWell(
      key: Key('imageRecognitionMode_${value.name}'),
      onTap: onChanged == null ? null : () => onChanged!(value),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 18,
              color: selected ? AppColors.greenDeep : AppColors.ink3,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: selected ? AppColors.greenDeep : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppColors.ink2,
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

IconData _statusIcon(OcrModelPackageStatus status) => switch (status.state) {
  OcrModelInstallState.notInstalled => Icons.download_outlined,
  OcrModelInstallState.downloading => Icons.downloading_rounded,
  OcrModelInstallState.verifying => Icons.verified_outlined,
  OcrModelInstallState.installed => Icons.check_circle_outline_rounded,
  OcrModelInstallState.failed => Icons.error_outline_rounded,
};

String _statusBadge(OcrModelPackageStatus status) => switch (status.state) {
  OcrModelInstallState.notInstalled => 'NOT INSTALLED',
  OcrModelInstallState.downloading => 'DOWNLOADING',
  OcrModelInstallState.verifying => 'VERIFYING',
  OcrModelInstallState.installed => 'INSTALLED',
  OcrModelInstallState.failed => 'FAILED',
};

PixelNoticeTone _statusTone(OcrModelPackageStatus status) =>
    switch (status.state) {
      OcrModelInstallState.notInstalled => PixelNoticeTone.neutral,
      OcrModelInstallState.downloading => PixelNoticeTone.blue,
      OcrModelInstallState.verifying => PixelNoticeTone.amber,
      OcrModelInstallState.installed => PixelNoticeTone.green,
      OcrModelInstallState.failed => PixelNoticeTone.red,
    };
