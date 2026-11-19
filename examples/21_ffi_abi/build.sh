#!/bin/sh
# 21_ffi_abi 的构建与运行：库 → 动态库 → 消费者。
set -e
cd "$(dirname "$0")"
NEX=${NEX:-../../bin/nex}

echo "① 构建动态库（C ABI 导出面）"
$NEX mylib.nex --crate-type cdylib -o libmylib.dylib

echo "② 构建消费者（@ffi.import 引用该库 + 系统 libc）"
$NEX main.nex --backend cpp -o ffi_demo

echo "③ 运行（dlopen 按相对路径加载 libmylib.dylib）"
./ffi_demo
