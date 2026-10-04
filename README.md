# 眼中名片 · iOS 版（源码工程）

这是「眼中名片」在 iPhone 上的**重写实现**，不是把 Android 安装包转换过来的——
APK 和 IPA 之间不存在转换工具，两者语言、UI 框架、系统 API、签名分发机制都不同。

镜片上的 Rokid 眼镜跑 Android，手机跑 iOS，所以两端共用同一套数据格式，
但代码是各自独立的。眼镜端的 Android 工程在上一级目录，未被改动。

---

## 一、先说清楚：这里能拿到什么、不能拿到什么

**能拿到：** 一套完整的 SwiftUI 源码工程，包含识别、名片浮层、人员管理、
批量导入、设置全部功能。在 Mac 上用 Xcode 打开即可编译、装到 iPhone。

**不能拿到：** 一个可以直接安装的 `.ipa` 文件。原因有两条，都不是配置问题：

1. **iOS 的编译工具链只在 macOS 上运行。** 本工程是在 Windows 上生成的，
   我无法在这里编译，也无法验证它是否一次通过编译。
2. **iOS 安装包必须用苹果的证书签名。** 即使是免费 Apple ID，
   也必须由 Xcode 在你的 Mac 上完成签名，才能装进 iPhone。

所以交付的是源码工程 + 详细的构建步骤，最后一步需要你在 Mac 上完成。

---

## 二、和眼镜端的功能对应关系

| 功能 | 眼镜端（Android） | iOS 端 | 状态 |
| --- | --- | --- | --- |
| 功能菜单 | `MainActivity` | `MainView` | 一致 |
| 实时识别 | `RecognizeActivity` | `RecognizeView` + `RecognizeViewModel` | 一致 |
| 名片浮层 | 名片 Overlay | `NameCardView` | 一致 |
| 人员管理 | `PersonListActivity` | `PersonListView` | 一致 |
| 人员录入 | `PersonEditActivity` / `CaptureActivity` | `PersonEditView` | 改为从相册选照片 |
| 批量导入 | `ImportActivity` + `PersonImporter` | `ImportView` + `PersonImporter` | 一致（CSV / txt / json 三种格式都支持） |
| 设置 | `SettingsActivity` / `Settings` | `SettingsView` / `AppSettings` | 一致 |
| 素材目录 | `/sdcard/EyeCard/` | `Documents/EyeCard/`（可用「文件」App 或 Finder 文件共享访问） | 等价 |
| 人脸检测 | Rokid facelib | Apple Vision（`VNDetectFaceRectanglesRequest`） | **换实现** |
| 人脸特征 | Rokid 特征库（`featureId`） | 本地特征向量 + 余弦相似度（1:N） | **换实现** |
| 人名名单 | `persons.json` | `persons.json`（字段一一对应） | 一致 |

`persons.json` 的字段与眼镜端保持一致（`id` / `name` / `title` / `org` /
`phone` / `email` / `tags` / `note` / `photoPath` / `featureId` /
`createdAt` / `updatedAt`），iOS 端额外多一个 `faceEmbedding` 存特征向量，
`featureId` 仅作兼容保留。

---

## 三、人脸识别是怎么做的

眼镜端的识别能力来自 Rokid 的专有 SDK（`com.rokid.glass:facelib`），
它是一个 Android AAR + ARM 的 `.so` 库，**没有 iOS 版本**。所以 iOS 端重新搭了一条等价的链路：

```
相机帧 (CVPixelBuffer)
   ↓  VNDetectFaceRectanglesRequest          ← 人脸检测
人脸框（归一化坐标）
   ↓  按框裁剪 + 外扩 18%
人脸图
   ↓  FaceEmbedder                           ← 特征提取
特征向量
   ↓  PersonStore.match()                    ← 1:N 比对（余弦相似度）
命中的 Person → 弹出名片
```

**默认实现**用 Apple Vision 的 `VNGenerateImageFeaturePrintRequest` 生成特征向量。
它的好处是完全离线、不需要任何模型文件，装上就能跑。

需要提醒的是：这是**通用图像特征**，不是专门的人脸身份特征。在正面、光照正常、
人脸占比足够大的条件下可用，但鲁棒性不如专门的人脸模型。所以：

- **相似度阈值必须实测调整。** 默认 75，设置界面里可以边看边改。
  建议拿名单里的人正脸、侧脸、不同光照各跑几轮再定。
- 阈值调高更严格（误认少、可能漏认），调低更宽松。

### 想要更高的识别精度：放一个 Core ML 人脸模型

工程已经留好了位置，不需要改任何代码：

1. 准备一个人脸特征模型（例如 MobileFaceNet / FaceNet 一类，输出 128~512 维向量）；
2. 用 `coremltools` 转成 `.mlmodel`，**命名为 `FaceEmbedding.mlmodel`**；
3. 拖进 Xcode 的 `EyeCard` 目录下，确认勾选了 target `EyeCard`；
4. 重新编译。`FaceEngineFactory` 会自动检测到模型并优先使用它，
   设置页的「引擎」一栏会显示成 `Apple Vision + Core ML 人脸模型（FaceEmbedding）`。

模型要求：输入一张人脸图片（`VNCoreMLRequest` 会按模型声明的尺寸自动缩放），
输出一个 `MLMultiArray` 特征向量。

---

## 四、在 Mac 上构建

> **想直接拿到可安装的 ipa（包括手上没有 Mac 的情况）**，
> 看同目录的《导出iOS安装包.md》。那里有打包脚本的用法、用 GitHub 免费 macOS
> 机器云端打包的步骤，以及在 Windows 上用 Sideloadly 装进 iPhone 的完整流程。
>
> 已经装了 Xcode 的话，一条命令即可：
>
> ```bash
> cd ios && chmod +x build_ipa.sh && ./build_ipa.sh unsigned
> ```
>
> 产物在 `ios/dist/EyeCard-unsigned.ipa`。

### 环境要求

- macOS + Xcode 16 或更新版本（自带的工程文件用了 Xcode 16 的「文件系统同步目录」格式）
- iOS 16.0 及以上的 iPhone

### 打开工程的三种方式（任选一种）

**方式一：直接打开（推荐）**

双击 `EyeCard.xcodeproj`。首次打开后，在 target `EyeCard` 的
`Signing & Capabilities` 里把 `Team` 选成你自己的 Apple ID，`Bundle Identifier`
如果提示冲突就改成别的（例如 `com.你的名字.eyecard`）。

**方式二：用 XcodeGen 生成**

如果方式一打不开（例如 Xcode 版本较低），用附带的 `project.yml` 重新生成：

```bash
brew install xcodegen
cd ios
xcodegen generate
open EyeCard.xcodeproj
```

**方式三：手动新建工程（最稳，任何 Xcode 版本都行）**

1. Xcode → File → New → Project → iOS → App；
2. Product Name 填 `EyeCard`，Interface 选 **SwiftUI**，Language 选 **Swift**；
3. 删掉自动生成的 `ContentView.swift` 和 `EyeCardApp.swift`；
4. 把本目录的 `EyeCard` 文件夹整体拖进工程，勾选 *Copy items if needed* 与 target `EyeCard`；
5. 打开 target 的 Info 标签页，加上这几项（对应 `Config/Info.plist`）：
   - `Privacy - Camera Usage Description`：需要使用摄像头来识别人脸，并在识别到已登记人员时弹出名片。
   - `Privacy - Photo Library Usage Description`：需要读取你选择的照片，用于录入人员人脸信息。
   - `Application supports iTunes file sharing` = YES
   - `Supports opening documents in place` = YES
6. 把 Deployment Target 设为 iOS 16.0，并把应用方向锁定为竖屏。

### 装到 iPhone

1. 用数据线连上 iPhone，在 Xcode 顶部把运行目标选成你的手机；
2. 按 `⌘R`。首次运行 iPhone 会提示「不受信任的开发者」，
   去「设置 → 通用 → VPN 与设备管理」里信任你的 Apple ID 即可；
3. 免费 Apple ID 签名的 App 有效期 7 天，到期用 Xcode 重新装一次就行。

### 导出可安装的 ipa

用打包脚本（推荐，自动完成 Archive + Export）：

```bash
./build_ipa.sh unsigned                # 未签名，给 Sideloadly 用
./build_ipa.sh development --team XX    # 开发签名
./build_ipa.sh adhoc --team XX          # Ad Hoc，分发给已登记 UDID 的设备
./build_ipa.sh appstore --team XX       # 用于上传 App Store Connect
```

产物在 `ios/dist/`，脚本会打印 SHA-256。也可以用界面操作：
Xcode → Product → Archive → Distribute App。

注意：要分发给别人的设备，需要付费的 Apple Developer 账号
（99 美元/年），或者用 Ad Hoc 方式把对方设备 UDID 加进描述文件；
不想花钱就用 `unsigned` 模式，配合 Sideloadly 在装机时临时签名（有效期 7 天）。

---

## 五、跑起来之后怎么用

1. 首次启动按提示允许**相机**权限。
2. 录入人员，两种方式：
   - **单个人**：「人员管理」→ 右上角「+」→ 填信息 → 「从相册选择照片」→ 保存。
     保存时会自动检测人脸并提取特征。没有检测到人脸会提示你换一张更清晰的正面照。
   - **一批人**：把照片放进导入目录，再点「批量导入」。
3. 照片放进导入目录的方法（两种都行）：
   - 数据线连电脑 → Finder → 你的 iPhone → 文件 → 「眼中名片」→ 把照片拖进 `import`；
   - iPhone 上打开「文件」App → 我的 iPhone → 眼中名片 → `import`。
4. 「批量导入」页点右上角「开始导入」。
5. 回到「开始识别」，把手机背面摄像头对准人，识别到就会弹出名片。

### 批量导入的素材格式

`import` 目录里可以放照片（jpg / jpeg / png / bmp / webp / heic），
人员信息用以下任意一种方式补充，优先级从高到低：

- `persons.csv`：一行一人，列顺序 `文件名,姓名,职位,单位,电话,邮箱,标签,备注`
  （可以带表头，带表头时按列名匹配）；
- 与照片同名的 `.txt`：每行 `字段: 值`，例如 `姓名: 张三`；
- 与照片同名的 `.json`：字段名与 `persons.json` 一致。

三种都没有时，用照片文件名（去掉扩展名）作为姓名。
姓名相同的人员按「更新」处理，方便对同一批素材反复迭代。

---

## 六、目录结构

```
ios/
├── EyeCard.xcodeproj/          Xcode 工程
├── project.yml                 XcodeGen 备用工程描述
├── Config/Info.plist           相机权限、文件共享等配置
└── EyeCard/
    ├── EyeCardApp.swift        应用入口（预热引擎）
    ├── Models/
    │   ├── Person.swift        人员数据模型（字段对齐眼镜端）
    │   └── AppSettings.swift   设置项的键名与默认值
    ├── Store/
    │   ├── AppDirs.swift       目录规划（Documents/EyeCard）
    │   ├── PersonStore.swift   名单读写、人脸 1:N 比对
    │   └── PersonImporter.swift 批量导入（CSV / txt / json）
    ├── Face/
    │   ├── FaceEngine.swift    引擎与特征提取器协议
    │   ├── VisionFaceEngine.swift     检测 + 裁剪
    │   ├── FeaturePrintEmbedder.swift 默认特征提取（Vision）
    │   ├── CoreMLFaceEmbedder.swift   可选：Core ML 人脸模型
    │   ├── FaceEngineFactory.swift    按可用性挑选实现
    │   └── ImageUtils.swift    图片方向归一化、缩放、缓存
    ├── Camera/CameraController.swift  相机采集与预览
    └── UI/
        ├── MainView.swift          功能菜单 + 状态
        ├── RecognizeView.swift     实时识别界面
        ├── RecognizeViewModel.swift 识别流程与名片状态
        ├── NameCardView.swift      名片浮层
        ├── PersonListView.swift    人员管理
        ├── PersonEditView.swift    人员录入 / 编辑
        ├── ImportView.swift        批量导入
        ├── SettingsView.swift      设置
        └── GlassStyle.swift        配色与通用组件
```

---

## 七、已知限制

这些是我在 Windows 上无法验证、或者当前实现确实存在的边界，先讲清楚：

1. **代码未经编译验证。** 我这边没有 macOS，无法运行 Xcode 编译。
   如果报错，多数会是拼写或 API 可用性一类的小问题，按 Xcode 提示改即可。
2. **识别精度依赖阈值调校。** 默认的 Vision 图像特征在受控条件下可用，
   正式使用建议接入 Core ML 人脸模型（见第三节）。
3. **人脸数据是明文保存的。** 特征向量和照片直接存在沙盒的
   `Documents/EyeCard/` 里，方便调试和交换数据，但没有加密。
   如果要处理敏感人员数据，需要额外加一层加密存储。
4. **竖屏锁定。** 应用锁定竖屏，相机的画面旋转也按竖屏固定处理，
   这样送进 Vision 的方向恒为「正立」。如果以后要支持横屏，需要按设备姿态
   动态计算图像方向。
5. **前后摄像头可切换**，但识别默认用后置摄像头
   （对准别人用），自拍测试可以点右上角切换。
6. **识别阈值是跨线程读的**：阈值在主线程（设置界面）写入、在相机线程读取，
   两者之间没有加锁。`Double` 在 arm64 上是 8 字节对齐读写，实际不会读到"半个值"，
   所以这里保留了现状没有改动。要彻底消除这个数据竞争，需要把这几个设置项
   改成由锁保护的快照再传给相机线程。
7. **列表头像是同步读盘解码的**：人员列表和名片里的照片走的是
   `ImageUtils.cachedImage`，同步读文件 + 解码（有 `NSCache` 兜底）。
   录的人很多、列表很长时滚动可能掉帧，后续可以改成异步加载加占位图。
