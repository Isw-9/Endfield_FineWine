# Endfield_FineWine——在 Apple Silicon macOS 上运行《明日方舟：终末地》

通过经过**自定义补丁修改的 CrossOver Wine**，在 Apple Silicon Mac 上运行**《明日方舟：终末地》**——越过游戏的 VMProtect/TenProtect 保护壳和 **ACE 反作弊**，使用 Apple 的 **D3DMetal** 完成渲染，最终进入登录界面并正常游玩。

本项目发布时，CodeWeavers 将《终末地》评为 **“Installs, Will Not Run”（可以安装，但无法运行）**，社区也普遍认为不可能通过 CrossOver 运行《终末地》。本仓库提供了目前已知的首个可用方案，以及发现该方案的完整工程分析记录。

> **本项目是什么：** 一组针对 CrossOver（LGPL）Wine 的**补丁**，以及用于构建和部署补丁的**脚本**与**文档**。本项目**不包含或再分发** CrossOver、Wine、Apple Game Porting Toolkit 或游戏本体——你需要自行准备它们的正版授权副本。

---

## ⚠️ 请先阅读——范围、法律与伦理

- **请合法拥有游戏。** 本项目假定你已通过官方启动器安装了合法授权的《明日方舟：终末地》。本项目不会帮助你获取游戏。
- **这是兼容性工作，不是作弊。** 反作弊补丁仅用于让游戏在不受支持的硬件上**启动**——与 Valve 的 Proton 和 Linux 上的 dw-proton 属于同类工作。它们不会带来**任何游戏内优势**，不会修改游戏逻辑，也不会影响其他玩家。
- **不规避 DRM。** 本项目中的任何内容都不会破解或绕过授权与 DRM。
- **风险由你自行承担。** 在不受支持的配置上运行游戏可能违反其服务条款。是否使用本项目由你自行决定，风险也由你自行承担；作者不承担任何责任（参见 LICENSE）。
- **本项目与以下公司无关：** 鹰角/Gryphline、腾讯、CodeWeavers 或 Apple。

---

## 可用功能

- ✅ VMProtect/TenProtect 保护壳（`EndfieldBase.dll`）
- ✅ **ACE 反作弊**（`ACE-Base64.dll`、`ACE-Service64.exe`、内核驱动 `ACE-BASE.sys`）——可完整通过
- ✅ Unity 引擎可以加载（《终末地》使用 Unity IL2CPP），并通过 **Apple D3DMetal** 渲染
- ✅ **登录界面和实际游玩**——据报告，在 Apple M3 上运行良好

**已测试环境：** Apple M3、macOS 26.5、CrossOver 26.2.0。预计其他 Apple Silicon 芯片以及版本相近的 macOS/CrossOver 26.2 也能正常工作，但尚未验证。

目前还存在一个不影响使用的现象：ACE 的一个后台线程会在 `ntoskrnl.exe.PsGetProcessExitStatus` 处中止，但游戏仍可正常进入登录界面并游玩。

## 工作原理（简述）

本方案结合了两个新发现的 **Rosetta 2** 缺陷，以及从 Linux **dw-proton** 移植的反作弊补丁：

1. **Rosetta 会在普通 NOP 指令上发生故障。** VMProtect 会产生数以十万计的 `0F 1F` 多字节 NOP；Rosetta 错误地将它们识别为非法指令并触发异常，继而陷入堆栈溢出循环。修复方法：跳过该 NOP。
2. **Rosetta 会错误分类特权指令。** ACE 驱动会读取 `CR3`（`mov rbx, cr3`）作为反虚拟机探测；在 Rosetta 下，该指令被报告为*无效操作码*异常，而不是 `#GP`，导致 ACE 收到错误的异常并以“driver error 13”失败。修复方法：像 Linux 一样传递 `EXCEPTION_PRIV_INSTRUCTION`。
3. **dw-proton 移植：** 回移植 17 个 `ntoskrnl.exe` 函数，并加入 `KiUser*Dispatcher` int3 伪装和 QPC 时序补丁，从而清除阻碍 ACE 初始化的问题。

两个 Rosetta 修复在 `dlls/ntdll/unix/signal_x86_64.c` 中合计约 40 行代码，并可帮助 Apple Silicon 上的一大类受保护游戏（参见 WineHQ **Bug 45083**）。完整工程分析见 **[docs/13-working-solution.md](docs/13-working-solution.md)** 及 [docs/](docs/) 中的系列文档。

---

## 环境要求

| 项目 | 要求 |
|---|---|
| **Mac** | Apple Silicon（M 系列），不支持 Intel。 |
| **macOS** | 推荐 macOS 15（Sequoia）或更高版本；本项目在 macOS 26.5 上开发。 |
| **Rosetta 2** | 必需（`softwareupdate --install-rosetta --agree-to-license`）。补丁版 Wine 为 x86_64。 |
| **CrossOver** | 必须为 **26.2**（替换的模块需要与该版本的 Wine 11.0 ABI 匹配）。请从 [codeweavers.com](https://www.codeweavers.com/crossover) 获取有授权的 CrossOver。 |
| **Xcode CLT** | `xcode-select --install` |
| **Homebrew** | [brew.sh](https://brew.sh)（Apple Silicon 版本，位于 `/opt/homebrew`） |
| **游戏** | 通过 Gryphline 启动器安装到 CrossOver 容器中的正版《明日方舟：终末地》。 |
| **磁盘空间/时间** | 构建目录约需 5 GB；构建耗时约 20～60 分钟。 |
| **GPTK4** *（可选）* | Apple Game Porting Toolkit 4，可获得最佳性能——参见[下文](#图形与性能gptk4)。 |

---

## 安装

有两种方式可以将补丁版 Wine 部署到 CrossOver。**两种方式都需要先构建补丁版 Wine**（第 1 节），然后再进行部署（第 2 节为脚本方式，第 3 节为手动方式）。

### 1. 构建补丁版 Wine

```bash
git clone <your-fork-url> Endfield_FineWine
cd Endfield_FineWine

# 一次完成：安装依赖 → 获取源码 → 应用补丁 → 配置 → 构建（约 20～60 分钟）
./scripts/build-wine.sh all
```

也可以分步执行（某个环节需要处理时更方便）：

```bash
./scripts/build-wine.sh deps       # 通过 Homebrew 安装：bison、mingw-w64、meson、pkg-config 等
./scripts/build-wine.sh fetch      # 下载 CrossOver 26.2 Wine 源码（约 142 MB）并执行 git init
./scripts/build-wine.sh apply      # 使用 git apply 应用全部 23 个补丁（已验证可无冲突应用）
./scripts/build-wine.sh configure  # 仅构建 64 位版本，通过 `arch -x86_64` 运行（Rosetta 宿主）
./scripts/build-wine.sh build      # 执行 make -j
```

说明：

- **不需要 `cx-llvm`/`win32on64`。** 《终末地》仅支持 64 位，因此这里使用**标准工具链**构建纯 64 位 Wine，避开了目前已无法获得的 CrossOver 定制版 clang。详见 [docs/04](docs/04-building-crossover-wine.md)。
- 该构建有意保持**最小化**（不包含捆绑字体、TLS 或图形库）。这没有问题：我们只会替换 CrossOver 中的 3 个核心模块，而 CrossOver 已经提供了其余所有内容。

### 2. 部署到 CrossOver——脚本方式（推荐）

```bash
./scripts/swap-into-crossover.sh
```

该脚本会将 `/Applications/CrossOver.app` 复制为 `build/CrossOver_patched.app`，替换 3 个补丁模块，对它们进行临时签名，移除应用包签名封装并清除隔离属性。之后使用 `build/CrossOver_patched.app` 运行游戏（第 4 节）。

### 3. 部署到 CrossOver——手动方式

如果你希望手动操作（例如为了理解或审查过程）：

```bash
# 复制 CrossOver（必须为 26.2），保留原版不变
cp -a /Applications/CrossOver.app "$HOME/CrossOver_patched.app"
CXR="$HOME/CrossOver_patched.app/Contents/SharedSupport/CrossOver"
B="$PWD/build/wine-build64"

# 替换 3 个补丁模块（先备份原始文件）
cp "$CXR/lib/wine/x86_64-unix/ntdll.so"        "$CXR/lib/wine/x86_64-unix/ntdll.so.orig"
cp "$CXR/lib/wine/x86_64-windows/kernel32.dll" "$CXR/lib/wine/x86_64-windows/kernel32.dll.orig"
cp "$CXR/lib/wine/x86_64-windows/ntoskrnl.exe" "$CXR/lib/wine/x86_64-windows/ntoskrnl.exe.orig"

cp "$B/dlls/ntdll/ntdll.so"                           "$CXR/lib/wine/x86_64-unix/ntdll.so"
cp "$B/dlls/kernel32/x86_64-windows/kernel32.dll"     "$CXR/lib/wine/x86_64-windows/kernel32.dll"
cp "$B/dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe" "$CXR/lib/wine/x86_64-windows/ntoskrnl.exe"

# 对替换的文件进行临时签名，并移除应用包签名封装和隔离属性以便加载
for f in x86_64-unix/ntdll.so x86_64-windows/kernel32.dll x86_64-windows/ntoskrnl.exe; do
  codesign --force --sign - "$CXR/lib/wine/$f"
done
rm -rf "$HOME/CrossOver_patched.app/Contents/_CodeSignature" \
       "$HOME/CrossOver_patched.app/Contents/CodeResources"
xattr -drs com.apple.quarantine "$HOME/CrossOver_patched.app"
```

| 补丁模块 | 包含内容 |
|---|---|
| `lib/wine/x86_64-unix/ntdll.so` | 两个 Rosetta 信号修复及 `NtDelayExecution` QPC 时序修复 |
| `lib/wine/x86_64-windows/kernel32.dll` | `KiUser*Dispatcher` int3 伪装 |
| `lib/wine/x86_64-windows/ntoskrnl.exe` | 17 个 `ntoskrnl.exe` em 回移植函数 |

### 4. 运行游戏

让**补丁版** CrossOver 使用你现有的《终末地》容器：

```bash
CXR="$PWD/build/CrossOver_patched.app/Contents/SharedSupport/CrossOver"
"$CXR/bin/wine" --bottle "Arknights Endfield" \
  --cx-app "C:/Program Files/GRYPHLINK/games/Arknights Endfield/Endfield.exe"
```

也可以从 Finder 启动 `CrossOver_patched.app`，然后像平常一样从对应容器启动《终末地》。游戏应该可以进入登录界面。若要捕获调试日志，请在命令前加上 `CX_LOG=/tmp/ef.log WINEDEBUG=+seh`。

---

## 图形与性能（GPTK4）

**你可能并不需要 GPTK4。** CrossOver 26.2 已经捆绑 **D3DMetal 3.0**（即 GPTK 3.0），《终末地》默认便使用它进行渲染——在已测试的 M3/macOS 26.5 环境上，无需额外调整图形组件即可流畅运行。Apple 的 **Game Porting Toolkit 4** 可将捆绑的 D3DMetal 从 **3.0 升级到 4**（DirectX 12 → **Metal 4**，支持 MetalFX 帧生成和 HDR），提供最新、最快的渲染路径。但 GPTK4 属于 **macOS 27 测试版时期的软件**，因此应将其视为一项**可选的高级升级**。

> **关于“Vulkan”：** GPTK/D3DMetal **不提供** Vulkan——它会将 DirectX **直接转换为 Metal**。Apple GPU 上的 Vulkan 由 **MoltenVK**（Vulkan → Metal）提供，CrossOver 已捆绑 MoltenVK，CXPatcher/Procyon 还可对其进行升级。因此存在两类图形方案：**DirectX → 直接转换为 Metal**（D3DMetal/DXMT，GPTK 属于此类）和 **DirectX/Vulkan → Vulkan → Metal**（DXVK/vkd3d + MoltenVK）。直接使用 D3DMetal 的路径性能更高。

### 选择图形后端

> **⚠️ 对《终末地》而言，请将游戏自身的渲染器设置为 DirectX 11。** 《终末地》默认为 Vulkan/DX12，而它们在 CrossOver 26.2 下都会失败（DX12 → `vkd3d` 无法编译其 DXIL 着色器；原生 Vulkan → MoltenVK 同样失败），最终出现白屏。仅将 CrossOver 的*后端*设置为 D3DMetal，**并不能**使游戏的 DX12 绕过 vkd3d——你必须在启动器或游戏内的图形设置中选择 **DirectX 11**（也可以使用 `-force-d3d11` 启动）。游戏更新可能会重置此设置，因此每次更新后请重新检查。以下通用 GPTK4 指南适用于游戏已切换到 DirectX 路径的情况。

在 CrossOver 中选择 **Arknights Endfield** 容器，然后进入**高级设置 → 图形**：

- **D3DMetal** *（推荐）*——DirectX 11/12 → Metal。使用 GPTK4 时，DX12 → Metal 4 的速度最快，并且这是唯一支持**通过 MetalFX 实现 DLSS** 帧生成的路径。若要获得完整收益，请强制游戏使用 **DirectX 12** 模式。
- **DXMT**——适合 DirectX 11 游戏，也支持 DLSS/MetalFX 开关。
- **DXVK**——DirectX 10/11 → Vulkan → MoltenVK（备用方案；多一层转换，不支持 DLSS）。

另外，请启用 **DLSS（MetalFX）** 和 **MSync**，并在容器环境变量中设置 `ROSETTA_ADVERTISE_AVX=1` 以启用 AVX2（该功能由 macOS 15 及更高版本上的 Rosetta 2 提供，与 GPTK 无关）。

### 安装 GPTK4

> **Apple 的 GPTK 仅限评估用途——你必须自行下载，且不得再分发**，因此本仓库无法捆绑 GPTK。这些步骤适用于在 **macOS 27（测试版）**上使用 GPTK4。对于 **macOS 26**，CrossOver 捆绑的 **D3DMetal 3.0** 才是匹配版本——无需进行任何操作。

1. 从 Apple **下载**：[developer.apple.com/games/game-porting-toolkit](https://developer.apple.com/games/game-porting-toolkit/) → Downloads 列表（[搜索“Game Porting Toolkit”](https://developer.apple.com/download/all/?q=game%20porting%20toolkit)）。使用 Apple ID 登录（以往免费 Apple Developer 账户即可）。挂载下载的 `.dmg`（它会出现在 `/Volumes/…` 下；运行 `ls /Volumes/` 可获得准确名称）。
2. 将它应用到**补丁版** CrossOver 副本——请在完成第 2 节的模块替换之后再执行，以便同时保留反作弊修复和 GPTK4：

   **手动方式**——替换两个 D3DMetal 库（保留带有 `-old` 后缀的备份）：

   ```bash
   GPTK_VOL="/Volumes/<已挂载的 GPTK 卷——请运行 ls /Volumes/ 检查>"
   cd "$HOME/CrossOver_patched.app/Contents/SharedSupport/CrossOver/lib64/apple_gptk/external"
   mv D3DMetal.framework D3DMetal.framework-old
   mv libd3dshared.dylib  libd3dshared.dylib-old
   ditto "$GPTK_VOL/redist/lib/external/" .
   ```

   （文件夹名称是 `apple_gptk`，末尾带有 **k**。只需使用 `redist/lib/external/` 中的库——请忽略 DMG 中的 Homebrew/Wine 路径，那是供*独立版* GPTK 使用的，不适用于 CrossOver。）

   **CXPatcher/Procyon（更简单）**——[CXPatcher](https://github.com/italomandara/CXPatcher) 可以自动将 GPTK `.dmg` 中的 D3DMetal 放入 CrossOver 副本（将 CrossOver 拖入应用，保持“Integrate D3DMetal (GPTK)”开启，然后选择 GPTK dmg）。其作者已将 **GPTK4** 支持迁移到后继项目 **[Procyon](https://github.com/italomandara/Procyon)**——如需 GPTK4，请使用 Procyon 的预发布版本。这些工具只修改**图形组件**；反作弊仍需要本项目的 Wine 模块替换，因此必须对同一份 CrossOver 副本同时应用两者（例如，对 CXPatcher/Procyon 的输出运行 `swap-into-crossover.sh`）。

### 注意事项

- **GPTK4 需要 macOS 27（测试版）**和 Metal 4。在 **macOS 26 上请继续使用捆绑的 D3DMetal 3.0。** 目前尚未验证 GPTK4 能否与 **CrossOver 26.2** 完美集成——请自行测试，保留 `-old` 备份并准备随时恢复；CrossOver 27/Procyon 可能是更顺畅的方案。
- 仅支持 Apple Silicon；需要 Rosetta 2。

---

## 仓库结构

```text
patches/            Wine 补丁（LGPL——见下文）
  stage1-macos/       两个 Rosetta 修复及一个构建修复
  stage2-dwproton/    移植的 dw-proton 反作弊补丁（em 回移植及其他补丁）
scripts/            build-wine.sh、swap-into-crossover.sh、捕获/调试辅助脚本
docs/               完整工程分析记录（从 docs/README.md 开始）
build/              （已被 gitignore 忽略）生成的 Wine 源码及构建输出
```

## 故障排除

- **“CrossOver.app is version X, expected 26.2”**——模块替换需要匹配的 Wine ABI。请安装 CrossOver 26.2。
- **游戏无法启动/出现签名错误**——重新执行 `codesign --force --sign -` 和 `xattr -drs com.apple.quarantine`；确认已移除应用包签名封装。
- **ACE 再次出现“driver error 13”**——补丁版 `ntdll.so`/`ntoskrnl.exe` 未被加载；请检查替换路径，并确认启动的是*补丁版*应用。
- **白屏/空白画面（游戏更新后很常见）**——游戏更新将渲染器重置为 **Vulkan 或 DirectX 12**，而二者在 CrossOver 26.2 下都无法良好工作（DX12 → `vkd3d` 无法编译游戏的 DXIL/SM6 着色器 → `Cannot load DXIL conversion library`；原生 Vulkan → MoltenVK 同样失败）。**解决方法：将游戏的渲染 API 设为 DirectX 11**——在 Gryphline 启动器或游戏内图形设置中选择 **DirectX 11**（也可以使用 `-force-d3d11` 启动 Unity）。DX11 使用成熟的 D3DMetal/DXMT 路径，可以正常渲染。**不要**尝试通过 CrossOver 的 `apple_gptk` 副本覆盖其 `d3d11/d3d12/dxgi.dll` 来解决问题——这会破坏 `unityplayer.dll` 初始化（Windows 错误 **1114**）；这些 D3DMetal DLL 只能通过 CrossOver 自身的后端机制加载。
- **`unityplayer.dll`“missing or corrupt”（错误 1114）**——这是 DLL 初始化失败，通常由替换图形 DLL（见上文）或在没有启动器工作目录的情况下直接运行 `Endfield.exe` 导致。请恢复 CrossOver 默认的 `d3d11/d3d12/dxgi.dll`，并通过 Gryphline 启动器运行游戏。
- 更多信息及调试捕获脚本见 [scripts/01-capture-failure.sh](scripts/01-capture-failure.sh) 和 [docs/10](docs/10-milestone-1-results.md)。

---

## 许可证

- **脚本（`scripts/`）和文档（`docs/`、README）：** [MIT](LICENSE)。
- **补丁（`patches/`）：** 这些是对 **Wine** 的修改，因此采用 **LGPL-2.1-or-later**（Wine 的许可证）——MIT 无法对其重新授权。`stage2-dwproton/` 补丁源自 **dw-proton（Dawn Winery）**项目，并保留上游作者（Etaash Mathamsetty、Ziia Shi/mkrsym1、NelloKudo 等）的权利。详见 [patches/README.md](patches/README.md)。
- 本仓库**不分发** Wine、CrossOver、Apple GPTK、MoltenVK 或游戏本体。请从各自来源获取，并遵守各自的许可证。

## 致谢

- **[dw-proton/Dawn Winery](https://dawn.wine/)**——本项目第二阶段所移植的 Linux ACE/《终末地》补丁。
- **[CodeWeavers CrossOver](https://www.codeweavers.com/crossover)** 和 **[Wine](https://www.winehq.org/)** 项目——本项目的基础。
- **[Apple Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/)**——D3DMetal。
- **WineHQ Bug 45083** 的报告者——他们的先前工作帮助界定了 Rosetta VMProtect 问题。

## 贡献与上游合并

两个 Rosetta 信号处理修复属于 CrossOver 在 Apple Silicon 上的通用缺陷，值得向 **CodeWeavers** 报告（可引用 Bug 45083）。欢迎提交 PR，以改进构建/部署脚本、打包方式（例如 CXPatcher 风格的覆盖层），以及在更多芯片和 macOS 版本上进行测试。
