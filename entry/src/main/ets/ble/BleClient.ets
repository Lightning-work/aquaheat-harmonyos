/**
 * BleClient.ets —— 鸿蒙 BLE 低功耗蓝牙透传通道（@ohos.bluetooth.ble）
 * 扫描全部 BLE 设备 → 连接 → 枚举服务 → 按特征属性自动配对收发通道
 * （FFE0/FFF0/NUS 等常见透传模组清单，收发同体与分离收发均适配）。
 * 写方向 20 字节分片 + 20ms 间隔，兼容廉价模组 UART 缓冲。
 */
import { ble } from '@kit.ConnectivityKit';

/** 常见蓝牙透传服务 UUID（16 位短 UUID 展开为标准 128 位基准） */
function expandBaseUuid(short: number): string {
  const hex = short.toString(16).padStart(4, '0');
  return `0000${hex}-0000-1000-8000-00805f9b34fb`;
}

const KNOWN_SERVICES: string[] = [
  expandBaseUuid(0xffe0),
  expandBaseUuid(0xfff0),
  expandBaseUuid(0xae00),
  expandBaseUuid(0xfefb),
  expandBaseUuid(0xfee7),
  expandBaseUuid(0xffe5),
  '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
  '49535343-fe7d-4ae5-8fa9-9fafd205e455',
];

export interface ScanDevice {
  deviceId: string;
  deviceName: string;
  rssi: number;
}

export interface ChannelInfo {
  rxServiceUuid: string;
  rxCharUuid: string;
  txServiceUuid: string;
  txCharUuid: string;
  props: ble.GattProperties;
  info: string;
}

const CHUNK_SIZE: number = 20;
const CHUNK_GAP_MS: number = 20;

function shortUuid(uuid: string): string {
  const m = /^0000([0-9a-f]{4})-0000-1000-8000-00805f9b34fb$/.exec(uuid);
  if (m !== null) {
    return m[1].toUpperCase();
  }
  return uuid.slice(0, 8).toUpperCase();
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

export class BleTransport {
  private gatt: ble.GattClientDevice | null = null;
  private rx: ble.BLECharacteristic | null = null;
  private tx: ble.BLECharacteristic | null = null;
  private writeChain: Promise<void> = Promise.resolve();
  public connectedName: string = '';

  /** 扫描全部 BLE 设备，durationMs 后自动停止并返回结果 */
  async scanDevices(durationMs: number): Promise<ScanDevice[]> {
    const found: ScanDevice[] = [];
    const seen = new Set<string>();
    const onFind = (results: Array<ble.ScanResult>) => {
      for (const r of results) {
        if (seen.has(r.deviceId)) {
          continue;
        }
        seen.add(r.deviceId);
        const item: ScanDevice = {
          deviceId: r.deviceId,
          deviceName: r.deviceName && r.deviceName.length > 0 ? r.deviceName : '未知设备',
          rssi: r.rssi,
        };
        found.push(item);
      }
    };
    ble.on('BLEDeviceFind', onFind);
    try {
      const opt: ble.ScanOptions = {
        interval: 500,
        dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY,
        matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE,
      };
      ble.startBLEScan(opt);
      await sleep(durationMs);
      ble.stopBLEScan();
    } finally {
      ble.off('BLEDeviceFind', onFind);
    }
    // 信号强的排前
    found.sort((a: ScanDevice, b: ScanDevice) => b.rssi - a.rssi);
    return found;
  }

  /** 连接并自动配对收发特征；onData 为透传数据回调 */
  async connect(deviceId: string, name: string,
    onData: (bytes: Uint8Array) => void, onDisconnect: () => void): Promise<ChannelInfo> {
    this.connectedName = name;
    this.gatt = ble.createGattClientDevice(deviceId);
    this.gatt.on('BLEConnectionStateChange', (state: ble.BLEConnectionState) => {
      if (state.state !== ble.ProfileConnectionState.STATE_CONNECTED) {
        this.cleanup();
        onDisconnect();
      }
    });
    await this.gatt.connect();

    const services: Array<ble.GattService> = await this.gatt.getServices();
    const info = this.pickChannel(services);
    this.rx = info.rxChar;
    this.tx = info.txChar;

    // 订阅 notify 数据
    this.gatt.on('BLECharacteristicChange', (r: ble.BLECharacteristic) => {
      const v = r.value;
      if (v && v.byteLength > 0) {
        onData(new Uint8Array(v));
      }
    });
    if (this.rx !== null) {
      await this.gatt.setCharacteristicChangeNotification(this.rx, true);
    }
    return info;
  }

  /** 枚举服务树，按属性自动配对收发特征（优先已知服务与收发同体） */
  private pickChannel(services: Array<ble.GattService>): ChannelInfo {
    const known = new Set<string>(KNOWN_SERVICES);
    let pool: ble.GattService[] = [];
    let unknownPool: ble.GattService[] = [];
    for (const svc of services) {
      if (known.has(svc.serviceUuid.toLowerCase())) {
        pool.push(svc);
      } else {
        unknownPool.push(svc);
      }
    }
    if (pool.length === 0) {
      pool = unknownPool;
    }

    let rxChar: ble.BLECharacteristic | null = null;
    let rxSameAsTx = false;
    let txChar: ble.BLECharacteristic | null = null;
    for (const svc of pool) {
      for (const ch of svc.characteristics) {
        const p = ch.properties;
        if (!p) {
          continue;
        }
        const canNotify = p.notify === true || p.indicate === true;
        const canWrite = p.write === true || p.writeWithoutResponse === true;
        if (canNotify && rxChar === null) {
          rxChar = ch;
          rxSameAsTx = canWrite;
        }
        if (canWrite && txChar === null && rxChar !== ch) {
          txChar = ch;
        }
      }
    }
    if (rxChar === null) {
      throw new Error('未找到具备 Notify 属性的透传特征（非透传模组？）');
    }
    if (txChar === null && !rxSameAsTx) {
      throw new Error('未找到具备 Write 属性的透传特征（无法下发命令）');
    }
    if (txChar === null) {
      txChar = rxChar; // 收发同体
    }
    if (!this.gatt) {
      throw new Error('GATT 未连接');
    }
    const svcUuid = rxChar.serviceUuid;
    const rxUuid = rxChar.characteristicUuid;
    const txUuid = txChar.characteristicUuid;
    const info: ChannelInfo = {
      rxServiceUuid: svcUuid,
      rxCharUuid: rxUuid,
      txServiceUuid: txChar.serviceUuid,
      txCharUuid: txUuid,
      props: txChar.properties,
      info: rxSameAsTx
        ? `服务 ${shortUuid(svcUuid)} · 收发同体 ${shortUuid(rxUuid)}`
        : `服务 ${shortUuid(svcUuid)} · 收 ${shortUuid(rxUuid)} / 发 ${shortUuid(txUuid)}`,
    };
    return info;
  }

  /** 写透传字节（串行队列 + 分片） */
  async write(bytes: Uint8Array): Promise<void> {
    const task = this.writeChain.then(async () => {
      if (this.gatt === null || this.tx === null) {
        throw new Error('BLE 未连接');
      }
      for (let off = 0; off < bytes.length; off += CHUNK_SIZE) {
        const end = Math.min(off + CHUNK_SIZE, bytes.length);
        const chunk = bytes.slice(off, end);
        const ch: ble.BLECharacteristic = {
          serviceUuid: this.tx.serviceUuid,
          characteristicUuid: this.tx.characteristicUuid,
          descriptors: [],
          value: chunk.buffer,
        };
        const wt = this.tx.properties && this.tx.properties.write === true
          ? ble.GattWriteType.WRITE
          : ble.GattWriteType.WRITE_NO_RESPONSE;
        await this.gatt.writeCharacteristicValue(ch, wt);
        if (end < bytes.length) {
          await sleep(CHUNK_GAP_MS);
        }
      }
    });
    this.writeChain = task.catch(() => {
    });
    return task;
  }

  disconnect(): void {
    try {
      if (this.gatt !== null) {
        this.gatt.close();
      }
    } catch (e) {
      // 忽略关闭异常
    }
    this.cleanup();
  }

  private cleanup(): void {
    this.gatt = null;
    this.rx = null;
    this.tx = null;
  }
}
