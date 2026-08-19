# HarmonyOS 原生图像核心状态

更新：2026-08-20

## 结论

**状态：`ok`（模拟器集成级）**

ArkTS 通过 `libsitemark_native.so` 的 C++ N-API 薄层调用 `sitemark_core` 的 JSON C ABI。实际拍摄回归中，`sha256` 和 `render` 均返回正常结果，记录从 `captured` 经 `rendering` 收敛到 `ready`，且水印成片可在列表、详情与系统保存面板中读取。归档、bundle、恢复抽取与诊断 ZIP 使用同一 Rust API，没有在 ArkTS 重写第二套图像或 ZIP 算法。

## 绑定方式

```text
ArkTS NativeImagePipeline
  -> C++ N-API call(string)
  -> sitemark_call_json / sitemark_string_free
  -> Rust image_core
```

- 只传文件路径和结构化 JSON，全分辨率图像不作为 ArkTS 字节数组跨边界复制。
- C ABI 捕获 Rust panic，返回稳定 `invalid_data:` 错误而不使应用进程越边。
- Rust 返回字符串只能用 `sitemark_string_free` 释放一次；N-API 薄层在转成 JS 字符串后立即释放。
- `build-rust.ps1` 使用 HarmonyOS native clang/sysroot 分别生成 `x86_64-unknown-linux-ohos` 和 `aarch64-unknown-linux-ohos`。

## 验证边界

- 当前确认的运行环境是 API 22 x86_64 模拟器。
- `arm64-v8a` 库只完成交叉编译和 HAP 入包检查，未在 HarmonyOS NEXT 真机加载。
- 调试样图用于驱动模拟器状态机；其内容不是真机相机画质或 EXIF 证据。
- 正式签名 HAP、真机 12/50MP 内存峰值和厂商相机旋转信息尚待验证。
