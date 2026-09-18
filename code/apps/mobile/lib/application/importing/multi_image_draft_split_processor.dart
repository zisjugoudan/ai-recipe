import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;

import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/llm/llm_cancellation_token.dart';
import '../../domain/llm/llm_connection_config.dart';
import '../../domain/llm/llm_models.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/llm_provider_exception.dart';
import 'import_pipeline_contracts.dart';

/// 多图分组判断与多草稿生成（IMAGE-002，ADR-0029）。
///
/// 多模态转录处理器只保证每张图的文字证据完整；本处理器负责：
/// 1. 用纯文本 LLM 判断多张图片是“每张图独立完整菜谱”还是“多张图合成一个
///    菜谱”（以及混合分组）；
/// 2. 按分组把转录证据拆分为多份 `ImportContent`，逐组调用下游
///    （结构化生成）产出多个菜谱草稿；
/// 3. 聚合返回多个草稿 ID（主草稿 + 附加草稿）。
///
/// 分组判断失败时**回退为全部合并生成一个草稿**（combined），不因判断失败
/// 丢弃内容，也不生成空草稿。
class MultiImageDraftSplitProcessor implements ImportContentProcessor {
  MultiImageDraftSplitProcessor({
    required LlmProvider provider,
    required LlmConnectionConfig config,
    required String apiKey,
    required ImportContentProcessor downstream,
  }) : _provider = provider,
       _config = config,
       _apiKey = apiKey,
       _downstream = downstream;

  /// 分组判断固定提示词：只要求返回 JSON，不生成菜谱正文。
  static const String groupingPrompt = '''
下面是一个菜谱内容的多张图片转录文字，每张图用“图 N：”开头（N 从 0 开始）。
请判断这些图片的关系，只返回 JSON，不要解释：
- 每张图都是一份完整独立的菜谱 → {"mode":"independent","reason":"..."}
- 所有图合起来才是一份完整菜谱 → {"mode":"combined","reason":"..."}
- 按图号分组，每组一份菜谱 → {"mode":"mixed","groups":[[0],[1,2]],"reason":"..."}

判断规则（依次检查）：
1. 逐张图判断它是否包含：完整菜名 + 配料/食材列表 + 做法步骤。如果某张图这三者
   都齐备，它就是一份独立菜谱，应作为独立分组。
2. 只有当多张图明显是同一道菜的分段（例如图 1 只有开头、图 2 才是配料、图 3 才是
   做法，或文字明确说明“接上文/见图 X”），才合并为同一组。
3. 图片是否像“多角度/多张同菜”不影响判断：只要每张图内容各自完整，就选
   independent 或 mixed，不要轻易合并。
4. mixed 时图号从 0 开始，与输入一致，所有图都必须恰好出现在一组中。

输入：
''';

  final LlmProvider _provider;
  final LlmConnectionConfig _config;
  final String _apiKey;
  final ImportContentProcessor _downstream;

  @override
  Future<ImportRecipeDraftResult> process(
    ImportContent content, {
    required ImportPipelineProgressCallback onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();

    // 只对“多张图都产出了文字转录”的内容做分组判断；单图/无转录直接走下游。
    final transcribedImages = _transcribedImageGroups(content);
    debugPrint(
      '[AIRecipe][Grouping] 进入分组处理 转录图组数=${transcribedImages.length} '
      '转录片段数=${content.textFragments.where((f) => f.sourceType == ImportTextFragmentSourceType.ocr).length}',
    );
    if (transcribedImages.length < 2) {
      debugPrint(
        '[AIRecipe][Grouping] 图组数<2，跳过分组判断，直接生成单草稿',
      );
      return _downstream.process(
        content,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    }

    await onProgress(
      ImportTaskStage.generating,
      0.6,
      '正在分析 ${transcribedImages.length} 张图片是否为同一道菜',
    );
    cancellationToken?.throwIfCancelled();

    // 分组判断：失败回退为全部合并，避免内容被丢弃。
    final groups = await _resolveGroups(
      content,
      transcribedImages,
      cancellationToken,
    );
    if (groups.length < 2) {
      // 全部合并为一份菜谱（含判断失败回退）。
      return _downstream.process(
        content,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    }

    // 分组完成：告知用户将生成几份草稿。
    await onProgress(
      ImportTaskStage.generating,
      0.6,
      '识别为 ${groups.length} 份独立菜谱，正在生成草稿',
    );

    // 按图分组逐份生成草稿：第一组为主草稿，其余为附加草稿。
    // 性能优化（IMAGE-002 / 解决方案.md）：多草稿生成改为有限并发（同时 2 份），
    // 避免 N 份草稿串行累加等待时间（串行 3 份实测约 139s → 并发约 60s）。
    final recipeIds = await _generateDraftsConcurrently(
      content,
      groups,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );

    return ImportRecipeDraftResult(
      recipeId: recipeIds.first,
      additionalRecipeIds: recipeIds.skip(1).toList(growable: false),
    );
  }

  /// 有限并发逐组生成草稿（并发窗口 2），结果按下标保序。
  ///
  /// 进度处理：每组草稿生成期间，整体进度落在 [0.6, 0.9] 的独立子区间内推进。
  /// 同批内并发的组共享 `lastEmitted` 并取最大值，保证跨组切换时进度严格单调
  /// 不减，避免触发任务“进度不能倒退”校验导致整单失败（IMAGE-002）。
  Future<List<String>> _generateDraftsConcurrently(
    ImportContent content,
    List<List<int>> groups, {
    required ImportPipelineProgressCallback onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    final recipeIds = List<String?>.filled(groups.length, null);
    const progressStart = 0.6;
    const progressEnd = 0.9;
    var lastEmitted = progressStart;
    const concurrency = 2;

    // 并发组会同时回调 onProgress：若并发写导入任务，SQLite 乐观锁会把
    // “读-改-写”变成写冲突或进度交错回退，导致整单 unexpected 失败
    // （IMAGE-002，实测多草稿并发生成偶发“导入失败·不可重试”）。这里把
    // 进度上报串行化，从源头消除并发写；runner 侧另有冲突重试兜底。
    var reportChain = Future<void>.value();
    Future<void> report(
      ImportTaskStage stage,
      double progress,
      String detail,
    ) {
      final current = reportChain.then(
        (_) => onProgress(stage, progress, detail),
      );
      // 单次上报失败不阻断后续上报；错误仍会经 generateOne 的 Future
      // 抛给调用方（如取消需要立即中止）。
      reportChain = current.catchError((_) {});
      return current;
    }

    Future<void> generateOne(int index) async {
      cancellationToken?.throwIfCancelled();
      final groupContent = _splitContentByGroup(
        content,
        groups[index],
        isFirstGroup: index == 0,
      );
      final groupStart =
          progressStart + (progressEnd - progressStart) * index / groups.length;
      final groupEnd =
          progressStart + (progressEnd - progressStart) * (index + 1) / groups.length;
      final result = await _downstream.process(
        groupContent,
        onProgress: (stage, progress, [detail]) async {
          // 下游结构化生成器进度范围约为 [0.65, 0.9]，先映射到本组子区间；
          // 再与已上报进度取较大值兜底，保证整体进度单调不减。
          final t = ((progress - 0.65) / (1 - 0.65)).clamp(0.0, 1.0);
          final effective = math.max(
            groupStart + (groupEnd - groupStart) * t,
            lastEmitted,
          );
          lastEmitted = effective;
          // 覆盖下游详情：分组场景下“第几份草稿”比生成器内部说明更有用。
          await report(
            stage,
            effective,
            '正在生成第 ${index + 1}/${groups.length} 份菜谱草稿',
          );
        },
        cancellationToken: cancellationToken,
      );
      recipeIds[index] = result.recipeId;
      // 本组结束后推进到该组子区间终点，保证进度单调不减。
      final finished = math.max(groupEnd, lastEmitted);
      lastEmitted = finished;
      await report(
        ImportTaskStage.generating,
        finished,
        '第 ${index + 1}/${groups.length} 份草稿已生成',
      );
    }

    // 以并发窗口 2 分批执行；批内并发、批间串行，既加速又保持进度单调。
    for (var start = 0; start < groups.length; start += concurrency) {
      cancellationToken?.throwIfCancelled();
      final end = math.min(start + concurrency, groups.length);
      await Future.wait(<Future<void>>[
        for (var index = start; index < end; index += 1) generateOne(index),
      ]);
    }

    // 并发完成，进度推进到子区间终点，由后续阶段继续。
    lastEmitted = math.max(progressEnd, lastEmitted);
    await report(
      ImportTaskStage.generating,
      progressEnd,
      '全部草稿已生成，正在收尾',
    );
    return recipeIds.cast<String>().toList(growable: false);
  }

  /// 转录片段按图（sourceMediaOrder）分组；只统计有转录文本的图。
  static Map<int, List<ImportTextFragment>> _transcribedImageGroups(
    ImportContent content,
  ) {
    final groups = <int, List<ImportTextFragment>>{};
    for (final fragment in content.textFragments) {
      if (fragment.sourceType != ImportTextFragmentSourceType.ocr) continue;
      final mediaOrder = fragment.sourceMediaOrder;
      if (mediaOrder == null) continue;
      groups.putIfAbsent(mediaOrder, () => <ImportTextFragment>[]).add(fragment);
    }
    return groups;
  }

  /// 分组判断：调用纯文本 LLM，失败时回退全部合并。
  Future<List<List<int>>> _resolveGroups(
    ImportContent content,
    Map<int, List<ImportTextFragment>> transcribedImages,
    ImportCancellationToken? cancellationToken,
  ) async {
    final orders = transcribedImages.keys.toList()..sort();
    final buffer = StringBuffer(groupingPrompt);
    if (content.title?.trim().isNotEmpty == true) {
      buffer.writeln('作者标题：${content.title}');
    }
    if (content.description?.trim().isNotEmpty == true) {
      buffer.writeln('作者简介：${content.description}');
    }
    for (final order in orders) {
      buffer.writeln('图 $order：');
      final fragments = transcribedImages[order]!
        ..sort((a, b) => a.order.compareTo(b.order));
      for (final fragment in fragments) {
        buffer.writeln(fragment.text);
      }
    }

    final llmCancellationToken = LlmCancellationToken();
    if (cancellationToken != null) {
      unawaited(
        cancellationToken.whenCancelled.then((_) {
          llmCancellationToken.cancel();
        }),
      );
    }

    String responseText;
    try {
      final result = await _provider.generate(
        config: _config,
        apiKey: _apiKey,
        request: LlmGenerationRequest(
          messages: <LlmMessage>[
            LlmMessage(role: LlmMessageRole.user, content: buffer.toString()),
          ],
          temperature: 0,
          // 分组判断是轻量分类任务（PERF-001，深度思考开关方案）：固定用
          // 快速模式，避免额外推理开销拖慢导入。
          reasoningMode: LlmReasoningMode.fast,
        ),
        cancellationToken: llmCancellationToken,
      );
      responseText = result.text;
      // 记录 LLM 原始分组响应，便于真机诊断分组质量（IMAGE-002）。
      debugPrint(
        '[AIRecipe][Grouping] 分组判断原始响应：${_clip(responseText, 500)}',
      );
    } on LlmProviderException catch (error) {
      debugPrint(
        '[AIRecipe][Grouping] 分组判断 LLM 失败 kind=${error.kind.name}，'
        '回退为全部合并',
      );
      return <List<int>>[orders];
    } catch (_) {
      debugPrint('[AIRecipe][Grouping] 分组判断调用异常，回退为全部合并');
      return <List<int>>[orders];
    }
    cancellationToken?.throwIfCancelled();

    final parsed = _parseGrouping(responseText, orders);
    if (parsed == null) {
      debugPrint(
        '[AIRecipe][Grouping] 分组判断响应无法解析，回退为全部合并：'
        '${_clip(responseText, 200)}',
      );
      return <List<int>>[orders];
    }
    debugPrint(
      '[AIRecipe][Grouping] 分组结果 groups=${parsed.map((g) => g.join(",")).join(" | ")} '
      '图数=${orders.length} 草稿数=${parsed.length}',
    );
    return parsed;
  }

  /// 解析分组 JSON；失败返回 null。
  static List<List<int>>? _parseGrouping(String text, List<int> orders) {
    final trimmed = text.trim();
    // 允许模型返回 ```json ... ``` 代码块。
    final jsonMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(trimmed);
    final jsonText = jsonMatch?.group(1) ?? trimmed;
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final mode = decoded['mode'];
    if (mode == 'independent') {
      return orders.map((order) => <int>[order]).toList(growable: false);
    }
    if (mode == 'combined') {
      return <List<int>>[List<int>.from(orders)];
    }
    if (mode == 'mixed') {
      final rawGroups = decoded['groups'];
      if (rawGroups is! List) return null;
      final groups = <List<int>>[];
      final covered = <int>{};
      for (final raw in rawGroups) {
        if (raw is! List) return null;
        final group = <int>[];
        for (final item in raw) {
          if (item is! int) return null;
          if (!orders.contains(item) || covered.contains(item)) return null;
          group.add(item);
          covered.add(item);
        }
        if (group.isEmpty) return null;
        groups.add(group);
      }
      if (covered.length != orders.length) return null;
      return groups;
    }
    return null;
  }

  /// 按图分组拆分 content：
  /// - 只保留属于该组图序的转录片段；
  /// - 作者原文（authorText）与标题仅并入第一份草稿，避免多草稿重复正文；
  /// - 媒体列表保留该组图片（供配图/封面）。
  ImportContent _splitContentByGroup(
    ImportContent content,
    List<int> groupOrders, {
    required bool isFirstGroup,
  }) {
    final orderSet = groupOrders.toSet();
    final fragments = <ImportTextFragment>[];
    var order = -1;
    ImportTextFragment copy(ImportTextFragment source) {
      order += 1;
      return ImportTextFragment(
        kind: source.kind,
        text: source.text,
        order: order,
        confidence: source.confidence,
        sourceMediaOrder: source.sourceMediaOrder,
        sourceProvider: source.sourceProvider,
        sourceLanguage: source.sourceLanguage,
        sourceStartMs: source.sourceStartMs,
        sourceEndMs: source.sourceEndMs,
        speakerLabel: source.speakerLabel,
        sourceType: source.sourceType,
      );
    }

    for (final fragment in content.textFragments) {
      final isTranscription =
          fragment.sourceType == ImportTextFragmentSourceType.ocr &&
          fragment.sourceMediaOrder != null;
      if (isTranscription) {
        if (orderSet.contains(fragment.sourceMediaOrder)) {
          fragments.add(copy(fragment));
        }
      } else if (isFirstGroup &&
          fragment.sourceType == ImportTextFragmentSourceType.authorText) {
        // 作者原文只并入第一份草稿，避免多草稿重复正文。
        fragments.add(copy(fragment));
      }
    }

    final media = content.media
        .where(
          (item) =>
              item.kind != ImportMediaKind.image ||
              orderSet.contains(item.order),
        )
        .toList(growable: false);

    return ImportContent(
      source: content.source,
      resolvedUrl: content.resolvedUrl,
      contentType: content.contentType,
      title: isFirstGroup ? content.title : null,
      description: null,
      authorName: content.authorName,
      publishedAt: content.publishedAt,
      capturedAt: content.capturedAt,
      textFragments: fragments,
      media: media,
      warnings: content.warnings
          .where(
            (warning) =>
                warning != ImportContentWarning.requiresOcr &&
                warning != ImportContentWarning.missingText,
          )
          .toSet(),
    );
  }

  static String _clip(String value, int maxLength) =>
      value.length <= maxLength ? value : '${value.substring(0, maxLength)}…';
}
