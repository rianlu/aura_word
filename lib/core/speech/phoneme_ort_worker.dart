import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const _ortApiVersion = 28;

class PhonemeOrtOutput {
  final Float32List values;
  final int frames;
  final int vocab;

  const PhonemeOrtOutput({
    required this.values,
    required this.frames,
    required this.vocab,
  });
}

class PhonemeOrtClient {
  Isolate? _isolate;
  SendPort? _commands;
  final ReceivePort _replies = ReceivePort();
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  var _ready = false;

  PhonemeOrtClient() {
    _replies.listen((message) {
      if (message is SendPort) {
        _commands = message;
        _ready = true;
        return;
      }
      if (message is! Map) return;
      final id = message['id'] as int?;
      final completer = id == null ? null : _pending.remove(id);
      if (completer == null) return;
      if (message['ok'] == true) {
        completer.complete(message['result']);
      } else {
        completer.completeError(StateError('${message['error']}'));
      }
    });
  }

  Future<void> open(String modelPath) async {
    _isolate ??= await Isolate.spawn(_phonemeOrtMain, _replies.sendPort);
    while (!_ready) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await _call('open', {'path': modelPath});
  }

  Future<PhonemeOrtOutput> run(Float32List samples) async {
    final result = await _call('run', {'samples': samples});
    if (result is! Map) {
      throw StateError('音素评分结果异常');
    }
    return PhonemeOrtOutput(
      values: result['values'] as Float32List,
      frames: result['frames'] as int,
      vocab: result['vocab'] as int,
    );
  }

  Future<void> close() async {
    final isolate = _isolate;
    if (_commands != null && _ready) {
      try {
        await _call('close', {}).timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    _commands = null;
    _isolate = null;
    _ready = false;
    isolate?.kill(priority: Isolate.immediate);
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('音素评分已关闭'));
      }
    }
    _pending.clear();
  }

  Future<Object?> _call(String command, Map<String, Object?> args) {
    final commands = _commands;
    if (commands == null) {
      throw StateError('音素评分还没准备好');
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    commands.send({'id': id, 'cmd': command, ...args});
    return completer.future;
  }
}

void _phonemeOrtMain(SendPort replies) {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  _SherpaOrt? ort;
  commands.listen((message) {
    if (message is! Map) return;
    final id = message['id'];
    try {
      final cmd = message['cmd'];
      Object? result;
      if (cmd == 'open') {
        final session = ort ?? _SherpaOrt();
        ort = session;
        session.open(message['path'] as String);
      } else if (cmd == 'run') {
        final session = ort;
        if (session == null) {
          throw StateError('音素评分还没准备好');
        }
        final output = session.run(message['samples'] as Float32List);
        result = {
          'values': output.values,
          'frames': output.frames,
          'vocab': output.vocab,
        };
      } else if (cmd == 'close') {
        ort?.close();
        ort = null;
      }
      replies.send({'id': id, 'ok': true, 'result': result});
    } catch (e) {
      replies.send({'id': id, 'ok': false, 'error': e.toString()});
    }
  });
}

class _SherpaOrt {
  late final DynamicLibrary _library;
  late final Pointer<Void> _api;
  Pointer<Void> _env = nullptr;
  Pointer<Void> _session = nullptr;
  String _inputName = 'input_values';
  String _outputName = 'logits';
  var _opened = false;

  void open(String modelPath) {
    if (_opened) return;
    _library = DynamicLibrary.open('libonnxruntime.so');
    final base = _library
        .lookupFunction<
          Pointer<OrtApiBase> Function(),
          Pointer<OrtApiBase> Function()
        >('OrtGetApiBase')();
    final getApi = base.ref.getApi
        .asFunction<Pointer<Void> Function(int)>();
    _api = getApi(_ortApiVersion);
    if (_api == nullptr) {
      throw StateError('音素评分引擎版本不匹配');
    }

    final logId = 'aura'.toNativeUtf8();
    final envOut = calloc<Pointer<Void>>();
    try {
      _check(_slot<CreateEnvNative>(3).asFunction<CreateEnvDart>()(2, logId, envOut));
      _env = envOut.value;
    } finally {
      calloc.free(logId);
      calloc.free(envOut);
    }

    final optionsOut = calloc<Pointer<Void>>();
    Pointer<Void> options = nullptr;
    try {
      _check(_slot<CreateOptionsNative>(10).asFunction<CreateOptionsDart>()(optionsOut));
      options = optionsOut.value;
      _check(_slot<SetOptLevelNative>(23).asFunction<SetOptLevelDart>()(options, 2));
      _check(_slot<SetThreadsNative>(24).asFunction<SetThreadsDart>()(options, 4));
      final path = modelPath.toNativeUtf8();
      final sessionOut = calloc<Pointer<Void>>();
      try {
        _check(_slot<CreateSessionNative>(7).asFunction<CreateSessionDart>()(_env, path, options, sessionOut));
        _session = sessionOut.value;
      } finally {
        calloc.free(path);
        calloc.free(sessionOut);
      }
    } finally {
      calloc.free(optionsOut);
      if (options != nullptr) {
        _slot<ReleaseOneNative>(100).asFunction<ReleaseOneDart>()(options);
      }
    }

    _inputName = _sessionName(input: true) ?? _inputName;
    _outputName = _sessionName(input: false) ?? _outputName;
    _opened = true;
  }

  PhonemeOrtOutput run(Float32List samples) {
    final memoryOut = calloc<Pointer<Void>>();
    final tensorOut = calloc<Pointer<Void>>();
    final data = calloc<Float>(samples.length);
    final shape = calloc<Int64>(2);
    final inputNames = calloc<Pointer<Utf8>>();
    final inputs = calloc<Pointer<Void>>();
    final outputNames = calloc<Pointer<Utf8>>();
    final outputs = calloc<Pointer<Void>>();
    final inputName = _inputName.toNativeUtf8();
    final outputName = _outputName.toNativeUtf8();
    Pointer<Void> memory = nullptr;
    Pointer<Void> tensor = nullptr;
    Pointer<Void> output = nullptr;
    try {
      _check(_slot<CreateMemoryNative>(69).asFunction<CreateMemoryDart>()(1, 0, memoryOut));
      memory = memoryOut.value;
      data.asTypedList(samples.length).setAll(0, samples);
      shape[0] = 1;
      shape[1] = samples.length;
      _check(
        _slot<CreateTensorNative>(49).asFunction<CreateTensorDart>()(
          memory,
          data.cast(),
          samples.length * 4,
          shape,
          2,
          1,
          tensorOut,
        ),
      );
      tensor = tensorOut.value;
      inputNames.value = inputName;
      inputs.value = tensor;
      outputNames.value = outputName;
      _check(
        _slot<RunNative>(9).asFunction<RunDart>()(
          _session,
          nullptr,
          inputNames,
          inputs,
          1,
          outputNames,
          1,
          outputs,
        ),
      );
      output = outputs.value;
      return _readOutput(output);
    } finally {
      if (output != nullptr) _slot<ReleaseOneNative>(96).asFunction<ReleaseOneDart>()(output);
      if (tensor != nullptr) _slot<ReleaseOneNative>(96).asFunction<ReleaseOneDart>()(tensor);
      if (memory != nullptr) _slot<ReleaseOneNative>(94).asFunction<ReleaseOneDart>()(memory);
      calloc.free(memoryOut);
      calloc.free(tensorOut);
      calloc.free(data);
      calloc.free(shape);
      calloc.free(inputNames);
      calloc.free(inputs);
      calloc.free(outputNames);
      calloc.free(outputs);
      calloc.free(inputName);
      calloc.free(outputName);
    }
  }

  void close() {
    if (_session != nullptr) {
      _slot<ReleaseOneNative>(95).asFunction<ReleaseOneDart>()(_session);
      _session = nullptr;
    }
    if (_env != nullptr) {
      _slot<ReleaseOneNative>(92).asFunction<ReleaseOneDart>()(_env);
      _env = nullptr;
    }
    _opened = false;
  }

  PhonemeOrtOutput _readOutput(Pointer<Void> value) {
    final infoOut = calloc<Pointer<Void>>();
    final countOut = calloc<IntPtr>();
    final typeOut = calloc<Int32>();
    final dataOut = calloc<Pointer<Void>>();
    Pointer<Void> info = nullptr;
    Pointer<Int64> dims = nullptr;
    try {
      _check(_slot<GetTypeNative>(65).asFunction<GetTypeDart>()(value, infoOut));
      info = infoOut.value;
      _check(_slot<GetTypeCodeNative>(60).asFunction<GetTypeCodeDart>()(info, typeOut));
      if (typeOut.value != 1) {
        throw StateError('音素评分结果不是浮点数据');
      }
      _check(_slot<GetDimCountNative>(61).asFunction<GetDimCountDart>()(info, countOut));
      final rank = countOut.value;
      if (rank < 2) {
        throw StateError('音素评分结果异常');
      }
      dims = calloc<Int64>(rank);
      _check(_slot<GetDimsNative>(62).asFunction<GetDimsDart>()(info, dims, rank));
      var count = 1;
      final shape = <int>[];
      for (var i = 0; i < rank; i++) {
        final dim = dims[i];
        shape.add(dim);
        count *= dim;
      }
      _check(_slot<GetDataNative>(51).asFunction<GetDataDart>()(value, dataOut));
      final values = Float32List.fromList(
        dataOut.value.cast<Float>().asTypedList(count),
      );
      return PhonemeOrtOutput(
        values: values,
        frames: shape[shape.length - 2],
        vocab: shape.last,
      );
    } finally {
      if (info != nullptr) _slot<ReleaseOneNative>(99).asFunction<ReleaseOneDart>()(info);
      if (dims != nullptr) calloc.free(dims);
      calloc.free(infoOut);
      calloc.free(countOut);
      calloc.free(typeOut);
      calloc.free(dataOut);
    }
  }

  String? _sessionName({required bool input}) {
    final allocatorOut = calloc<Pointer<Void>>();
    final countOut = calloc<IntPtr>();
    final nameOut = calloc<Pointer<Utf8>>();
    try {
      _check(_slot<GetAllocatorNative>(78).asFunction<GetAllocatorDart>()(allocatorOut));
      final allocator = allocatorOut.value;
      final countFn = input ? 30 : 31;
      final nameFn = input ? 36 : 37;
      _check(_slot<GetCountNative>(countFn).asFunction<GetCountDart>()(_session, countOut));
      if (countOut.value <= 0) return null;
      _check(_slot<GetNameNative>(nameFn).asFunction<GetNameDart>()(_session, 0, allocator, nameOut));
      final name = nameOut.value.toDartString();
      _slot<FreeNative>(76).asFunction<FreeDart>()(allocator, nameOut.value.cast());
      return name;
    } finally {
      calloc.free(allocatorOut);
      calloc.free(countOut);
      calloc.free(nameOut);
    }
  }

  Pointer<NativeFunction<T>> _slot<T extends Function>(int index) {
    return (_api.cast<Pointer<NativeFunction<T>>>() + index).value;
  }

  void _check(Pointer<Void> status) {
    if (status == nullptr) return;
    final message = _slot<ErrorMessageNative>(2).asFunction<ErrorMessageDart>()(status).toDartString();
    _slot<ReleaseOneNative>(93).asFunction<ReleaseOneDart>()(status);
    throw StateError(message.isEmpty ? '音素评分失败' : message);
  }
}

final class OrtApiBase extends Struct {
  external Pointer<NativeFunction<Pointer<Void> Function(Uint32)>> getApi;
  external Pointer<NativeFunction<Pointer<Utf8> Function()>> getVersionString;
}

typedef CreateEnvNative = Pointer<Void> Function(
  Int32 level,
  Pointer<Utf8> logId,
  Pointer<Pointer<Void>> out,
);
typedef CreateOptionsNative = Pointer<Void> Function(Pointer<Pointer<Void>> out);
typedef SetOptLevelNative = Pointer<Void> Function(Pointer<Void> options, Int32 level);
typedef SetThreadsNative = Pointer<Void> Function(Pointer<Void> options, Int32 threads);
typedef CreateSessionNative = Pointer<Void> Function(
  Pointer<Void> env,
  Pointer<Utf8> path,
  Pointer<Void> options,
  Pointer<Pointer<Void>> out,
);
typedef CreateMemoryNative = Pointer<Void> Function(
  Int32 allocatorType,
  Int32 memType,
  Pointer<Pointer<Void>> out,
);
typedef CreateTensorNative = Pointer<Void> Function(
  Pointer<Void> memory,
  Pointer<Void> data,
  IntPtr dataBytes,
  Pointer<Int64> shape,
  IntPtr rank,
  Int32 elementType,
  Pointer<Pointer<Void>> out,
);
typedef RunNative = Pointer<Void> Function(
  Pointer<Void> session,
  Pointer<Void> runOptions,
  Pointer<Pointer<Utf8>> inputNames,
  Pointer<Pointer<Void>> inputs,
  IntPtr inputCount,
  Pointer<Pointer<Utf8>> outputNames,
  IntPtr outputCount,
  Pointer<Pointer<Void>> outputs,
);
typedef GetTypeNative = Pointer<Void> Function(
  Pointer<Void> value,
  Pointer<Pointer<Void>> out,
);
typedef GetTypeCodeNative = Pointer<Void> Function(
  Pointer<Void> info,
  Pointer<Int32> out,
);
typedef GetDimCountNative = Pointer<Void> Function(
  Pointer<Void> info,
  Pointer<IntPtr> out,
);
typedef GetDimsNative = Pointer<Void> Function(
  Pointer<Void> info,
  Pointer<Int64> dims,
  IntPtr count,
);
typedef GetDataNative = Pointer<Void> Function(
  Pointer<Void> value,
  Pointer<Pointer<Void>> out,
);
typedef GetAllocatorNative = Pointer<Void> Function(Pointer<Pointer<Void>> out);
typedef GetCountNative = Pointer<Void> Function(
  Pointer<Void> session,
  Pointer<IntPtr> out,
);
typedef GetNameNative = Pointer<Void> Function(
  Pointer<Void> session,
  IntPtr index,
  Pointer<Void> allocator,
  Pointer<Pointer<Utf8>> out,
);
typedef FreeNative = Void Function(Pointer<Void> allocator, Pointer<Void> ptr);
typedef ReleaseOneNative = Void Function(Pointer<Void> value);
typedef ErrorMessageNative = Pointer<Utf8> Function(Pointer<Void> status);

typedef CreateEnvDart = Pointer<Void> Function(
  int level,
  Pointer<Utf8> logId,
  Pointer<Pointer<Void>> out,
);
typedef CreateOptionsDart = Pointer<Void> Function(Pointer<Pointer<Void>> out);
typedef SetOptLevelDart = Pointer<Void> Function(Pointer<Void> options, int level);
typedef SetThreadsDart = Pointer<Void> Function(Pointer<Void> options, int threads);
typedef CreateSessionDart = Pointer<Void> Function(
  Pointer<Void> env,
  Pointer<Utf8> path,
  Pointer<Void> options,
  Pointer<Pointer<Void>> out,
);
typedef CreateMemoryDart = Pointer<Void> Function(
  int allocatorType,
  int memType,
  Pointer<Pointer<Void>> out,
);
typedef CreateTensorDart = Pointer<Void> Function(
  Pointer<Void> memory,
  Pointer<Void> data,
  int dataBytes,
  Pointer<Int64> shape,
  int rank,
  int elementType,
  Pointer<Pointer<Void>> out,
);
typedef RunDart = Pointer<Void> Function(
  Pointer<Void> session,
  Pointer<Void> runOptions,
  Pointer<Pointer<Utf8>> inputNames,
  Pointer<Pointer<Void>> inputs,
  int inputCount,
  Pointer<Pointer<Utf8>> outputNames,
  int outputCount,
  Pointer<Pointer<Void>> outputs,
);
typedef GetTypeDart = Pointer<Void> Function(
  Pointer<Void> value,
  Pointer<Pointer<Void>> out,
);
typedef GetTypeCodeDart = Pointer<Void> Function(
  Pointer<Void> info,
  Pointer<Int32> out,
);
typedef GetDimCountDart = Pointer<Void> Function(
  Pointer<Void> info,
  Pointer<IntPtr> out,
);
typedef GetDimsDart = Pointer<Void> Function(
  Pointer<Void> info,
  Pointer<Int64> dims,
  int count,
);
typedef GetDataDart = Pointer<Void> Function(
  Pointer<Void> value,
  Pointer<Pointer<Void>> out,
);
typedef GetAllocatorDart = Pointer<Void> Function(Pointer<Pointer<Void>> out);
typedef GetCountDart = Pointer<Void> Function(
  Pointer<Void> session,
  Pointer<IntPtr> out,
);
typedef GetNameDart = Pointer<Void> Function(
  Pointer<Void> session,
  int index,
  Pointer<Void> allocator,
  Pointer<Pointer<Utf8>> out,
);
typedef FreeDart = void Function(Pointer<Void> allocator, Pointer<Void> ptr);
typedef ReleaseOneDart = void Function(Pointer<Void> value);
typedef ErrorMessageDart = Pointer<Utf8> Function(Pointer<Void> status);
