/**
 * Index.ets —— AquaHeat Console 鸿蒙主页面
 * 分区：连接（BLE / SPP 双通道）→ 状态总览（14 项）→ 时间设置 → 调试日志
 */
import { AppStore, LogItem, TransportKind } from '../model/AppStore';
import { ScanDevice } from '../ble/BleClient';
import { PairedDevice } from '../ble/SppClient';
import {
  getWindowName,
  getWifiName,
  getFaultName,
  getWorkModeName,
  getAnodeDisplay,
  WEEK_NAMES,
  RegData,
  emptyRegData,
} from '../protocol/HeaterProtocol';

const ACCENT: string = '#6366F1';
const CARD_BG: string = '#FFFFFF';
const INSET: string = '#F6F7FB';
const TEXT1: string = '#111827';
const TEXT2: string = '#4B5563';
const TEXT3: string = '#9CA3AF';
const HAIRLINE: string = '#E5E7EB';
const OK: string = '#22C55E';
const WARN: string = '#F59E0B';
const INFO: string = '#06B6D4';
const DANGER: string = '#EF4444';

/** 可复用卡片容器（标题 + 内容插槽） */
@Component
struct CardShell {
  title: string = '';
  @BuilderParam content: () => void = emptyCard;

  build() {
    Column() {
      Row({ space: 7 }) {
        Text(this.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor(TEXT1)
      }
      this.content()
    }
    .width('100%')
    .padding(13)
    .borderRadius(14)
    .backgroundColor(CARD_BG)
    .border({ width: 1, color: HAIRLINE })
    .alignItems(HorizontalAlign.Start)
  }
}

@Builder
function emptyCard() {
}

@Entry
@Component
struct Index {
  @State open: boolean = false;
  @State connecting: boolean = false;
  @State scanning: boolean = false;
  @State transport: TransportKind | '' = '';
  @State deviceName: string = '';
  @State channelInfo: string = '';
  @State hasData: boolean = false;
  @State fails: number = 0;
  @State regs: RegData = emptyRegData();
  @State logs: LogItem[] = [];
  @State bleResults: ScanDevice[] = [];
  @State paired: PairedDevice[] = [];
  @State selPaired: string = '';
  @State selBle: string = '';
  @State week: number = 1;
  @State hour: number = 12;
  @State minute: number = 0;
  @State second: number = 0;
  private store: AppStore = AppStore.getInstance();
  private listener: (() => void) = () => {
  };
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.listener = () => {
      this.mirrorState();
    };
    this.store.onUpdate(this.listener);
    this.mirrorState();
    this.store.refreshPaired();
  }

  aboutToDisappear(): void {
    this.store.offUpdate(this.listener);
  }

  private mirrorState(): void {
    this.open = this.store.open;
    this.connecting = this.store.connecting;
    this.scanning = this.store.scanning;
    this.transport = this.store.transport;
    this.deviceName = this.store.deviceName;
    this.channelInfo = this.store.channelInfo;
    this.hasData = this.store.hasData;
    this.fails = this.store.consecutiveFails;
    this.regs = this.store.regs;
    this.logs = this.store.logs;
    this.bleResults = this.store.bleScanResults;
    this.paired = this.store.pairedDevices;
  }

  /** 温度类字段展示：未应答显示 -- */
  private tempText(v: number): string {
    return this.hasData ? `${v} ℃` : '--';
  }

  private stateText(v: string): string {
    return this.hasData ? v : '--';
  }

  private numState(v: number): number {
    return this.hasData ? v : 0;
  }

  build() {
    Column() {
      this.headerBar()
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          this.connectionCard()
          this.statusCard()
          this.clockCard()
          this.logCard()
          Blank().height(30)
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 14 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F3F4F6')
  }

  /* ---------- 顶栏 ---------- */
  @Builder
  headerBar() {
    Row({ space: 10 }) {
      Text('💧')
        .fontSize(20)
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .borderRadius(10)
        .backgroundColor(ACCENT)
      Column({ space: 1 }) {
        Text('AquaHeat Console')
          .fontSize(15).fontWeight(FontWeight.Bold).fontColor(TEXT1)
        Text(this.open ? `已连接 ${this.deviceName}` : '未连接 · 鸿蒙版')
          .fontSize(10.5).fontColor(this.open ? OK : TEXT3)
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Row({ space: 5 }) {
        Circle({ width: 7, height: 7 })
          .fill(this.hasData ? OK : this.open ? WARN : TEXT3)
        Text(this.hasData ? '轮询中 500ms' : this.open ? '持续重发中' : '离线')
          .fontSize(10.5).fontColor(TEXT2)
      }
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(12)
      .backgroundColor(this.open ? '#ECFDF5' : '#F3F4F6')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  /* ---------- 连接卡 ---------- */
  @Builder
  connectionCard() {
    CardShell({ title: '🔗 蓝牙连接 · BLE / SPP 双通道' }) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Circle({ width: 8, height: 8 })
            .fill(this.open ? OK : TEXT3)
          Text(this.open ? `通道在线 · ${this.transport.toUpperCase()} · ${this.channelInfo}`
            : '通道离线 · SPP 先配对再连接；BLE 点扫描选择')
            .fontSize(11).fontColor(TEXT2)
            .layoutWeight(1)
        }
        .width('100%')
        .padding(9)
        .borderRadius(8)
        .backgroundColor(INSET)

        Text('经典蓝牙 SPP（JDY-31-SPP / HC-05）')
          .fontSize(11).fontColor(TEXT3)

        List({ space: 6 }) {
          ForEach(this.paired, (d: PairedDevice) => {
            ListItem() {
              Row({ space: 8 }) {
                Radio({ value: d.deviceId, group: 'spp' })
                  .checked(this.selPaired === d.deviceId)
                  .onChange((v: boolean) => {
                    if (v) {
                      this.selPaired = d.deviceId;
                    }
                  })
                  .radioStyle({ checkedBackgroundColor: ACCENT })
                  .width(18).height(18)
                Text(d.deviceName)
                  .fontSize(12.5).fontColor(TEXT1).fontWeight(FontWeight.Medium)
                  .layoutWeight(1)
                Text(d.deviceId)
                  .fontSize(9.5).fontColor(TEXT3)
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 7, bottom: 7 })
              .borderRadius(8)
              .backgroundColor(this.selPaired === d.deviceId ? '#EEF2FF' : INSET)
              .onClick(() => {
                this.selPaired = d.deviceId;
              })
            }
          }, (d: PairedDevice) => d.deviceId)
        }
        .width('100%')
        .height(this.paired.length > 0 ? Math.min(140, this.paired.length * 38) : 0)

        Row({ space: 8 }) {
          if (!this.open || this.transport !== 'spp') {
            Button('连接 SPP 设备')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .backgroundColor(ACCENT).fontColor(Color.White)
              .fontSize(12.5).height(34)
              .layoutWeight(1)
              .enabled(this.selPaired !== '' && !this.open && !this.connecting)
              .onClick(() => {
                const dev = this.store.pairedDevices.find((x: PairedDevice) => x.deviceId === this.selPaired);
                if (dev) {
                  this.store.connectSpp(dev);
                }
              })
            Button('刷新配对')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .backgroundColor(INSET).fontColor(TEXT2)
              .fontSize(11.5).height(34)
              .onClick(() => {
                this.store.refreshPaired();
              })
          }
          if (this.open && this.transport === 'spp') {
            Button('断开连接')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .backgroundColor(Color.White).fontColor(DANGER)
              .border({ width: 1, color: '#FCA5A5' })
              .fontSize(12.5).height(34)
              .layoutWeight(1)
              .onClick(() => {
                this.store.disconnect();
              })
          }
        }
        .width('100%')

        Text('未配对？请先到系统设置 → 蓝牙 中配对模组（JDY-31 PIN 1234），回来点「刷新配对」。BLE 扫描列表不会出现经典蓝牙模组，属正常现象。')
          .fontSize(10).fontColor(TEXT3).lineHeight(15)

        Divider().color(HAIRLINE)
        Text('低功耗蓝牙 BLE（JDY-23 / HC-08 / CH9141 等）')
          .fontSize(11).fontColor(TEXT3)

        List({ space: 6 }) {
          ForEach(this.bleResults, (d: ScanDevice) => {
            ListItem() {
              Row({ space: 8 }) {
                Radio({ value: d.deviceId, group: 'ble' })
                  .checked(this.selBle === d.deviceId)
                  .onChange((v: boolean) => {
                    if (v) {
                      this.selBle = d.deviceId;
                    }
                  })
                  .radioStyle({ checkedBackgroundColor: ACCENT })
                  .width(18).height(18)
                Text(d.deviceName)
                  .fontSize(12.5).fontColor(TEXT1).fontWeight(FontWeight.Medium)
                  .layoutWeight(1)
                Text(`${d.rssi} dBm`)
                  .fontSize(9.5).fontColor(TEXT3)
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 7, bottom: 7 })
              .borderRadius(8)
              .backgroundColor(this.selBle === d.deviceId ? '#EEF2FF' : INSET)
              .onClick(() => {
                this.selBle = d.deviceId;
              })
            }
          }, (d: ScanDevice) => d.deviceId)
        }
        .width('100%')
        .height(this.bleResults.length > 0 ? Math.min(150, this.bleResults.length * 38) : 0)

        Row({ space: 8 }) {
          if (!this.open || this.transport !== 'ble') {
            Button(this.scanning ? '扫描中...' : '扫描 BLE 设备')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .backgroundColor('#0EA5E9').fontColor(Color.White)
              .fontSize(12.5).height(34)
              .layoutWeight(1)
              .enabled(!this.scanning && !(this.open && this.transport === 'spp'))
              .onClick(() => {
                this.store.scanBle(3000);
              })
            Button('连接选中')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .backgroundColor(INSET).fontColor(TEXT2)
              .fontSize(11.5).height(34)
              .enabled(this.selBle !== '' && !this.open && !this.connecting)
              .onClick(() => {
                const dev = this.store.bleScanResults.find((x: ScanDevice) => x.deviceId === this.selBle);
                if (dev) {
                  this.store.connectBle(dev);
                }
              })
          }
          if (this.open && this.transport === 'ble') {
            Button('断开连接')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .backgroundColor(Color.White).fontColor(DANGER)
              .border({ width: 1, color: '#FCA5A5' })
              .fontSize(12.5).height(34)
              .layoutWeight(1)
              .onClick(() => {
                this.store.disconnect();
              })
          }
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  /* ---------- 状态总览卡（14 项） ---------- */
  @Builder
  statusRow(label: string, note: string, value: string, color: string) {
    Row({ space: 8 }) {
      Text(label).fontSize(12).fontColor(TEXT2).layoutWeight(1)
      Text(note).fontSize(9).fontColor(TEXT3)
      Text(value).fontSize(12).fontWeight(FontWeight.Medium).fontColor(color)
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
    .border({ width: { bottom: 0.5 }, color: HAIRLINE })
  }

  @Builder
  statusCard() {
    CardShell({ title: '📊 设备状态 · 全量 14 项' }) {
      Column({ space: 0 }) {
        this.statusRow('NTC1 下胆温度', '0x01', this.tempText(this.regs.ntc1Temp), TEXT1)
        this.statusRow('NTC2 上胆温度', '0x02', this.tempText(this.regs.ntc2Temp), TEXT1)
        this.statusRow('平均温度', '0x03', this.tempText(this.regs.avgTemp), TEXT1)
        this.statusRow('当前水温', '0x04', this.tempText(this.regs.currentTemp), WARN)
        this.statusRow('目标水温', '0x05', this.tempText(this.regs.targetTemp), INFO)
        this.statusRow('设备窗口', 'bit[3:0]', this.stateText(getWindowName(this.regs.deviceStatus)), TEXT1)
        this.statusRow('WiFi 云端', 'bit[7:4]', this.stateText(getWifiName(this.regs.deviceStatus)), TEXT1)
        this.statusRow('RY1 加热继电器', '0x08',
          this.stateText(this.regs.ry1State === 1 ? '闭合' : '断开'),
          this.numState(this.regs.ry1State) === 1 ? WARN : TEXT1)
        this.statusRow('RY2 换向继电器', '0x09',
          this.stateText(this.regs.ry2State === 1 ? '闭合' : '断开'),
          this.numState(this.regs.ry2State) === 1 ? INFO : TEXT1)
        this.statusRow('故障码', '0x07', this.stateText(getFaultName(this.regs.faultCode)),
          this.numState(this.regs.faultCode) !== 0 ? WARN : OK)
        this.statusRow('工作模式', '0x06', this.stateText(getWorkModeName(this.regs.workMode)), TEXT1)
        this.statusRow('预约使能', '0x11',
          this.stateText(this.regs.reserveEnable === 1 ? '开启' : '关闭'), TEXT1)
        this.statusRow('预约小时', '0x12', this.hasData ? `${this.regs.reserveHour} h` : '--', TEXT1)
        this.statusRow('阳极倒计时', '0x0B/C', this.stateText(getAnodeDisplay(this.regs.anodeCountdown)), TEXT1)
      }
      .width('100%')
    }
  }

  /* ---------- 时间设置卡 ---------- */
  @Builder
  clockCard() {
    CardShell({ title: '⏰ 时间设置（可写区 0x0D~0x10）' }) {
      Column({ space: 10 }) {
        Row({ space: 6 }) {
          ForEach(WEEK_NAMES, (w: string, i: number) => {
            Text(w.slice(1))
              .fontSize(10.5)
              .fontColor(this.week === i ? Color.White : TEXT2)
              .padding({ left: 6, right: 6, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor(this.week === i ? ACCENT : INSET)
              .onClick(() => {
                this.week = i;
              })
          }, (w: string) => w)
        }

        Row({ space: 10 }) {
          this.numField('时', this.hour, (): number => this.hour, (v: number): void => {
            this.hour = v;
          })
          this.numField('分', this.minute, (): number => this.minute, (v: number): void => {
            this.minute = v;
          })
          this.numField('秒', this.second, (): number => this.second, (v: number): void => {
            this.second = v;
          })
        }
        .width('100%')

        Row({ space: 8 }) {
          Button('写入时间')
            .buttonStyle(ButtonStyleMode.NORMAL)
            .backgroundColor(ACCENT).fontColor(Color.White)
            .fontSize(12.5).height(34)
            .layoutWeight(1)
            .onClick(() => {
              this.store.writeTime(this.week, this.hour, this.minute, this.second);
            })
          Button('同步本机时间')
            .buttonStyle(ButtonStyleMode.NORMAL)
            .backgroundColor(Color.White).fontColor(ACCENT)
            .border({ width: 1, color: ACCENT })
            .fontSize(12.5).height(34)
            .layoutWeight(1)
            .onClick(() => {
              this.store.syncLocalTime();
            })
        }
        .width('100%')

        Text('周日 = 0 · 24h 制 · 写入帧 buildWriteFrame(0x0D, 4B)')
          .fontSize(9.5).fontColor(TEXT3)
      }
      .width('100%')
    }
  }

  @Builder
  numField(label: string, label0: string, getV: () => number, setV: (v: number) => void) {
    Column({ space: 4 }) {
      Text(label).fontSize(10).fontColor(TEXT3)
      Row() {
        Text('−')
          .fontSize(14).fontColor(TEXT2)
          .padding(8)
          .onClick(() => {
            const v = getV();
            if (v > 0) {
              setV(v - 1);
            }
          })
        Text(getV().toString().padStart(2, '0'))
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor(TEXT1)
          .width(28).textAlign(TextAlign.Center)
        Text('+')
          .fontSize(14).fontColor(TEXT2)
          .padding(8)
          .onClick(() => {
            const v = getV();
            if (v < 99) {
              setV(v + 1);
            }
          })
      }
      .justifyContent(FlexAlign.Center)
      .borderRadius(8)
      .backgroundColor(INSET)
    }
    .alignItems(HorizontalAlign.Center)
  }

  /* ---------- 调试日志卡 ---------- */
  @Builder
  logCard() {
    CardShell({ title: '🧪 协议调试日志' }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text('帧 TX/RX · 无应答持续重发（断开连接才停止）')
            .fontSize(10).fontColor(TEXT3).layoutWeight(1)
          Text('清空')
            .fontSize(11).fontColor(DANGER)
            .padding(4)
            .onClick(() => {
              this.store.clearLog();
            })
        }
        .width('100%')

        Column() {
          ForEach(this.logs, (l: LogItem) => {
            Row({ space: 6 }) {
              Text(l.ts).fontSize(9).fontColor(TEXT3)
              Text(l.dir)
                .fontSize(9).fontWeight(FontWeight.Bold)
                .fontColor(l.dir === 'TX' ? '#3B82F6' : l.dir === 'RX' ? OK : l.dir === 'ERR' ? WARN : TEXT3)
              Text(l.text)
                .fontSize(9.5).fontColor(TEXT2)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding({ top: 3, bottom: 3 })
          }, (l: LogItem) => l.id.toString())
        }
        .width('100%')
        .height(200)
        .alignContent(Alignment.Bottom)
      }
      .width('100%')
    }
  }
}
