// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi';
import 'dart:io';

import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';

typedef ProcessBytesNative = Uint32 Function(
  Uint32 id,
  Pointer<Uint8> payload,
  Uint64 payloadLen,
  Pointer<Pointer<Uint8>> outPtr,
  Pointer<Uint64> outLen,
);

typedef ProcessBytesDart = int Function(
  int id,
  Pointer<Uint8> payload,
  int payloadLen,
  Pointer<Pointer<Uint8>> outPtr,
  Pointer<Uint64> outLen,
);

// Free function
typedef FreeBytesNative = Void Function(Pointer<Uint8> ptr, IntPtr len);
typedef FreeBytesDart = void Function(Pointer<Uint8> ptr, int len);
typedef PosixCallocNative = Pointer Function(IntPtr num, IntPtr size);
typedef PosixFreeNative = Void Function(Pointer);
typedef WinCoTaskMemAllocNative = Pointer Function(NSize);
typedef WinCoTaskMemAlloc = Pointer Function(int);
typedef WinCoTaskMemFreeNative = Void Function(Pointer);
typedef WinCoTaskMemFree = void Function(Pointer);
@Native<PosixCallocNative>(symbol: 'calloc')
external Pointer posixCalloc(int num, int size);
final Pointer<NativeFunction<PosixFreeNative>> posixFreePointer =
    Native.addressOf(posixFree);
const CallocAllocator calloc = CallocAllocator._();

final DynamicLibrary ole32lib = DynamicLibrary.open('ole32.dll');
final WinCoTaskMemAlloc winCoTaskMemAlloc =
    ole32lib.lookupFunction<WinCoTaskMemAllocNative, WinCoTaskMemAlloc>(
        'CoTaskMemAlloc');
final Pointer<NativeFunction<WinCoTaskMemFreeNative>> winCoTaskMemFreePointer =
    ole32lib.lookup('CoTaskMemFree');
final WinCoTaskMemFree winCoTaskMemFree = winCoTaskMemFreePointer.asFunction();
@Native<Void Function(Pointer)>(symbol: 'free')
external void posixFree(Pointer ptr);

@AbiSpecificIntegerMapping({
  Abi.androidArm: Uint32(),
  Abi.androidArm64: Uint64(),
  Abi.androidIA32: Uint32(),
  Abi.androidX64: Uint64(),
  Abi.androidRiscv64: Uint64(),
  Abi.fuchsiaArm64: Uint64(),
  Abi.fuchsiaX64: Uint64(),
  Abi.fuchsiaRiscv64: Uint64(),
  Abi.iosArm: Uint32(),
  Abi.iosArm64: Uint64(),
  Abi.iosX64: Uint64(),
  Abi.linuxArm: Uint32(),
  Abi.linuxArm64: Uint64(),
  Abi.linuxIA32: Uint32(),
  Abi.linuxX64: Uint64(),
  Abi.linuxRiscv32: Uint32(),
  Abi.linuxRiscv64: Uint64(),
  Abi.macosArm64: Uint64(),
  Abi.macosX64: Uint64(),
  Abi.windowsArm64: Uint64(),
  Abi.windowsIA32: Uint32(),
  Abi.windowsX64: Uint64(),
})
final class NSize extends AbiSpecificInteger {
  const NSize();
}

final class CallocAllocator implements Allocator {
  const CallocAllocator._();

  void _fillMemory(Pointer destination, int length, int fill) {
    final ptr = destination.cast<Uint8>();
    for (var i = 0; i < length; i++) {
      ptr[i] = fill;
    }
  }

  void _zeroMemory(Pointer destination, int length) =>
      _fillMemory(destination, length, 0);

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    Pointer<T> result;
    if (Platform.isWindows) {
      result = winCoTaskMemAlloc(byteCount).cast();
    } else {
      result = posixCalloc(byteCount, 1).cast();
    }
    if (result.address == 0) {
      throw ZKLibException('Could not allocate $byteCount bytes.');
    }
    if (Platform.isWindows) {
      _zeroMemory(result, byteCount);
    }
    return result;
  }

  @override
  void free(Pointer pointer) {
    if (Platform.isWindows) {
      winCoTaskMemFree(pointer);
    } else {
      posixFree(pointer);
    }
  }

  Pointer<NativeFinalizerFunction> get nativeFree =>
      Platform.isWindows ? winCoTaskMemFreePointer : posixFreePointer;
}
