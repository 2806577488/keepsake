#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""APK 的 ABI 声明自检（E-01 / N-1）。

为什么需要：Flutter 只把引擎库（libflutter/libapp/libsqlite3）放进目标 ABI 目录，
但插件的 .so 会被 AGP 打进所有 ABI 目录。于是 APK 的 `native-code` 会声明三个 ABI，
而只有一个是完整的 → 不支持的那个 ABI 设备装得上、启动即 `UnsatisfiedLinkError`。

本脚本对 APK 里**每一个** `lib/<abi>/` 目录检查是否带 `libflutter.so`，
只要有一个 ABI 目录缺，就说明这个包装到对应设备上必崩。

用法：
    python tool/check_apk_abi.py build/app/outputs/flutter-apk/app-release.apk

退出码：0 = 全部 ABI 都带引擎库；1 = 有问题；2 = 用法/文件错误。
"""

import os
import sys
import zipfile


def main() -> int:
    if len(sys.argv) != 2:
        print('用法: python tool/check_apk_abi.py <apk>')
        return 2
    path = sys.argv[1]
    if not os.path.isfile(path):
        print('找不到 APK: %s' % path)
        return 2

    with zipfile.ZipFile(path) as apk:
        names = apk.namelist()

    libs = {}
    for name in names:
        if not name.startswith('lib/') or not name.endswith('.so'):
            continue
        parts = name.split('/')
        if len(parts) < 3:
            continue
        libs.setdefault(parts[1], set()).add(parts[2])

    if not libs:
        print('APK 里没有 lib/ 目录：%s' % path)
        return 1

    missing = []
    for abi in sorted(libs):
        files = libs[abi]
        has_engine = 'libflutter.so' in files
        print('%-12s %2d 个 .so，libflutter.so %s' % (
            abi, len(files), '有' if has_engine else '**缺**'))
        if not has_engine:
            missing.append(abi)

    if missing:
        print('')
        print('FAIL: 下列 ABI 目录会被系统选中、但缺 libflutter.so —— 装到对应设备上启动即崩：')
        print('      ' + ', '.join(missing))
        print('      修法：构建时只声明目标 ABI（android/app/build.gradle.kts 的 abiFilters）')
        return 1

    print('')
    print('OK: 所有声明的 ABI 都带 libflutter.so（%s）' % ', '.join(sorted(libs)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
