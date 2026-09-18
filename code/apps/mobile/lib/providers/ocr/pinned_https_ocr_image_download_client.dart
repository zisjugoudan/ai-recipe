import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/ocr/ocr_provider_exception.dart';
import 'ocr_remote_image_download_client.dart';
import 'remote_ocr_image_security_policy.dart';

class PinnedHttpsOcrImageDownloadClient
    implements OcrRemoteImageDownloadClient {
  PinnedHttpsOcrImageDownloadClient({
    OcrRemoteImageSecurityPolicy securityPolicy =
        const OcrRemoteImageSecurityPolicy(),
    OcrHostResolver? hostResolver,
    OcrPinnedHttpsConnector? connector,
    this.maxBytes = 16 * 1024 * 1024,
    this.maxRedirects = 5,
    this.maxResponseHeaderBytes = 32 * 1024,
    this.connectionTimeout = const Duration(seconds: 10),
    this.tlsTimeout = const Duration(seconds: 10),
    this.responseTimeout = const Duration(seconds: 15),
    this.totalTimeout = const Duration(seconds: 60),
  }) : _securityPolicy = securityPolicy,
       _hostResolver = hostResolver ?? InternetAddress.lookup,
       _connector = connector ?? _connectPinnedTls {
    if (maxBytes <= 0 ||
        maxRedirects < 0 ||
        maxResponseHeaderBytes <= 0 ||
        connectionTimeout <= Duration.zero ||
        tlsTimeout <= Duration.zero ||
        responseTimeout <= Duration.zero ||
        totalTimeout <= Duration.zero) {
      throw ArgumentError('Remote OCR download limits must be valid.');
    }
  }

  final OcrRemoteImageSecurityPolicy _securityPolicy;
  final OcrHostResolver _hostResolver;
  final OcrPinnedHttpsConnector _connector;
  final int maxBytes;
  final int maxRedirects;
  final int maxResponseHeaderBytes;
  final Duration connectionTimeout;
  final Duration tlsTimeout;
  final Duration responseTimeout;
  final Duration totalTimeout;

  @override
  Future<OcrRemoteImageDownload> download(
    Uri uri,
    File destination, {
    ImportCancellationToken? cancellationToken,
  }) async {
    final operation = _DownloadOperation(
      cancellationToken: cancellationToken,
      totalTimeout: totalTimeout,
    );
    try {
      var current = _securityPolicy.validateUrl(uri.toString());
      for (var redirectCount = 0; ; redirectCount += 1) {
        operation.throwIfStopped();
        final response = await _request(
          current,
          destination,
          operation: operation,
        );
        if (!response.isRedirect) {
          return OcrRemoteImageDownload(
            mimeType: response.mimeType!,
            byteLength: response.byteLength!,
          );
        }
        if (redirectCount >= maxRedirects) {
          throw const OcrProviderException(
            kind: OcrProviderErrorKind.invalidResponse,
            message: 'Remote OCR image exceeded the redirect limit.',
          );
        }
        current = _securityPolicy.validateUrl(
          current.resolve(response.location!).toString(),
        );
      }
    } on ImportOperationCancelledException {
      rethrow;
    } on OcrProviderException {
      rethrow;
    } on _OcrDownloadTimeout {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.timeout,
        message: 'Remote OCR image download timed out.',
      );
    } on SocketException {
      if (cancellationToken?.isCancelled ?? false) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.cancelled,
          message: 'Remote OCR image staging was cancelled.',
        );
      }
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.networkUnavailable,
        message: 'Remote OCR image network is unavailable.',
      );
    } on TlsException {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.networkUnavailable,
        message: 'Remote OCR image TLS connection failed.',
      );
    } on FileSystemException {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.unavailable,
        message: 'Remote OCR image staging storage is unavailable.',
      );
    } catch (_) {
      if (cancellationToken?.isCancelled ?? false) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.cancelled,
          message: 'Remote OCR image staging was cancelled.',
        );
      }
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: 'Remote OCR image response is invalid.',
      );
    } finally {
      operation.finish();
    }
  }

  Future<_RemoteResponse> _request(
    Uri uri,
    File destination, {
    required _DownloadOperation operation,
  }) async {
    final literal = InternetAddress.tryParse(uri.host);
    final resolved = literal == null
        ? await operation.wait(
            _hostResolver(uri.host),
            phaseTimeout: connectionTimeout,
          )
        : <InternetAddress>[literal];
    _securityPolicy.validateResolvedAddresses(resolved);
    operation.throwIfStopped();
    // 优先 IPv4：部分 CDN 的 IPv6 边缘节点会对非浏览器客户端返回 403
    // （真机实测），而 IPv4 节点可正常下载（Windows 同网络实测 200）。
    final addresses = <InternetAddress>[
      ...resolved.where((item) => item.type == InternetAddressType.IPv4),
      ...resolved.where((item) => item.type != InternetAddressType.IPv4),
    ];
    debugPrint(
      '[AIRecipe][RemoteImage] 解析 ${uri.host} -> '
      '${addresses.map((item) => item.address).join(',')}',
    );

    // 地址级故障转移：连接失败或应用层被拒（如 403）时依次尝试下一个
    // 解析地址，全部失败后抛出最后一次记录的错误。
    OcrProviderException? lastRejection;
    OcrProviderException? lastConnectionError;
    for (final address in addresses) {
      operation.throwIfStopped();
      try {
        return await _requestOnce(
          uri,
          destination,
          address: address,
          operation: operation,
        );
      } on ImportOperationCancelledException {
        rethrow;
      } on _OcrDownloadTimeout {
        // 全局超时与具体地址无关，不换地址直接上抛。
        rethrow;
      } on FileSystemException {
        // 存储层错误与网络无关，不换地址。
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.unavailable,
          message: 'Remote OCR image staging storage is unavailable.',
        );
      } on OcrProviderException catch (error) {
        lastRejection = error;
        debugPrint(
          '[AIRecipe][RemoteImage] 地址 ${address.address} 被拒 '
          'kind=${error.kind.name} status=${error.statusCode}',
        );
      } on SocketException {
        lastConnectionError = const OcrProviderException(
          kind: OcrProviderErrorKind.networkUnavailable,
          message: 'Remote OCR image network is unavailable.',
        );
      } on TlsException {
        lastConnectionError = const OcrProviderException(
          kind: OcrProviderErrorKind.networkUnavailable,
          message: 'Remote OCR image TLS connection failed.',
        );
      } catch (_) {
        lastRejection = const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Remote OCR image response is invalid.',
        );
      }
    }
    if (lastRejection != null) throw lastRejection;
    if (lastConnectionError != null) throw lastConnectionError;
    throw const OcrProviderException(
      kind: OcrProviderErrorKind.invalidResponse,
      message: 'Remote OCR image response is invalid.',
    );
  }

  /// 在单个解析地址上执行一次连接与下载请求。
  Future<_RemoteResponse> _requestOnce(
    Uri uri,
    File destination, {
    required InternetAddress address,
    required _DownloadOperation operation,
  }) async {
    OcrPinnedHttpsConnection? connection;
    try {
      final establishedConnection = await operation.wait(
        _connector(
          uri: uri,
          address: address,
          connectionTimeout: operation.limit(connectionTimeout),
          tlsTimeout: operation.limit(tlsTimeout),
          cancellationToken: operation.cancellationToken,
        ),
        phaseTimeout: connectionTimeout + tlsTimeout,
      );
      connection = establishedConnection;
      operation.connection = establishedConnection;
      debugPrint('[AIRecipe][RemoteImage] 已连接 ${address.address}');
      establishedConnection.add(ascii.encode(_buildRequest(uri)));
      await operation.wait(
        establishedConnection.flush(),
        phaseTimeout: responseTimeout,
      );

      final reader = _ConnectionReader(
        establishedConnection.incoming,
        operation: operation,
        responseTimeout: responseTimeout,
      );
      final headerBytes = await reader.readUntil(const <int>[
        13,
        10,
        13,
        10,
      ], maxBytes: maxResponseHeaderBytes);
      final responseHead = _HttpResponseHead.parse(headerBytes);
      if (responseHead.isRedirect) {
        final location = responseHead.singleHeader('location');
        if (location == null || location.trim().isEmpty) {
          throw const OcrProviderException(
            kind: OcrProviderErrorKind.invalidResponse,
            message: 'Remote OCR image redirect is invalid.',
          );
        }
        return _RemoteResponse.redirect(location.trim());
      }
      if (responseHead.statusCode != 200) {
        // 诊断：读取并输出被拒响应体（如 403 的拒绝原因），便于区分
        // 签名过期 / UA-Referer 防盗链 / 风控挑战；脱敏后仅用于 Logcat。
        final errorBody = await _readErrorBody(reader);
        debugPrint(
          '[AIRecipe][RemoteImage] 下载被拒 status=${responseHead.statusCode} '
          'reason=$errorBody',
        );
        throw _statusException(responseHead.statusCode);
      }

      final mimeType = _normalizeMimeType(
        responseHead.singleHeader('content-type'),
      );
      if (mimeType == null) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Remote OCR image response MIME type is unsupported.',
        );
      }
      final contentLength = responseHead.contentLength;
      final chunked = responseHead.isChunked;
      if (contentLength != null && chunked) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Remote OCR image response framing is invalid.',
        );
      }
      if (contentLength != null && contentLength > maxBytes) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidInput,
          message: 'Remote OCR image exceeds the allowed byte limit.',
        );
      }

      final output = await destination.open(mode: FileMode.writeOnly);
      var byteLength = 0;
      try {
        Future<void> write(List<int> bytes) async {
          operation.throwIfStopped();
          byteLength += bytes.length;
          if (byteLength > maxBytes) {
            throw const OcrProviderException(
              kind: OcrProviderErrorKind.invalidInput,
              message: 'Remote OCR image exceeds the allowed byte limit.',
            );
          }
          await operation.wait(
            output.writeFrom(bytes),
            phaseTimeout: responseTimeout,
          );
        }

        if (chunked) {
          await _readChunkedBody(reader, write);
        } else if (contentLength != null) {
          var remaining = contentLength;
          while (remaining > 0) {
            final next = await reader.readUpTo(min(remaining, 64 * 1024));
            if (next.isEmpty) {
              throw const OcrProviderException(
                kind: OcrProviderErrorKind.invalidResponse,
                message: 'Remote OCR image response ended unexpectedly.',
              );
            }
            await write(next);
            remaining -= next.length;
          }
        } else {
          while (true) {
            final next = await reader.readAvailable();
            if (next == null) break;
            await write(next);
          }
        }
        await operation.wait(output.flush(), phaseTimeout: responseTimeout);
      } finally {
        await output.close();
      }
      if (byteLength == 0) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Remote OCR image response body is empty.',
        );
      }
      return _RemoteResponse.success(
        mimeType: mimeType,
        byteLength: byteLength,
      );
    } finally {
      operation.connection = null;
      if (connection != null) {
        connection.destroy();
        try {
          await connection.close();
        } catch (_) {}
      }
    }
  }

  Future<void> _readChunkedBody(
    _ConnectionReader reader,
    Future<void> Function(List<int> bytes) write,
  ) async {
    while (true) {
      final lineBytes = await reader.readUntil(const <int>[
        13,
        10,
      ], maxBytes: 8192);
      final line = ascii.decode(lineBytes, allowInvalid: false).trim();
      final size = int.tryParse(line.split(';').first.trim(), radix: 16);
      if (size == null || size < 0) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Remote OCR image chunk framing is invalid.',
        );
      }
      if (size == 0) {
        var trailerBytes = 0;
        while (true) {
          final trailer = await reader.readUntil(const <int>[
            13,
            10,
          ], maxBytes: maxResponseHeaderBytes);
          trailerBytes += trailer.length + 2;
          if (trailerBytes > maxResponseHeaderBytes) {
            throw const OcrProviderException(
              kind: OcrProviderErrorKind.invalidResponse,
              message: 'Remote OCR image response trailers are too large.',
            );
          }
          if (trailer.isEmpty) return;
        }
      }
      if (size > maxBytes) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidInput,
          message: 'Remote OCR image exceeds the allowed byte limit.',
        );
      }
      final data = await reader.readExact(size);
      final terminator = await reader.readExact(2);
      if (terminator[0] != 13 || terminator[1] != 10) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Remote OCR image chunk framing is invalid.',
        );
      }
      await write(data);
    }
  }

  static String _buildRequest(Uri uri) {
    final withoutFragment = uri.replace(fragment: '');
    final serialized = withoutFragment.toString();
    var target = serialized.substring(withoutFragment.origin.length);
    if (target.isEmpty) target = '/';
    if (target.startsWith('?')) target = '/$target';
    final formattedHost = _formatHost(uri.host);
    final host = uri.hasPort && uri.port != 443
        ? '$formattedHost:${uri.port}'
        : formattedHost;
    final buffer = StringBuffer()
      ..write('GET $target HTTP/1.1\r\n')
      ..write('Host: $host\r\n')
      ..write('Accept: image/jpeg, image/png, image/webp\r\n')
      ..write('Accept-Encoding: identity\r\n')
      ..write('Connection: close\r\n')
      // 公开平台图片 CDN 通常按浏览器 UA 与来源 Referer 防盗链；
      // 使用浏览器 UA 并按域名派生 Referer，避免裸请求被 403 拒绝。
      ..write(
        'User-Agent: Mozilla/5.0 (Linux; Android 14; Mobile) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/126.0.0.0 Mobile Safari/537.36\r\n',
      );
    final referer = _refererFor(uri.host);
    if (referer != null) {
      buffer.write('Referer: $referer\r\n');
    }
    buffer.write('\r\n');
    return buffer.toString();
  }

  /// 按图片域名派生来源 Referer：小红书/抖音 CDN 需要来源站防盗链。
  static String? _refererFor(String host) {
    final normalized = host.toLowerCase();
    if (normalized.endsWith('xiaohongshu.com') ||
        normalized.endsWith('xhscdn.com') ||
        normalized.endsWith('xhscdn.org')) {
      return 'https://www.xiaohongshu.com/';
    }
    if (normalized.endsWith('douyin.com') ||
        normalized.endsWith('iesdouyin.com')) {
      return 'https://www.douyin.com/';
    }
    return null;
  }

  static String _formatHost(String host) =>
      host.contains(':') ? '[$host]' : host;

  static String? _normalizeMimeType(String? raw) {
    if (raw == null) return null;
    final normalized = raw.split(';').first.trim().toLowerCase();
    return switch (normalized) {
      'image/jpeg' || 'image/jpg' => 'image/jpeg',
      'image/png' => 'image/png',
      'image/webp' => 'image/webp',
      _ => null,
    };
  }

  /// 读取被拒响应体前缀（最多 512 字节），用于诊断 CDN 拒绝原因。
  ///
  /// 读取失败不阻塞错误上报；内容仅用于 Logcat 诊断，不做用户可见文案。
  Future<String> _readErrorBody(_ConnectionReader reader) async {
    final buffer = <int>[];
    try {
      while (buffer.length < 512) {
        final next = await reader.readAvailable();
        if (next == null) break;
        buffer.addAll(next);
      }
    } catch (_) {
      // 读取失败不阻塞错误上报。
    }
    final decoded = utf8.decode(buffer, allowMalformed: true);
    final normalized = decoded.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (normalized.length <= 512) return normalized;
    return normalized.substring(0, 512);
  }

  static OcrProviderException _statusException(int statusCode) {
    if (statusCode == 408 || statusCode == 504) {
      return OcrProviderException(
        kind: OcrProviderErrorKind.timeout,
        message: 'Remote OCR image server timed out.',
        statusCode: statusCode,
      );
    }
    if (statusCode == 429) {
      return OcrProviderException(
        kind: OcrProviderErrorKind.rateLimited,
        message: 'Remote OCR image server rate limit was reached.',
        statusCode: statusCode,
      );
    }
    if (statusCode >= 500) {
      return OcrProviderException(
        kind: OcrProviderErrorKind.networkUnavailable,
        message: 'Remote OCR image server is unavailable.',
        statusCode: statusCode,
      );
    }
    return OcrProviderException(
      kind: OcrProviderErrorKind.invalidResponse,
      message: 'Remote OCR image server rejected the request.',
      statusCode: statusCode,
    );
  }
}

Future<OcrPinnedHttpsConnection> _connectPinnedTls({
  required Uri uri,
  required InternetAddress address,
  required Duration connectionTimeout,
  required Duration tlsTimeout,
  ImportCancellationToken? cancellationToken,
}) async {
  cancellationToken?.throwIfCancelled();
  ConnectionTask<Socket>? task;
  Socket? rawSocket;
  try {
    task = await Socket.startConnect(address, uri.port);
    final connectFuture = task.socket.timeout(connectionTimeout);
    rawSocket = cancellationToken == null
        ? await connectFuture
        : await Future.any<Socket>(<Future<Socket>>[
            connectFuture,
            cancellationToken.whenCancelled.then<Socket>((_) {
              task?.cancel();
              throw const ImportOperationCancelledException();
            }),
          ]);
    cancellationToken?.throwIfCancelled();
    final secureFuture = SecureSocket.secure(
      rawSocket,
      host: uri.host,
    ).timeout(tlsTimeout);
    final secureSocket = cancellationToken == null
        ? await secureFuture
        : await Future.any<SecureSocket>(<Future<SecureSocket>>[
            secureFuture,
            cancellationToken.whenCancelled.then<SecureSocket>((_) {
              rawSocket?.destroy();
              throw const ImportOperationCancelledException();
            }),
          ]);
    return _SocketPinnedHttpsConnection(secureSocket);
  } on TimeoutException {
    task?.cancel();
    rawSocket?.destroy();
    throw const _OcrDownloadTimeout();
  } catch (_) {
    task?.cancel();
    rawSocket?.destroy();
    rethrow;
  }
}

class _SocketPinnedHttpsConnection implements OcrPinnedHttpsConnection {
  _SocketPinnedHttpsConnection(this._socket);

  final SecureSocket _socket;

  @override
  Stream<List<int>> get incoming => _socket;

  @override
  void add(List<int> bytes) => _socket.add(bytes);

  @override
  Future<void> flush() => _socket.flush();

  @override
  Future<void> close() => _socket.close();

  @override
  void destroy() => _socket.destroy();
}

class _DownloadOperation {
  _DownloadOperation({
    required this.cancellationToken,
    required Duration totalTimeout,
  }) : _deadline = DateTime.now().add(totalTimeout) {
    final token = cancellationToken;
    if (token != null) {
      unawaited(
        token.whenCancelled.then((_) {
          if (_active) connection?.destroy();
        }),
      );
    }
  }

  final ImportCancellationToken? cancellationToken;
  final DateTime _deadline;
  OcrPinnedHttpsConnection? connection;
  bool _active = true;

  Duration limit(Duration requested) {
    final remaining = _deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) throw const _OcrDownloadTimeout();
    return remaining < requested ? remaining : requested;
  }

  Future<T> wait<T>(Future<T> future, {required Duration phaseTimeout}) async {
    throwIfStopped();
    final timed = future.timeout(
      limit(phaseTimeout),
      onTimeout: () {
        connection?.destroy();
        throw const _OcrDownloadTimeout();
      },
    );
    final token = cancellationToken;
    if (token == null) return timed;
    return Future.any<T>(<Future<T>>[
      timed,
      token.whenCancelled.then<T>((_) {
        connection?.destroy();
        throw const ImportOperationCancelledException();
      }),
    ]);
  }

  void throwIfStopped() {
    cancellationToken?.throwIfCancelled();
    if (DateTime.now().isAfter(_deadline)) {
      connection?.destroy();
      throw const _OcrDownloadTimeout();
    }
  }

  void finish() {
    _active = false;
    connection = null;
  }
}

class _ConnectionReader {
  _ConnectionReader(
    Stream<List<int>> incoming, {
    required _DownloadOperation operation,
    required Duration responseTimeout,
  }) : _iterator = StreamIterator<List<int>>(incoming),
       _operation = operation,
       _responseTimeout = responseTimeout;

  final StreamIterator<List<int>> _iterator;
  final _DownloadOperation _operation;
  final Duration _responseTimeout;
  final List<int> _buffer = <int>[];
  bool _done = false;

  Future<List<int>> readUntil(
    List<int> delimiter, {
    required int maxBytes,
  }) async {
    if (delimiter.isEmpty || maxBytes < 0) {
      throw ArgumentError('Reader limits must be valid.');
    }
    while (true) {
      final delimiterIndex = _indexOf(_buffer, delimiter);
      if (delimiterIndex >= 0) {
        if (delimiterIndex > maxBytes) {
          throw const OcrProviderException(
            kind: OcrProviderErrorKind.invalidResponse,
            message: 'Remote OCR image response framing is too large.',
          );
        }
        final result = List<int>.of(_buffer.take(delimiterIndex));
        _buffer.removeRange(0, delimiterIndex + delimiter.length);
        return result;
      }
      if (_buffer.length > maxBytes + delimiter.length - 1) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Remote OCR image response framing is too large.',
        );
      }
      if (!await _readMore()) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Remote OCR image response ended unexpectedly.',
        );
      }
    }
  }

  Future<List<int>> readExact(int length) async {
    if (length < 0) throw ArgumentError.value(length, 'length');
    while (_buffer.length < length && await _readMore()) {}
    if (_buffer.length < length) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: 'Remote OCR image response ended unexpectedly.',
      );
    }
    return _take(length);
  }

  Future<List<int>> readUpTo(int maxLength) async {
    if (maxLength <= 0) throw ArgumentError.value(maxLength, 'maxLength');
    if (_buffer.isEmpty && !await _readMore()) return const <int>[];
    return _take(min(maxLength, _buffer.length));
  }

  Future<List<int>?> readAvailable() async {
    if (_buffer.isEmpty && !await _readMore()) return null;
    return _take(_buffer.length);
  }

  Future<bool> _readMore() async {
    if (_done) return false;
    final hasNext = await _operation.wait(
      _iterator.moveNext(),
      phaseTimeout: _responseTimeout,
    );
    if (!hasNext) {
      _done = true;
      return false;
    }
    final next = _iterator.current;
    if (next.isNotEmpty) _buffer.addAll(next);
    return true;
  }

  List<int> _take(int length) {
    final result = List<int>.of(_buffer.take(length));
    _buffer.removeRange(0, length);
    return result;
  }

  static int _indexOf(List<int> bytes, List<int> delimiter) {
    final lastStart = bytes.length - delimiter.length;
    for (var start = 0; start <= lastStart; start += 1) {
      var matches = true;
      for (var offset = 0; offset < delimiter.length; offset += 1) {
        if (bytes[start + offset] != delimiter[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) return start;
    }
    return -1;
  }
}

class _HttpResponseHead {
  _HttpResponseHead({required this.statusCode, required this.headers});

  final int statusCode;
  final Map<String, List<String>> headers;

  bool get isRedirect =>
      const <int>{301, 302, 303, 307, 308}.contains(statusCode);

  int? get contentLength {
    final raw = singleHeader('content-length');
    if (raw == null) return null;
    final normalized = raw.trim();
    if (!RegExp(r'^[0-9]+$').hasMatch(normalized)) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: 'Remote OCR image content length is invalid.',
      );
    }
    final parsed = int.tryParse(normalized);
    if (parsed == null || parsed < 0) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: 'Remote OCR image content length is invalid.',
      );
    }
    return parsed;
  }

  bool get isChunked {
    final raw = singleHeader('transfer-encoding');
    if (raw == null) return false;
    final codings = raw
        .split(',')
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (codings.length != 1 || codings.single != 'chunked') {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: 'Remote OCR image transfer encoding is unsupported.',
      );
    }
    return true;
  }

  String? singleHeader(String name) {
    final values = headers[name.toLowerCase()];
    if (values == null || values.isEmpty) return null;
    if (values.length != 1) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: 'Remote OCR image response contains duplicate headers.',
      );
    }
    return values.single;
  }

  static _HttpResponseHead parse(List<int> bytes) {
    String decoded;
    try {
      decoded = ascii.decode(bytes, allowInvalid: false);
    } on FormatException {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: 'Remote OCR image response headers are invalid.',
      );
    }
    final lines = decoded.split('\r\n');
    if (lines.isEmpty) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: 'Remote OCR image response status is invalid.',
      );
    }
    final statusMatch = RegExp(
      r'^HTTP/1\.[01] ([0-9]{3})(?: .*)?$',
    ).firstMatch(lines.first);
    final statusCode = statusMatch == null
        ? null
        : int.tryParse(statusMatch.group(1)!);
    if (statusCode == null || statusCode < 100 || statusCode > 599) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: 'Remote OCR image response status is invalid.',
      );
    }

    final headers = <String, List<String>>{};
    final fieldNamePattern = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
    for (final line in lines.skip(1)) {
      if (line.isEmpty || line.startsWith(' ') || line.startsWith('\t')) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Remote OCR image response headers are invalid.',
        );
      }
      final separator = line.indexOf(':');
      if (separator <= 0) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Remote OCR image response headers are invalid.',
        );
      }
      final name = line.substring(0, separator).trim().toLowerCase();
      if (!fieldNamePattern.hasMatch(name)) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Remote OCR image response headers are invalid.',
        );
      }
      final value = line.substring(separator + 1).trim();
      if (value.codeUnits.any((unit) => unit < 0x20 && unit != 0x09)) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Remote OCR image response headers are invalid.',
        );
      }
      headers.putIfAbsent(name, () => <String>[]).add(value);
    }

    for (final name in const <String>{
      'content-length',
      'content-type',
      'transfer-encoding',
      'location',
    }) {
      if ((headers[name]?.length ?? 0) > 1) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Remote OCR image response contains duplicate headers.',
        );
      }
    }
    return _HttpResponseHead(statusCode: statusCode, headers: headers);
  }
}

class _RemoteResponse {
  const _RemoteResponse.redirect(this.location)
    : mimeType = null,
      byteLength = null;

  const _RemoteResponse.success({
    required this.mimeType,
    required this.byteLength,
  }) : location = null;

  final String? location;
  final String? mimeType;
  final int? byteLength;

  bool get isRedirect => location != null;
}

class _OcrDownloadTimeout implements Exception {
  const _OcrDownloadTimeout();
}
