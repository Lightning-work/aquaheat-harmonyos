/**
 * AppStore.ets —— 中央数据流单例（与网页版 useHeater.js 同构）
 * 轮询回路：500ms 发读帧 → 1.2s 无应答计失败（只计数，持续重发，断开才停）
 * 通道：BLE 低功耗透传 / SPP 经典蓝牙透传
 */
import {
  buildReadFrame,
  buildWriteFrame,
  bytesToHex,
  CMD_READ_RESPONSE,
  CMD_WRITE_ACK,
  CMD_ACK_NAK,
  getErrorName,
  ADDR_ALL_START,
  ADDR_ALL_LENGTH,
  ADDR_TIME_START,
  FrameReceiver,
  ParsedFrame,
  RegData,
  emptyRegData,
  parseRegisterPayload,
  WEEK_NAMES,
} from '../protocol/HeaterProtocol';
import { BleTransport, ScanDevice } from '../ble/BleClient';
import { SppTransport, PairedDevice } from '../ble/SppClient';
import { common } from '@kit.AbilityKit';

export const POLL_MS: number = 500;
export const HISTORY_MAX: number = 480;
export const LOG_MAX: number = 300;

export interface LogItem {
  id: number;
  ts: string;
  dir: string; // TX | RX | ERR | SYS
  text: string;
}

export type TransportKind = 'ble' | 'spp';

export interface TrendPoint {
  t: string;
  current: number;
  avg: number;
  ntc1: number;
  ntc2: number;
}

function nowStamp(): string {
  const d = new Date();
  const p = (n: number, w: number = 2): string => n.toString().padStart(w, '0');
  return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}.${p(d.getMilliseconds(), 3)}`;
}

export class AppStore {
  private static instance: AppStore | null = null;

  public static getInstance(): AppStore {
    if (AppStore.instance === null) {
      AppStore.instance = new AppStore();
    }
    return AppStore.instance;
  }

  /* 状态（Index 页通过 listener 镜像到 @State） */
  public open: boolean = false;
  public connecting: boolean = false;
  public scanning: boolean = false;
  public transport: TransportKind | '' = '';
  public deviceName: string = '';
  public channelInfo: string = '';
  public hasData: boolean = false;
  public consecutiveFails: number = 0;
  public txBytes: number = 0;
  public rxBytes: number = 0;
  public framesTx: number = 0;
  public framesRx: number = 0;
  public badFrames: number = 0;
  public regs: RegData = emptyRegData();
  public history: TrendPoint[] = [];
  public logs: LogItem[] = [];
  public bleScanResults: ScanDevice[] = [];
  public pairedDevices: PairedDevice[] = [];

  private listeners: (() => void)[] = [];
  private receiver: FrameReceiver = new FrameReceiver();
  private ble: BleTransport = new BleTransport();
  private spp: SppTransport = new SppTransport();
  private pollTimer: number = -1;
  private logSeq: number = 0;
  private readSeq: number = 0;
  private outstandingReads: Set<number> = new Set();
  private context: common.Context | null = null;

  public onUpdate(listener: () => void): void {
    this.listeners.push(listener);
  }

  public offUpdate(listener: () => void): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }

  private notify(): void {
    for (const l of this.listeners) {
      l();
    }
  }

  public init(context: common.Context): void {
    this.context = context;
    this.receiver.onFrame = (frame: Uint8Array, parsed: ParsedFrame) => {
      this.handleDeviceFrame(frame, parsed);
    };
    this.log('SYS', 'AquaHeat Console 鸿蒙版 · 就绪（未连接）');
    this.log('SYS', '协议 V1.0 · 帧 9+N · 500ms 轮询 · 无应答持续重发');
  }

  private log(dir: string, text: string, note?: string): void {
    let full = text;
    if (note !== undefined && note !== '') {
      full = `${text}  ; ${note}`;
    }
    const item: LogItem = { id: ++this.logSeq, ts: nowStamp(), dir: dir, text: full };
    this.logs.push(item);
    if (this.logs.length > LOG_MAX) {
      this.logs.splice(0, this.logs.length - LOG_MAX);
    }
    this.notify();
  }

  /* ---------------- 连接管理 ---------------- */

  public async refreshPaired(): Promise<void> {
    try {
      this.pairedDevices = await this.spp.listPaired();
      this.log('SYS', `经典蓝牙已配对设备 ${this.pairedDevices.length} 台`);
      this.notify();
    } catch (e) {
      this.log('ERR', `获取已配对设备失败 · ${(e as Error).message}`);
    }
  }

  public async scanBle(durationMs: number): Promise<void> {
    if (this.scanning || this.open) {
      return;
    }
    this.scanning = true;
    this.notify();
    try {
      this.log('SYS', `BLE 扫描中（${Math.round(durationMs / 1000)} 秒）...`);
      this.bleScanResults = await this.ble.scanDevices(durationMs);
      this.log('SYS', `BLE 扫描完成 · 发现 ${this.bleScanResults.length} 台设备`);
    } catch (e) {
      this.log('ERR', `BLE 扫描失败 · ${(e as Error).message}`);
    }
    this.scanning = false;
    this.notify();
  }

  public async connectSpp(device: PairedDevice): Promise<void> {
    if (this.open || this.connecting) {
      return;
    }
    this.connecting = true;
    this.transport = 'spp';
    this.notify();
    try {
      await this.spp.connect(device.deviceId, device.deviceName,
        (bytes: Uint8Array) => this.feedDeviceBytes(bytes),
        () => this.onChannelLost('经典蓝牙已断开'));
      this.finishConnect(device.deviceName, `SPP · ${device.deviceId}`);
    } catch (e) {
      this.connecting = false;
      this.transport = '';
      this.log('ERR', `SPP 连接失败 · ${(e as Error).message}`);
      this.notify();
    }
  }

  public async connectBle(device: ScanDevice): Promise<void> {
    if (this.open || this.connecting) {
      return;
    }
    this.connecting = true;
    this.transport = 'ble';
    this.notify();
    try {
      const info = await this.ble.connect(device.deviceId, device.deviceName,
        (bytes: Uint8Array) => this.feedDeviceBytes(bytes),
        () => this.onChannelLost('BLE 已断开'));
      this.finishConnect(device.deviceName, info.info);
    } catch (e) {
      this.connecting = false;
      this.transport = '';
      this.log('ERR', `BLE 连接失败 · ${(e as Error).message}`);
      this.notify();
    }
  }

  private finishConnect(name: string, info: string): void {
    this.open = true;
    this.connecting = false;
    this.deviceName = name;
    this.channelInfo = info;
    this.hasData = false;
    this.consecutiveFails = 0;
    this.outstandingReads.clear();
    this.receiver.clear();
    this.history = [];
    this.log('SYS', `蓝牙通道建立 · ${name} · ${info}`, );
    this.log('SYS', `启动轮询（${POLL_MS}ms）· 与串口模式协议一致`);
    this.startTimers();
    this.notify();
  }

  private onChannelLost(msg: string): void {
    if (this.open) {
      this.stopTimers();
      this.open = false;
      this.hasData = false;
      this.transport = '';
      this.deviceName = '';
      this.channelInfo = '';
      this.outstandingReads.clear();
      this.log('SYS', msg, '重新连接即可');
      this.notify();
    }
  }

  public disconnect(): void {
    if (!this.open) {
      return;
    }
    this.stopTimers();
    const kind = this.transport === 'ble' ? 'BLE' : 'SPP';
    if (this.transport === 'ble') {
      this.ble.disconnect();
    } else if (this.transport === 'spp') {
      this.spp.disconnect();
    }
    this.open = false;
    this.hasData = false;
    this.transport = '';
    this.deviceName = '';
    this.channelInfo = '';
    this.outstandingReads.clear();
    this.log('SYS', `${kind} 已断开`);
    this.notify();
  }

  /* ---------------- 轮询回路 ---------------- */

  private startTimers(): void {
    this.stopTimers();
    this.pollTimer = setInterval(() => {
      this.pollTick();
    }, POLL_MS);
  }

  private stopTimers(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private pollTick(): void {
    if (!this.open) {
      return;
    }
    const frame = buildReadFrame(ADDR_ALL_START, ADDR_ALL_LENGTH);
    const token = ++this.readSeq;
    this.outstandingReads.add(token);
    this.sendFrame(frame, '读全部参数 0x00~0x12');
    this.framesTx++;
    // 无应答 1.2s 计失败：只计数，轮询持续重发，断开才停止
    setTimeout(() => {
      if (this.outstandingReads.has(token) && this.open) {
        this.outstandingReads.delete(token);
        this.consecutiveFails++;
        this.log('ERR', `读帧无应答 · 超时 1200ms（连续第 ${this.consecutiveFails} 次）`, undefined);
      }
    }, 1200);
  }

  private sendFrame(frame: Uint8Array, note: string): void {
    this.txBytes += frame.length;
    const hex = bytesToHex(frame);
    this.log('TX', note === '' ? hex : `${hex}  ; ${note}`);
    if (this.transport === 'ble') {
      this.ble.write(frame).catch((e: Error) => {
        this.log('ERR', `BLE 发送失败 · ${e.message}`);
      });
    } else if (this.transport === 'spp') {
      this.spp.write(frame).catch((e: Error) => {
        this.log('ERR', `SPP 发送失败 · ${e.message}`);
      });
    }
  }

  private feedDeviceBytes(bytes: Uint8Array): void {
    this.rxBytes += bytes.length;
    this.receiver.append(bytes);
  }

  private handleDeviceFrame(frame: Uint8Array, parsed: ParsedFrame): void {
    this.framesRx++;
    if (parsed.cmd === CMD_READ_RESPONSE) {
      this.outstandingReads.clear();
      this.hasData = true;
      this.regs = parseRegisterPayload(parsed.payload, parsed.startAddr);
      this.pushHistory();
      this.consecutiveFails = 0;
      this.log('RX', `读取应答 0x${parsed.startAddr.toString(16).toUpperCase()} · ${parsed.payload.length}B`);
    } else if (parsed.cmd === CMD_WRITE_ACK) {
      const ok = parsed.payload.length > 0 && parsed.payload[0] === 1;
      const err = ok ? '成功' : getErrorName(parsed.payload.length > 1 ? parsed.payload[1] : 0);
      this.log('RX', `写入应答 · ${ok ? '成功' : `失败 ${err}`}`);
    } else if (parsed.cmd === CMD_ACK_NAK) {
      const err = parsed.payload.length > 0 ? getErrorName(parsed.payload[0]) : '未知';
      this.log('ERR', `NAK · ${err}`);
    }
    this.notify();
  }

  private pushHistory(): void {
    const r = this.regs;
    const p = (n: number, w: number = 2): string => n.toString().padStart(w, '0');
    const label = `${p(r.hour)}:${p(r.minute)}:${p(r.second)}`;
    const avg = Math.round((r.ntc1Temp + r.ntc2Temp) / 2);
    const point: TrendPoint = {
      t: label,
      current: r.currentTemp,
      avg: avg,
      ntc1: r.ntc1Temp,
      ntc2: r.ntc2Temp,
    };
    this.history.push(point);
    if (this.history.length > HISTORY_MAX) {
      this.history.shift();
    }
  }

  /* ---------------- 写时间 ---------------- */

  public writeTime(week: number, hour: number, minute: number, second: number): void {
    if (!this.open) {
      this.log('SYS', '写入失败 · 蓝牙未连接');
      return;
    }
    const payload: number[] = [week & 0xff, hour & 0xff, minute & 0xff, second & 0xff];
    const frame = buildWriteFrame(ADDR_TIME_START, payload);
    const p = (n: number): string => n.toString().padStart(2, '0');
    const weekName = week < WEEK_NAMES.length ? WEEK_NAMES[week] : '--';
    this.sendFrame(frame, `写时间 0x0D · ${weekName} ${p(hour)}:${p(minute)}:${p(second)}`);
    this.framesTx++;
  }

  public syncLocalTime(): void {
    const d = new Date();
    this.writeTime(d.getDay(), d.getHours(), d.getMinutes(), d.getSeconds());
  }

  public clearLog(): void {
    this.logs = [];
    this.log('SYS', '调试日志已清空');
  }
}
