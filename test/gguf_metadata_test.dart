import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:echo/services/gguf_metadata.dart';

/// Minimal GGUF v3 writer for tests (header + metadata only).
class _GgufBuilder {
  final _b = BytesBuilder();
  int _kv = 0;
  final _body = BytesBuilder();

  void _u32(BytesBuilder b, int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void _u64(BytesBuilder b, int v) =>
      b.add((ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List());
  void _str(BytesBuilder b, String s) {
    final bytes = utf8.encode(s);
    _u64(b, bytes.length);
    b.add(bytes);
  }

  void string(String key, String value) {
    _kv++;
    _str(_body, key);
    _u32(_body, 8);
    _str(_body, value);
  }

  void u32(String key, int value) {
    _kv++;
    _str(_body, key);
    _u32(_body, 4);
    _u32(_body, value);
  }

  void stringArray(String key, int count) {
    _kv++;
    _str(_body, key);
    _u32(_body, 9);
    _u32(_body, 8);
    _u64(_body, count);
    for (var i = 0; i < count; i++) {
      _str(_body, 'tok$i');
    }
  }

  void floatArray(String key, int count) {
    _kv++;
    _str(_body, key);
    _u32(_body, 9);
    _u32(_body, 6);
    _u64(_body, count);
    _body.add(Uint8List(count * 4));
  }

  Uint8List build({int padTo = 0}) {
    _b.add(ascii.encode('GGUF'));
    _u32(_b, 3);
    _u64(_b, 0);
    _u64(_b, _kv);
    _b.add(_body.takeBytes());
    if (_b.length < padTo) _b.add(Uint8List(padTo - _b.length));
    return _b.takeBytes();
  }
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('gguf_test'));
  tearDown(() => dir.delete(recursive: true));

  Future<String> write(Uint8List bytes) async {
    final f = File('${dir.path}/m.gguf');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  // Shaped like Qwen2.5-1.5B: 28 layers, 1536 dim, 12 heads, 2 KV heads.
  Uint8List qwenLike({int padTo = 0}) {
    final g = _GgufBuilder()
      ..string('general.architecture', 'qwen2')
      ..string('general.name', 'Qwen2.5 1.5B Instruct')
      // Large vocab arrays before the arch keys: the reader must skip them.
      ..stringArray('tokenizer.ggml.tokens', 150000)
      ..floatArray('tokenizer.ggml.scores', 150000)
      ..u32('qwen2.block_count', 28)
      ..u32('qwen2.context_length', 32768)
      ..u32('qwen2.embedding_length', 1536)
      ..u32('qwen2.attention.head_count', 12)
      ..u32('qwen2.attention.head_count_kv', 2);
    return g.build(padTo: padTo);
  }

  test('reads architecture fields, skipping large tokenizer arrays', () async {
    final info = await readGgufInfo(await write(qwenLike()));
    expect(info, isNotNull);
    expect(info!.architecture, 'qwen2');
    expect(info.name, 'Qwen2.5 1.5B Instruct');
    expect(info.layers, 28);
    expect(info.trainedContext, 32768);
    expect(info.headCountKv, 2);
  });

  test('KV cache follows llama.cpp f16 sizing', () async {
    final info = (await readGgufInfo(await write(qwenLike())))!;
    // 28 layers * 4096 ctx * 2 kv heads * (128 + 128) * 2 bytes = 112 MiB
    expect(info.kvCacheBytes(4096), 28 * 4096 * 2 * 256 * 2);
    expect(info.kvCacheBytes(4096), 112 * 1024 * 1024);
  });

  test('suggests a smaller context when the requested one does not fit',
      () async {
    final info = (await readGgufInfo(await write(qwenLike())))!;
    final at32k = info.estimateBytes(32768);
    final fit = info.maxContextFitting(at32k - 200 * 1024 * 1024);
    expect(fit, isNotNull);
    expect(fit! % 512, 0);
    expect(fit, lessThan(32768));
    expect(info.estimateBytes(fit), lessThanOrEqualTo(at32k - 200 * 1024 * 1024));
  });

  test('returns null for non-GGUF or incomplete files', () async {
    expect(await readGgufInfo(await write(Uint8List.fromList(utf8.encode('nope')))),
        isNull);
    final truncated = qwenLike().sublist(0, 2000);
    expect(await readGgufInfo(await write(truncated)), isNull);
    expect(await readGgufInfo('${dir.path}/missing.gguf'), isNull);
  });
}
