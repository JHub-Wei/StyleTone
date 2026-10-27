# 优化补丁

这些补丁由 WP-24 分析/测量后提出，**不直接修改模块源码**。每个补丁：

- 可用 `git apply` 应用；
- 只动一个模块（或 UI 的一个文件）；
- 附有验证命令与风险；
- 合入后由 owner 重新测量并更新基线。

```bash
# 预览
git apply --check docs/performance/patches/wp-06-metal-frame-resource-cache.patch
git apply docs/performance/patches/wp-06-metal-frame-resource-cache.patch
swift test --filter MetalGeometryWarpTests
swift test --filter WarpFramePerformanceTests
```

| 补丁 | 模块 | 目的 | 预期 |
|---|---|---|---|
| `wp-17-preview-mask-scaling.patch` | StyleToneUI/Editor | vImage mask 缩放 | 预览缩放 -50–70% |
| `wp-06-metal-frame-resource-cache.patch` | StyleToneGeometry/Core | 缓存源纹理/index buffer | 预览帧 -10–20% |
| `wp-17-thermal-degradation.patch` | StyleToneUI/Editor | 热/低电/低端机降级 + 提示 | 稳定性/热 |
| `wp-02-streaming-export.patch` | StyleToneImaging | 导出直接写 URL | 峰值 -3–8 MB |

> 补丁没有在 WP-24 的目录内实现生产代码；合入前不能声称收益已生效。
> 所有补丁都不得改变导出分辨率/质量或 Core 契约。
