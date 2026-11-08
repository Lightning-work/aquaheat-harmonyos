/**
 * SppClient.ets —— 鸿蒙经典蓝牙 SPP（RFCOMM）透传通道
 * SDK 26：SPP API 位于 @ohos.bluetooth.socket（原 @ohos.bluetooth.spp 已并入）。
 * 前提：已在系统蓝牙完成配对（connection.getPairedDevices 仅返回地址字符串）。
 */
import { connection } from '@kit.ConnectivityKit';
import socket from '@ohos.bluetooth.socket';

const SPP_UUID: string = '00001101-0000-1000-8000-00805f9b34fb';

export interface PairedDevice {
  deviceId: string;
  deviceName: string;
}

export class SppTransport {
  private socketId: number = -1;
  private connectedName: string = '';
  private readHandler: ((bytes: Uint8Array) => void) | null = null;

  /** 列出系统已配对的经典蓝牙设备（仅地址字符串，名称由用户自行识别 MAC） */
  async listPaired(): Promise<PairedDevice[]> {
    const out: PairedDevice[] = [];
    const devices = await connection.getPairedDevices();
    for (const mac of devices) {
      const item: PairedDevice = {
        deviceId: mac,
        deviceName: mac,
      };
      out.push(item);
    }
    return out;
  }

  /** 连接已配对设备（RFCOMM/SPP）；onData 为透传数据回调 */
  async connect(deviceId: string, name: string,
    onData: (bytes: Uint8Array) => void, onDisconnect: () => void): Promise<void> {
    this.connectedName = name;
    this.readHandler = onData;
    const opt: socket.SppOptions = {
      uuid: SPP_UUID,
      secure: true,
      type: socket.SppType.SPP_RFCOMM,
    };
    this.socketId = await new Promise<number>((resolve: (v: number) => void, reject: (e: Error) => void) => {
      socket.sppConnect(deviceId, opt, (err, id) => {
        if (err) {
          const e = new Error(`sppConnect 失败 · ${err.message ?? JSON.stringify(err)}`);
          reject(e);
        } else {
          resolve(id);
        }
      });
    });

    socket.on('sppRead', this.socketId, (ab: ArrayBuffer) => {
      if (ab.byteLength > 0 && this.readHandler !== null) {
        this.readHandler(new Uint8Array(ab));
      }
    });

    // 断连探测依赖写失败 + 轮询超时暴露
    void onDisconnect;
    void this.connectedName;
  }

  /** 写透传字节（SPP 无 MTU 分片限制，整帧一次写入） */
  async write(bytes: Uint8Array): Promise<void> {
    if (this.socketId < 0) {
      throw new Error('SPP 未连接');
    }
    const buf: ArrayBuffer = bytes.buffer as ArrayBuffer;
    await socket.sppWriteAsync(this.socketId, buf);
  }

  disconnect(): void {
    try {
      if (this.socketId >= 0) {
        socket.sppCloseClientSocket(this.socketId);
      }
    } catch (e) {
      // 忽略关闭异常
    }
    this.socketId = -1;
    this.readHandler = null;
  }
}
