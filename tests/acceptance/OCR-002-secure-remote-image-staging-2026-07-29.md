# OCR-002 远程 HTTPS 图片安全暂存验收记录

- 日期：2026-07-29
- 状态：自动化验收通过
- 任务：`OCR-002`
- 关联主任务：`SPK-002`（继续保持 `DOING`）

## 验收范围

本轮验收本地 OCR 在处理远程图片前的安全下载、应用私有临时文件暂存、图片载荷校验、调用后清理，以及设备组合根接入。云 OCR Provider 不经过本暂存层。

## 实现架构

```text
公开内容 Adapter 的远程图片 URL
→ RemoteStagingOcrProvider
→ SecureRemoteOcrImageStager
→ RemoteOcrImageSecurityPolicy
→ PinnedHttpsOcrImageDownloadClient
→ 应用私有临时图片
→ 本地 OcrProvider
→ 成功、失败或取消后释放临时文件
```

- [x] 已有本地图片直接透传，不重复复制。
- [x] 默认本地 OCR Builder 与自定义本地 OCR Builder 均经过远程暂存包装。
- [x] `OcrRemoteImageStager` 可注入测试替身。
- [x] 云 OCR Provider 保持供应商侧传输，不复用本地暂存层。

## URL、DNS、重定向与 TLS 安全边界

- [x] 只接受 `https` URL。
- [x] 拒绝缺失主机、userinfo、fragment 和控制字符。
- [x] DNS 返回的全部地址都必须是公网地址；只要混入非公网地址即拒绝。
- [x] 拒绝环回、私网、link-local、CGNAT、文档地址和其他保留地址。
- [x] 301、302、303、307、308 重定向每一跳都重新校验 URL 与 DNS。
- [x] 拒绝重定向降级到 HTTP 或跳转至非公网地址。
- [x] TCP 连接固定到已通过校验的 IP，避免校验后重新解析导致地址漂移。
- [x] HTTP `Host`、TLS SNI 与证书主机名校验继续使用原始域名。
- [x] 映射后的错误不暴露源 URL、主机名、解析 IP 或本地路径。

## HTTP 响应限制

- [x] 支持受限的 HTTP/1.0 与 HTTP/1.1 响应。
- [x] 支持 `Content-Length`、`chunked` 和 connection-close 响应体。
- [x] 限制响应头大小、重定向次数、下载字节数和连接/TLS/响应/总操作超时。
- [x] 在写入响应体前拒绝超过上限的 `Content-Length`。
- [x] 拒绝重复敏感 Header、冲突的响应 framing 和不支持的 `Transfer-Encoding`。
- [x] 取消时销毁活动连接并停止继续写入。

## 图片载荷校验

- [x] 只允许 JPEG、PNG 和 WebP。
- [x] `Content-Type` 必须与图片 magic bytes 一致。
- [x] 拒绝非图片字节、MIME 不匹配和不支持的图片格式。
- [x] 限制下载字节、图片单边尺寸和总像素。
- [x] 图片验证失败时删除部分文件。

## 生命周期与临时文件清理

- [x] 识别成功后清理暂存文件。
- [x] 本地 OCR Provider 返回失败后清理暂存文件。
- [x] 下载、验证或写入失败后清理部分文件。
- [x] 取消后清理部分文件或已完成的暂存文件。
- [x] Facade 集成测试使用明确的远程图片暂存替身，不访问真实网络。

## 自动化验证

```text
OCR-002 定向测试：39 项通过
dart format --output=none --set-exit-if-changed lib test：130 个文件，0 个变化
dart analyze：No issues found
flutter analyze --no-pub：No issues found
flutter test --no-pub：307 项全部通过
Android :app:testDebugUnitTest --rerun-tasks：BUILD SUCCESSFUL，112 个任务全部执行
```

定向测试覆盖：

- URL 语法、HTTPS-only 和公网地址策略。
- 公网/私网混合 DNS 结果。
- 逐跳重定向复检与 HTTP 降级拒绝。
- 固定已验证地址的连接行为。
- `Content-Length`、chunked、connection-close 和响应 framing。
- 响应头、字节、超时与取消边界。
- JPEG、PNG、WebP 的 MIME 与 magic bytes 校验。
- 字节、边长、像素限制。
- 成功、失败和取消后的文件清理。
- 本地图片透传、远程图片包装和设备组合根接入。

## 验收边界与未验收项

以下内容不属于本次自动化验收结论，仍需后续切片验证：

- [ ] 真实小红书、抖音公开图片的端到端导入与本地 OCR 联调。
- [ ] 真实 CDN 重定向、防盗链和公网证书链行为。
- [ ] Android 真机网络、取消、临时目录和存储压力行为。
- [ ] 真实 PP-OCRv5 mobile 模型、转换参数、词典与许可证证据。
- [ ] Android 真机识别准确率、首次加载、1080p 单图耗时、峰值内存和模型体积。
- [ ] iOS Runtime、构建、网络权限和 iPhone 真机验证。
- [ ] 完整 Paddle DB contour/min-area-rect/unclip 后处理。
- [ ] 方向分类器、旋转/倾斜文字和复杂布局。
- [ ] 跨 isolate、多服务实例、跨进程和 OS 文件锁级别的模型包互斥。
- [ ] Manifest 签名、固定公钥或其他可信发布链。

## 结论

`OCR-002` 的远程 HTTPS 图片安全暂存层已通过当前自动化验收，可标记为 `DONE`。本结论只证明安全策略、受限下载、图片验证、暂存清理和组合根接入在可控测试环境下符合约定，不代表真实平台图片、真实 OCR 模型、真机质量或 iOS 已通过。关联主任务 `SPK-002` 继续保持 `DOING`。
