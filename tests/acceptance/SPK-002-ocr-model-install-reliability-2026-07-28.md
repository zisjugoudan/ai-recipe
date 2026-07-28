# SPK-002 OCR 模型安装可靠性验收记录

> 日期：2026-07-28
> 状态：Android 基础切片通过；`SPK-002` 仍为 `DOING`
> 工程：`code/apps/mobile`
> Windows 构建入口：`C:	mpi-recipe-mobile`

## 1. 验收范围

本记录聚焦 `R-013` 的基础缓解：

1. 模型安装显式取消。
2. 下载前磁盘空间预检。
3. 激活成功后的旧版本回收。
4. 激活提交点后的异常不得删除已激活模型。

本记录不验收真实 OCR 推理、iOS 真机、跨进程互斥或 Manifest 可信发布链。

## 2. 已实现行为

### 2.1 显式取消

- 新增 `OcrModelInstallCancellationToken`。
- 取消检查覆盖排队完成后、创建目录、容量检查前后、文件下载前、每个下载 chunk、Manifest 写入、staging rename、health check 和 active 切换前。
- 下载中取消会清理 staging 目录。
- 升级取消保留上一 active 版本。
- `state.json` 写入 `failureCode = cancelled`。
- `AiRecipeBackendFacade` 将取消映射为稳定 `operationCancelled`。
- 同包队列等待期间取消不是立即完成：当前操作必须等待前一个同包操作结束，随后在真正开始 I/O 前检查取消，避免后续操作越过仍在运行的前序安装。

### 2.2 下载前空间预检

- 新增 `OcrModelStorageCapacityProvider`。
- 默认要求：Manifest 模型总大小 + 64 MiB 安全余量。
- Provider 返回 `null` 时表示平台无法取得容量，安装继续。
- Provider 返回负数时映射为 `storageUnavailable`。
- 空间不足时映射为 `insufficientStorage`，且不发起下载。
- Android MethodChannel 新增 `getAvailableStorageBytes`，使用最近存在父目录的 `StatFs.availableBytes`。
- Dart 新增 `PlatformOcrStorageCapacityProvider`；`MissingPluginException`、`PlatformException`、非法响应和负数响应均返回 `null`，不向上泄漏原生异常。

### 2.3 旧版本回收

- 默认保留 active + 1 个最新 inactive 版本。
- `retainedInactiveVersions: 0` 时只保留 active。
- 忽略非语义版本目录。
- 回收异常 best-effort 处理，不能让已经激活的新版本失败。
- `retainedInactiveVersions < 0` 抛 `ArgumentError`。

### 2.4 激活提交点保护

- `active.json` 写入成功后视为安装提交点。
- 提交点之后，如果最终 `installed` 状态持久化或 `onStatusChanged` 回调抛异常，不得删除新版本目录。
- 服务会 best-effort 重写 `installed` 状态并返回 installed 结果。

## 3. 自动化验证

从 `C:	mpi-recipe-mobile` 执行：

```powershell
dart --suppress-analytics format lib test
flutter --suppress-analytics analyze --no-pub
flutter --suppress-analytics test --no-pub
flutter --suppress-analytics build apk --debug
```

结果：

- `dart format`：118 个文件，0 个变化。
- `flutter analyze --no-pub`：`No issues found!`
- `flutter test --no-pub`：259 项全部通过。
- Android Debug APK：成功生成 `build/app/outputs/flutter-apk/app-debug.apk`。

新增或更新的重点回归覆盖：

- 下载中取消并清理 staging。
- 升级取消保留上一 active。
- 空间不足时不调用下载客户端。
- 容量未知时继续安装。
- 默认保留 active + 1 inactive。
- `retainedInactiveVersions: 0` 只保留 active。
- 负数 reserve/retention 抛 `ArgumentError`。
- 激活成功后最终状态回调失败不删除 active 包。
- Android 容量查询 MethodChannel 名称、参数和异常降级。
- Facade 取消令牌透传、`insufficientStorage` 和 `cancelled` 稳定映射。

## 4. 未完成与风险状态

- `R-013` 只能标记为 Android 基础缓解，不关闭：iOS 容量查询、取消和回收未验证；真实设备空间压力、低内存和长时间下载场景未验证。
- `R-012` 仍开放：同一服务实例内串行队列已完成，但跨 isolate、多服务实例、跨进程和 OS 文件锁未完成。
- Manifest 签名、固定公钥、可信索引或完整可信发布链未实现。
- Android `recognize` 仍固定返回 `inference_not_implemented`。
- `recognitionSupported` 仍固定为 `false`。
- 真实 PP-OCRv5 模型、图片预处理、推理、后处理、真机性能指标和 iOS 均未完成。

## 5. 验收结论

`R-013` 的 Android 基础可靠性切片通过，模型安装现在具备显式取消、空间预检、旧版本回收和激活提交点保护。但这不代表本地 OCR 已完成；`SPK-002` 继续保持 `DOING`。
