# 眼中名片 · iOS 安装包（ipa）获取与安装指南

这是给 iPhone 端准备安装包的完整说明。如果你只想尽快在手机上装上，
直接看**第四节（云端打包）**和**第五节（在 Windows 上安装）**，
两步就够了，不需要有 Mac。

---

## 一、先说清楚一件事：APK 不能"转换"成 IPA

没有能把 Android 安装包转成 iOS 安装包的工具，一个都没有。原因不是工具难写，而是两者
从编译产物到安装机制都不一样：

| | Android / APK | iOS / IPA |
| --- | --- | --- |
| 可执行内容 | DEX 字节码 + ART 运行时 | arm64 机器码 |
| 界面框架 | Android View / XML 布局 | SwiftUI / UIKit |
| 系统能力 | Rokid facelib 等 Android AAR | Apple Vision / Core ML |
| 签名 | 自己的 keystore（自签发） | 苹果签发的证书 + 描述文件 |
| 谁验证签名 | 系统只校验一致性 | 苹果的服务器参与校验 |

所以「眼中名片」在两端是**两套原生实现**，共享的只有数据格式（`persons.json` 的字段
和素材目录结构）。眼镜端跑的 Android 工程在项目根目录，没有被改动；iPhone 端的
Swift 工程在 `ios/` 目录，功能与眼镜端一一对应。

---

## 二、三条拿到 ipa 的路线

这里不能直接给你一个 ipa 文件，原因有两条，都不是配置问题：

1. **iOS 的编译工具链只存在于 macOS。** `xcodebuild`、`clang` 的 iOS 后端、`codesign`、
   iOS 模拟器全都是苹果独有的，Windows 和 Linux 上既没有官方版本，也没有可用的替代品。
2. **iOS 安装包必须由 Apple 的证书签名。** 签名这一步只能由 Xcode（在你登录了 Apple ID
   的机器上）或 Apple 的服务器完成。

所以下面三条路线，区别只是"用谁的 macOS 机器、用谁的证书"：

| 路线 | 需要什么 | 能得到什么 | 适合谁 |
| --- | --- | --- | --- |
| **A 本机 Mac 打包** | 一台 Mac + Xcode 16 | 一条命令出 ipa（可签名，也可不签名） | 手边有 Mac |
| **B 云端 macOS 打包**（推荐） | 一个 GitHub 账号，不需要信用卡 | 未签名 ipa，下载回 Windows 用 Sideloadly 安装 | 只有 Windows |
| **C 付费开发者账号** | 99 美元/年 | 通过 TestFlight 正式分发，不需要电脑连接 | 要给多人用、要长期用 |

三条路线用的是同一个脚本 `ios/build_ipa.sh`，区别只是参数。

---

## 三、路线 A：在 Mac 上打包

### 环境

macOS + Xcode 16 或更新版本（自带的工程文件用的是 Xcode 16 的工程格式）。
装好 Xcode 后在终端执行一次：

```bash
sudo xcode-select --switch /Applications/Xcode.app
```

### 出未签名的包（给 Sideloadly 用，不需要开发者账号）

```bash
cd ios
chmod +x build_ipa.sh
./build_ipa.sh unsigned
```

产物：`ios/dist/EyeCard-unsigned.ipa`

### 出带签名的包

```bash
./build_ipa.sh development --team A1B2C3D4E5
```

`--team` 填你的 Apple Developer Team ID（10 位）。在
<https://developer.apple.com/account> 的 Membership 页面可以查到，
把工程拖进 Xcode 看 `Signing & Capabilities` 也能看到。

脚本会自动完成归档（Archive）和导出（Export），Team ID 由脚本写进
`ExportOptions-*.plist`，不需要你手改配置文件。用免费 Apple ID 也可以在 Xcode 里
完成签名，但拿不到 10 位的 Team ID 时，直接用 `unsigned` 模式更省事。

### 也可以完全不用脚本

双击 `ios/EyeCard.xcodeproj`，在 target `EyeCard` 的 `Signing & Capabilities` 里把
`Team` 选成你自己的 Apple ID，连上 iPhone，按 `⌘R`。工程里已经放好了共享 scheme，
Xcode 和命令行都能直接用。

---

## 四、路线 B：没有 Mac，用 GitHub 的 macOS 机器打包

GitHub 给每个仓库免费提供 macOS 构建机器。**这里只推 iOS 端、也只编译 iOS 端**，
Android 那边完全不用传。工作流文件已经放在 `ios/` 目录里了，跑一次就能拿到 ipa，
全程不需要你的电脑是 Mac，也不需要任何证书——因为产出的包是不签名的。

### 步骤

1. 注册一个 GitHub 账号（免费）。
2. 新建一个仓库，**只把 `ios` 这个目录推上去**。整个仓库约 0.5 MB，几秒就传完。

   命令行方式（已装 Git）：

   ```bash
   cd D:\Users\Administrator\Desktop\rokid\ios
   git init
   git add .
   git commit -m "眼中名片 iPhone 端"
   git branch -M main
   git remote add origin https://github.com/你的用户名/仓库名.git
   git push -u origin main
   ```

   也推荐装一个 GitHub Desktop，图形界面点几下就行。
   用网页上传也可以（仓库页面 `Add file` → `Upload files`），
   但浏览器的文件选择框一次装不下完整的目录结构，建议用前面两种方式。

   `ios` 目录已经自带工作流、`.gitignore` 和 `.gitattributes`，
   单独作为一个仓库是完整可用的，不需要再补别的文件。

   > **推送前确认签名材料没有被提交。** `ios/.gitignore` 已经排除了
   > `build/`、`dist/*.ipa`、`*.p12`、`*.mobileprovision` 等。核对一下：
   >
   > ```bash
   > git status --short
   > git ls-files | grep -iE "p12|mobileprovision"
   > ```

   > 只想推 iOS 的话不用管下面这些。如果以后要连 Android 一起推到**同一个**仓库，
   > 还需要两件事：把仓库根的 `.gitignore` 和 `.gitattributes` 一起带上
   > （排除 Android 的签名材料 `eyecard-release.jks`、`keystore.properties`，
   > 以及 103 MB 的 `_research/` 目录），并把 `ios/.github/workflows/ios-ipa.yml`
   > 复制到仓库根的 `.github/workflows/` 下——GitHub 只从仓库根扫描工作流。
   > Android 的发布密钥库一旦泄露，别人就能以你的名义签发这个应用的更新包。
3. 打开仓库的 `Actions` 标签页，左侧选「**构建 iOS 安装包（ipa）**」，
   右边点 `Run workflow` → 绿色按钮确认。
4. 等 3～6 分钟，本次运行的页面底部 `Artifacts` 会出现 `EyeCard-ipa`，点它下载。
5. 解压得到的 `EyeCard-unsigned.ipa` 就是你需要的安装包，接着看第五节。

### 关于免费额度

- **公开仓库**：不消耗额度，随便跑。
- **私有仓库**：免费账号每月 2000 分钟，但 macOS 机器按 10 倍计算，相当于每月约 200 分钟
  macOS 构建时间。这个工程一次构建约 3～5 分钟，够用很多次。

### 备选

Codemagic、Bitrise 这类云构建服务也提供 macOS 机器，配置方式类似，效果一样。
如果不想把代码放到公开仓库，用私有仓库即可。

---

## 五、在 Windows 上把 ipa 装进 iPhone（Sideloadly）

未签名的 ipa 不能直接安装，需要在本机用你的 Apple ID 重新签一次名。
Sideloadly 就是一个免费做这件事的 Windows 工具（macOS 上也能用）。

### 准备

1. 装 Apple 的 Windows 驱动，任选一种：
   - 从 <https://www.apple.com/itunes/download/win64> 下载 **经典版 iTunes**（exe 安装包）；
   - 或者从 Microsoft Store 装苹果官方的 **Apple Devices** 应用。
   > 注意：**Microsoft Store 版的 iTunes 与 Sideloadly 不兼容**，会报找不到设备的错。
   > 如果已经装了商店版，先卸载，再装上面的经典版。
2. 从 <https://sideloadly.io> 下载 Sideloadly（一个 exe，免安装）。

### 安装

1. iPhone 用数据线连上电脑，手机上弹出「信任此电脑」时点**信任**。
2. 打开 Sideloadly，填三个地方：
   - `IPA`：把 `EyeCard-unsigned.ipa` 拖进去；
   - `Apple ID`：填你的 Apple ID（**免费账号就行**，不需要开发者账号）；
   - `Start`：点它，按提示输入 Apple ID 密码（密码只用于向苹果换取签名，不会留在本地）。
3. 装完后，手机上进：**设置 → 通用 → VPN 与设备管理 → 开发者 App**，
   点你的 Apple ID → **信任**。
4. 回到主屏幕，「眼中名片」图标变成正常颜色就可以打开了。首次启动按提示允许**相机**权限。

### 免费 Apple ID 的限制（用之前一定要知道）

| 限制 | 说明 |
| --- | --- |
| **有效期 7 天** | 到期后应用打不开（点图标闪退），用 Sideloadly 重新装一次即可 |
| **重装不会丢数据** | 直接覆盖安装，已录入的人员数据仍在。**不要先卸载**，卸载会清空数据 |
| 最多 3 个 | 同一个 Apple ID 同时最多装 3 个自签应用 |
| 每周 10 个 | 一周内最多注册 10 个 App ID（滚动计算），超额要等到下周 |
| 无推送/无后台常驻 | 本项目不使用这些能力，不受影响 |

### 其他可选工具

- **爱思助手（i4Tools）**：界面中文，里面也有「IPA 签名」功能，原理和限制与 Sideloadly 相同。
- **AltStore / SideStore**：在 iPhone 上完成签名。AltStore 需要电脑后台跑 AltServer，
  好处是可以自动续签这 7 天的有效期，不用每次手动重装。
- **Apple Configurator**（仅 Mac）：只能装**已签名**的 ipa，未签名的包它装不了。

---

## 六、路线 C：要正式分发（付费账号）

免费 Apple ID 的 7 天限制不适合真正交付使用。付费账号 99 美元/年，换来两种方式：

### Ad Hoc：小范围分发（最多 100 台设备）

1. 在开发者后台把这些 iPhone 的 UDID 加进设备列表；
2. 打包：
   ```bash
   ./build_ipa.sh adhoc --team A1B2C3D4E5
   ```
3. 把 `ios/dist/EyeCard-adhoc.ipa` 发给对方，对方用 Sideloadly 或爱思助手装上即可
   （已签名，装的时候不需要再填 Apple ID）。
   证书一年有效，到期重新打包。

### TestFlight：大范围分发（最多 10000 人）

1. 打包：
   ```bash
   ./build_ipa.sh appstore --team A1B2C3D4E5
   ```
2. 用 Transporter（Mac App Store 里免费下载）把 `ios/dist/EyeCard-appstore.ipa`
   上传到 App Store Connect；
3. 在 App Store Connect 里建一个 App、建测试组，把测试员的 Apple ID 加进去；
4. 测试员装 TestFlight App 就能安装，**不需要连电脑**，构建版本 90 天有效。

> 上架审核会关注人脸数据的处理方式。本项目的人脸特征和照片全部存在手机本地沙盒
> （`Documents/EyeCard/`），不上传任何服务器，这个说不清楚的话过审会有麻烦；
> 相机和相册的用途说明已经写进 `Config/Info.plist`，可以直接用。

---

## 七、脚本参数速查

```bash
./build_ipa.sh unsigned                # 未签名，给 Sideloadly 用，不需要账号
./build_ipa.sh development --team XX    # 开发签名，装到已登记设备
./build_ipa.sh adhoc --team XX          # Ad Hoc，分发给已登记 UDID 的设备
./build_ipa.sh appstore --team XX       # 用于上传 App Store Connect
./build_ipa.sh --help                   # 查看说明
```

产物统一放在 `ios/dist/`：

| 模式 | 产物文件名 |
| --- | --- |
| unsigned | `EyeCard-unsigned.ipa` |
| development | `EyeCard-development.ipa` |
| adhoc | `EyeCard-adhoc.ipa` |
| appstore | `EyeCard-appstore.ipa` |

脚本结束时会打印 ipa 的 SHA-256，方便核对文件是否完整。

---

## 八、常见问题

**`cannot be opened because it is in a future Xcode project file format`**
自带的工程文件用了 Xcode 16 的格式，你的 Xcode 太旧。升级到 Xcode 16，或者用备用的
`project.yml` 重新生成工程：

```bash
brew install xcodegen
cd ios && xcodegen generate
```

**`Signing for "EyeCard" requires a development team`**
签名模式少了 Team ID，加上 `--team` 参数；或者直接用 `unsigned` 模式。

**`The app's bundle identifier "com.eyecard.glasses.ios" is not available`**
这个 Bundle ID 被别人占了（概率很低）。打开
`ios/EyeCard.xcodeproj/project.pbxproj`，把两处 `PRODUCT_BUNDLE_IDENTIFIER`
改成你自己的，例如 `com.你的名字.eyecard.ios`。

**Sideloadly 报找不到设备 / 一直转圈**
99% 是装了 Microsoft Store 版 iTunes。卸载它，改装苹果官网的经典版 iTunes，
或者装 Apple Devices 应用。

**Sideloadly 报 `Provision.cpp: ... maximum number of App IDs`**
免费账号一周内注册的 App ID 到上限了，等一周，或者把不需要的自签应用删掉。

**装好之后点图标立刻闪退**
两种可能：7 天有效期到了（重新用 Sideloadly 装一次），或者还没在
「设置 → 通用 → VPN 与设备管理」里信任你的开发者证书。

**识别不准、认错人**
看 `ios/README.md` 第三节。默认用的是 Apple Vision 的通用图像特征，阈值需要在
设置界面里按实际照片调；追求精度就放一个 Core ML 人脸模型进去，工程已经留好位置，
不需要改代码。

---

## 九、顺带修掉的 iOS 端缺陷

做打包验证时对 22 个 Swift 文件做了一遍静态审查，发现四处会让应用一装到手机上就出问题
（或者变成偶发难查的故障）的地方，已经改好。改动都很小，原有逻辑全部保留：

**1. 批量导入时在后台线程改名单（`Store/PersonStore.swift`）**

「批量导入」会把整批照片的处理放在后台队列上跑，而它在处理每张照片时会调用
`store.upsert(...)`。原来的实现直接在调用线程上写 `@Published persons`，
也就是在后台线程改 SwiftUI 的状态，控制台会报
`Publishing changes from background threads is not allowed`，列表可能不刷新甚至崩溃。

改法：`cached` 快照仍然立即更新（相机线程和导入循环马上能读到最新数据，行为不变），
只把 `@Published persons` 的赋值收敛回主线程；已经在主线程调用时同步赋值，与原来一致。

**2. 没有显式申请相机权限（`Camera/CameraController.swift`）**

原来的代码直接配置采集会话，依赖系统在访问相机时自动弹权限框。这个行为在 iOS 上
并不稳定，结果可能是启动后一直黑屏、也没有任何提示。

改法：启动时先调用 `AVCaptureDevice.requestAccess(for: .video)`，授权通过再配置会话；
被拒绝时给出明确提示（指引去「设置 → 隐私与安全性 → 相机」）。
同时加了一个标记，避免"正在等授权时用户已经退出界面，授权回来后相机却自己亮起来"。

**3. 相机回调的读写竞态（`Camera/CameraController.swift`）**

界面进入/退出识别界面时会设置或置空 `camera.onFrame`（在主线程），
而相机队列每帧都会读它并调用。这个读写没有任何同步，理论上存在
"读到一半闭包被释放"的竞态，表现是**偶发、难复现的崩溃**——这种问题最费时间。

改法：给 `onFrame` 加了一把锁保护读写，回调里先取一份局部强引用再调用，
保证这一帧执行期间闭包不会被释放。对性能的影响可以忽略（每帧一把无竞争的锁）。

**4. 引擎单例的非原子创建（`Face/FaceEngineFactory.swift`）**

`get()` 原来是"先查有没有、没有就创建一个"两步。`EyeCardApp`、`MainView`、
`RecognizeViewModel` 会在各自的线程上调用它，并发时可能创建出两个引擎：
既白占一份内存，还会出现"预热的是 A、识别时用的是 B"的错位。

改法：改成 `static let` 惰性常量，Swift 保证静态常量只初始化一次且线程安全，
对外接口和行为都不变。

> 另外补上了 1024×1024 的应用图标（`AppIcon-1024.png`），
> 原来 asset catalog 里只有槽位声明、没有图片文件，装出来图标是空白的。

---

## 十、这次新增/改动的文件

`ios` 目录是一个**完整独立**的部分：自带 GitHub 工作流、忽略规则和换行符策略，
可以单独作为一个仓库推到 GitHub 编译，不需要外部任何文件配合。

```
ios/                                    ← iOS 的东西全部收在这里
├── .github/workflows/ios-ipa.yml       GitHub 云端编译流水线（只编译 iOS）
├── .gitignore                          iOS 专用的忽略规则
├── .gitattributes                      换行符策略，保证脚本在 Mac 上能执行
├── build_ipa.sh                        打包脚本（四种模式）
├── ExportOptions-development.plist     开发签名导出配置
├── ExportOptions-adhoc.plist           Ad Hoc 导出配置
├── ExportOptions-appstore.plist        App Store 导出配置
├── project.yml                         XcodeGen 备用工程描述
├── README.md                           工程说明
├── 导出iOS安装包.md                     本文档
├── tools/make_appicon.ps1              生成应用图标（Windows 上跑）
├── dist/README.md                      ipa 的输出位置
├── Config/Info.plist                   相机权限、文件共享等配置
├── EyeCard.xcodeproj/                  Xcode 工程（含共享 scheme）
└── EyeCard/                            Swift 源码 + 应用图标
```

仓库根还有两个文件，它们只服务于整个项目（含 Android），
单独推 iOS 仓库时用不到：

```
.gitignore       仓库级忽略规则：Android 签名材料、构建产物、_research/（103 MB）
.gitattributes   仓库级换行符策略
```

Android 的忽略规则仍在仓库根的 `.gitignore` 里。

顺带修改的已有文件（缺陷修复，见第九节）：

```
ios/EyeCard/Store/PersonStore.swift          名单变更统一回到主线程发布
ios/EyeCard/Camera/CameraController.swift    启动前显式申请相机权限 + 回调读写加锁
ios/EyeCard/Face/FaceEngineFactory.swift     引擎单例改为线程安全的惰性常量
```

图标需要重画时，在 Windows PowerShell 里执行（在 rokid 项目根目录下）：

```powershell
powershell -ExecutionPolicy Bypass -File .\ios\tools\make_appicon.ps1
```

如果 `ios` 已经是个独立仓库，就在它自己的根目录执行
`powershell -ExecutionPolicy Bypass -File .\tools\make_appicon.ps1`。

> 这个 .ps1 带 UTF-8 BOM，这是 Windows PowerShell 5.1 正确解析中文的必要条件，
> 不要用编辑器把它另存为"无 BOM 的 UTF-8"，否则脚本会因为中文注释而语法报错。
