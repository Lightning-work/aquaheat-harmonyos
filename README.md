# AquaHeat Console · 鸿蒙 NEXT 原生版

热水器蓝牙上位机的 HarmonyOS NEXT（纯血鸿蒙）原生应用。本仓库通过 **GitHub Actions 云端编译**，本机无需安装 DevEco Studio。

- 包名：`com.whc.aquaheat`
- 最低系统：HarmonyOS 5.0 / API 12
- 蓝牙双通道：BLE（低功耗透传）+ SPP（经典蓝牙 RFCOMM，JDY-31-SPP / HC-05）
- 协议：与网页版/安卓版完全一致（9+N 帧 · 500ms 轮询 · 无应答持续重发）

## 使用步骤

### 1. 注册华为开发者账号（免费，一次）
https://developer.huawei.com/consumer/cn/ → 注册并实名认证。
签名证书在这一步的 AGC 控制台生成（见下文「签名」）。

### 2. 创建 GitHub 仓库并上传本工程
1. 登录 https://github.com → New repository → 名字随意（如 `aquaheat-harmonyos`）→ Public（私有仓库 CI 也有免费额度）→ Create
2. 仓库页 → **Add file → Upload files** → 把 `harmonyos` 文件夹里的**全部内容**（不是文件夹本身）拖进去 → Commit

### 3. 配置 commandline-tools 下载地址
编译需要华为的命令行工具包（内含 hvigor + SDK）：

1. 登录 https://developer.huawei.com/consumer/cn/deveco-studio/ → 页面底部「命令行工具」→ 下载 **Linux x64** 版 zip（约 2~3GB）
2. 把下载得到的**直链 URL**（浏览器下载列表里右键复制）填入仓库：
   Settings → Secrets and variables → Actions → **Variables** 标签 → New repository variable：
   - Name: `COMMANDLINE_TOOLS_URL`
   - Value: 直链 URL

> 直链有时效性。若 CI 报下载失败，重新去官网取一次新直链更新该变量即可。
> 也可在手动触发时（Run workflow）临时填入输入框。

### 4. 触发编译
仓库 → **Actions** 标签 → Build HarmonyOS HAP → Run workflow（push 也会自动触发）。
构建成功后在本页底部 **Artifacts** 下载 `aquaheat-hap`（内含 `entry-default-unsigned.hap`）。

### 5. 签名（调试版）
未签名 HAP 无法安装。调试签名走 AGC：

1. AGC 控制台 https://developer.huawei.com/consumer/cn/service/josp/agc/index.html
   → 我的证书/Profile：
   - 生成 **调试证书 .cer**（一次）
   - 本机生成密钥库 .p12（需一条命令，见下）
   - 创建 **调试 Profile .p7b**（需登记真机 UDID）
2. 真机 UDID 获取：NEXT 手机开启开发者模式（设置→关于手机→连点版本号 7 次→USB 调试），
   电脑用 commandline-tools 里的 hdc：`hdc shell bm get -u`（UDID）
3. 签名命令（CI 侧）：把 .p12/.cer/.p7b 以 base64 存入仓库 Secrets，
   用 `hap-sign-tool`（commandline-tools 内含）签名 HAP —— 具体命令见 workflow 后续版本

> 简化路径：如果本地装了 DevEco Studio（任何一台电脑/朋友电脑），
> 用「File → Project Structure → Signing Configs → Automatically generate signature」一键搞定
> 上述全部证书材料，再把生成的 p12/cer/p7b 传到 GitHub Secrets 供云端签名。

### 6. 安装到 NEXT 手机
签名后的 HAP 通过数据线 + hdc 安装：
```
hdc install entry-default-signed.hap
```
（hdc 在 commandline-tools 的 sdk/default/openharmony/toolchains 里）

## 工程结构

```
├── build-profile.json5          # 工程级配置（API 12 / HarmonyOS）
├── hvigorfile.ts / hvigor/      # 构建脚本
├── AppScope/                    # 应用级配置（包名/图标/版本）
└── entry/
    └── src/main/ets/
        ├── protocol/HeaterProtocol.ets   # 协议层（与网页版逐位一致）
        ├── ble/BleClient.ets             # BLE 低功耗透传（扫描/GATT/特征自动配对）
        ├── ble/SppClient.ets             # 经典蓝牙 SPP 透传（JDY-31/HC-05）
        ├── model/AppStore.ets            # 数据流单例（轮询/日志/连接）
        ├── pages/Index.ets               # 主界面（连接/状态14项/时间/日志）
        └── entryability/EntryAbility.ets
```

## 说明
- 曲线图（温度趋势）暂未实现，后续可加 Canvas 绘制
- 阳极倒计时为 0x0B/0x0C 大端 uint16，状态卡内实时显示
- 时间写入：`buildWriteFrame(0x0D, [week,h,m,s])`，协议与网页版一致
