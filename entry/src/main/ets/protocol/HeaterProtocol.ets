/**
 * HeaterProtocol.ets —— SC95F861x 热水器串口协议（V1.0）· ArkTS 移植版
 * 帧格式：[AA 55][Ver][Cmd][StartAddr][DataLen][Payload:N][Checksum][0D 0A]
 * 总帧长 = 9 + N；校验和 = (Ver + Cmd + StartAddr + DataLen + ΣPayload) & 0xFF。
 * 与网页版 heaterProtocol.js 逐位一致；分包/粘包由 FrameReceiver 重同步处理。
 */

export const SYNC_HEADER_1: number = 0xaa;
export const SYNC_HEADER_2: number = 0x55;
export const FRAME_TAIL_1: number = 0x0d;
export const FRAME_TAIL_2: number = 0x0a;
export const PROTOCOL_VERSION: number = 0x01;

export const CMD_READ: number = 0x01;
export const CMD_WRITE: number = 0x02;
export const CMD_READ_RESPONSE: number = 0x81;
export const CMD_WRITE_ACK: number = 0x82;
export const CMD_ACK_NAK: number = 0xfe;

export const ADDR_ALL_START: number = 0x00;
export const ADDR_ALL_LENGTH: number = 0x13;
export const ADDR_TIME_START: number = 0x0d;

export const WORK_MODE_NAMES: string[] =
  ['普通模式', '健康浴', '瀑布洗', '速热洗', 'ECO节能', '智能模式', '峰谷用电'];
export const WEEK_NAMES: string[] =
  ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const WINDOW_NAMES: string[] = ['BOOT', 'SLEEP', 'WORK', 'ERROR', 'TEST'];
const WIFI_NAMES: string[] = ['本地模式', '配网中', '已连云端', '产测WiFi'];
const ERROR_NAMES: string[] =
  ['成功(OK)', '非法地址', '长度溢出', '只读地址写入', '参数非法', '校验失败', '执行失败'];

export interface RegisterInfo {
  addr: number;
  name: string;
  writable: boolean;
}

export const REGISTER_MAP: RegisterInfo[] = [
  { addr: 0x00, name: '协议版本', writable: false },
  { addr: 0x01, name: 'NTC1 下胆温度', writable: false },
  { addr: 0x02, name: 'NTC2 上胆温度', writable: false },
  { addr: 0x03, name: '平均温度', writable: false },
  { addr: 0x04, name: '当前水温', writable: false },
  { addr: 0x05, name: '目标水温', writable: false },
  { addr: 0x06, name: '工作模式', writable: false },
  { addr: 0x07, name: '故障码', writable: false },
  { addr: 0x08, name: 'RY1 状态', writable: false },
  { addr: 0x09, name: 'RY2 状态', writable: false },
  { addr: 0x0a, name: '设备状态字', writable: false },
  { addr: 0x0b, name: '阳极倒计时高字节', writable: false },
  { addr: 0x0c, name: '阳极倒计时低字节', writable: false },
  { addr: 0x0d, name: '星期', writable: true },
  { addr: 0x0e, name: '时', writable: true },
  { addr: 0x0f, name: '分', writable: true },
  { addr: 0x10, name: '秒', writable: true },
  { addr: 0x11, name: '预约使能', writable: false },
  { addr: 0x12, name: '预约小时', writable: false },
];

export interface RegData {
  protocolVersion: number;
  ntc1Temp: number;
  ntc2Temp: number;
  avgTemp: number;
  currentTemp: number;
  targetTemp: number;
  workMode: number;
  faultCode: number;
  ry1State: number;
  ry2State: number;
  deviceStatus: number;
  anodeCountdown: number;
  weekDay: number;
  hour: number;
  minute: number;
  second: number;
  reserveEnable: number;
  reserveHour: number;
}

export interface ParsedFrame {
  cmd: number;
  startAddr: number;
  payload: Uint8Array;
}

export function emptyRegData(): RegData {
  const d: RegData = {
    protocolVersion: 1,
    ntc1Temp: 0,
    ntc2Temp: 0,
    avgTemp: 0,
    currentTemp: 0,
    targetTemp: 0,
    workMode: 0,
    faultCode: 0,
    ry1State: 0,
    ry2State: 0,
    deviceStatus: 0,
    anodeCountdown: 0,
    weekDay: 0,
    hour: 0,
    minute: 0,
    second: 0,
    reserveEnable: 0,
    reserveHour: 0,
  };
  return d;
}

/** 从 [start, start+length) 计算累加和（低 8 位） */
function sumRange(data: Uint8Array, start: number, length: number): number {
  let sum = 0;
  for (let i = 0; i < length; i++) {
    sum = (sum + data[start + i]) & 0xff;
  }
  return sum;
}

/** 构造读取寄存器请求帧（9 字节） */
export function buildReadFrame(startAddr: number, length: number): Uint8Array {
  const frame = new Uint8Array(9);
  frame[0] = SYNC_HEADER_1;
  frame[1] = SYNC_HEADER_2;
  frame[2] = PROTOCOL_VERSION;
  frame[3] = CMD_READ;
  frame[4] = startAddr & 0xff;
  frame[5] = length & 0xff;
  frame[6] = sumRange(frame, 2, 4);
  frame[7] = FRAME_TAIL_1;
  frame[8] = FRAME_TAIL_2;
  return frame;
}

/** 构造写入寄存器请求帧（9 + N 字节） */
export function buildWriteFrame(startAddr: number, payload: number[]): Uint8Array {
  const n = payload.length;
  const frame = new Uint8Array(9 + n);
  frame[0] = SYNC_HEADER_1;
  frame[1] = SYNC_HEADER_2;
  frame[2] = PROTOCOL_VERSION;
  frame[3] = CMD_WRITE;
  frame[4] = startAddr & 0xff;
  frame[5] = n & 0xff;
  for (let i = 0; i < n; i++) {
    frame[6 + i] = payload[i] & 0xff;
  }
  frame[6 + n] = sumRange(frame, 2, 4 + n);
  frame[7 + n] = FRAME_TAIL_1;
  frame[8 + n] = FRAME_TAIL_2;
  return frame;
}

/** 解析完整帧（调用方保证 frame 长度 ≥ 9 + dataLen） */
export function tryParseFrame(frame: Uint8Array): ParsedFrame | null {
  if (frame.length < 9) {
    return null;
  }
  if (frame[0] !== SYNC_HEADER_1 || frame[1] !== SYNC_HEADER_2) {
    return null;
  }
  const dataLen = frame[5];
  const expected = 9 + dataLen;
  if (frame.length < expected) {
    return null;
  }
  if (frame[expected - 2] !== FRAME_TAIL_1 || frame[expected - 1] !== FRAME_TAIL_2) {
    return null;
  }
  const calc = sumRange(frame, 2, 4 + dataLen);
  if (calc !== frame[6 + dataLen]) {
    return null;
  }
  const payload = frame.slice(6, 6 + dataLen);
  const p: ParsedFrame = { cmd: frame[3], startAddr: frame[4], payload: payload };
  return p;
}

export function bytesToHex(data: Uint8Array): string {
  let out = '';
  for (let i = 0; i < data.length; i++) {
    let h = data[i].toString(16).toUpperCase();
    if (h.length < 2) {
      h = '0' + h;
    }
    out += (i > 0 ? ' ' : '') + h;
  }
  return out;
}

/** 按起始地址偏移解析数据域 → 寄存器模型（大端仅阳极字段） */
export function parseRegisterPayload(payload: Uint8Array, startAddr: number): RegData {
  const d = emptyRegData();
  const get = (fieldAddr: number): number => {
    const idx = fieldAddr - startAddr;
    return idx >= 0 && idx < payload.length ? payload[idx] : 0;
  };
  d.protocolVersion = get(0x00);
  d.ntc1Temp = get(0x01);
  d.ntc2Temp = get(0x02);
  d.avgTemp = get(0x03);
  d.currentTemp = get(0x04);
  d.targetTemp = get(0x05);
  d.workMode = get(0x06);
  d.faultCode = get(0x07);
  d.ry1State = get(0x08);
  d.ry2State = get(0x09);
  d.deviceStatus = get(0x0a);
  d.anodeCountdown = ((get(0x0b) << 8) | get(0x0c)) >>> 0;
  d.weekDay = get(0x0d);
  d.hour = get(0x0e);
  d.minute = get(0x0f);
  d.second = get(0x10);
  d.reserveEnable = get(0x11);
  d.reserveHour = get(0x12);
  return d;
}

export function getFaultName(code: number): string {
  return code === 0 ? '无故障' : `故障 0x${code.toString(16).toUpperCase().padStart(2, '0')}`;
}

export function getWindowName(status: number): string {
  const v = status & 0x0f;
  return v < WINDOW_NAMES.length ? WINDOW_NAMES[v] : `未知(${v})`;
}

export function getWifiName(status: number): string {
  const w = (status >> 4) & 0x0f;
  return w < WIFI_NAMES.length ? WIFI_NAMES[w] : `未知(${w})`;
}

export function getErrorName(code: number): string {
  return code < ERROR_NAMES.length ? ERROR_NAMES[code] : `0x${code.toString(16)}`;
}

export function getWorkModeName(mode: number): string {
  return mode < WORK_MODE_NAMES.length ? WORK_MODE_NAMES[mode] : '未知';
}

/** 阳极倒计时（秒）→ "天/时:分:秒" 展示 */
export function getAnodeDisplay(sec: number): string {
  const d = Math.floor(sec / 86400);
  const h = Math.floor((sec % 86400) / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  const p = (n: number): string => n.toString().padStart(2, '0');
  if (d > 0) {
    return `${d}天${h}时${m}分`;
  }
  return `${p(h)}:${p(m)}:${p(s)}`;
}

/**
 * 帧接收器：任意分包边界到达，自动按 AA 55 同步头重同步
 */
export class FrameReceiver {
  private buffer: number[] = [];
  public onFrame: ((frame: Uint8Array, parsed: ParsedFrame) => void) | null = null;
  public badFrames: number = 0;

  append(data: Uint8Array): void {
    if (data.length === 0) {
      return;
    }
    for (let i = 0; i < data.length; i++) {
      this.buffer.push(data[i]);
    }
    if (this.buffer.length > 1024) {
      this.buffer.length = 0;
      return;
    }
    this.extract();
  }

  clear(): void {
    this.buffer.length = 0;
  }

  private extract(): void {
    for (;;) {
      if (this.buffer.length < 9) {
        return;
      }
      if (this.buffer[0] !== SYNC_HEADER_1 || this.buffer[1] !== SYNC_HEADER_2) {
        this.buffer.shift();
        continue;
      }
      const dataLen = this.buffer[5];
      const expected = 9 + dataLen;
      if (this.buffer.length < expected) {
        return;
      }
      const frame = new Uint8Array(expected);
      for (let i = 0; i < expected; i++) {
        frame[i] = this.buffer[i];
      }
      const parsed = tryParseFrame(frame);
      if (parsed !== null) {
        this.buffer.splice(0, expected);
        if (this.onFrame) {
          this.onFrame(frame, parsed);
        }
      } else {
        this.buffer.shift(); // 丢弃同步头首字节，向后重同步
        this.badFrames++;
      }
    }
  }
}
