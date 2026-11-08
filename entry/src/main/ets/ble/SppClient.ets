/**
 * SppClient.ets —— 鸿蒙经典蓝牙 SPP（RFCOMM）透传通道
 * 支持 JDY-31-SPP / HC-05 等经典蓝牙串口模组。
 * 前提：已在系统蓝牙完成配对；此处列出已配对设备并直连 RFCOMM。
 * 注意：spp 不在 @kit.ConnectivityKit 导出列表中，直接从 @ohos.bluetooth.spp 引入。
 */
import { connection } from '@kit.ConnectivityKit';
import spp from '@ohos.bluetooth.spp';

const SPP_UUID: string = '00001101-0000-1000-8000-00805f9b34fb';

export interface PairedDevice {
  deviceId: string;
  deviceName: string;
}

export class SppTransport {
  private socketId: number = -1;
  private connectedName: string = '';
  private readHandler: ((bytes: Uint8Array) => void) | null = null;

  /** 列出系统已配对的经典蓝牙设备（SDK 26 只返回设备地址字符串数组） */
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
    const opt: spp.SppConnectOptions = {
      uuid: SPP_UUID,
      secure: true,
      type: spp.SppType.SPP_RFCOMM,
    };
    this.socketId = await spp.sppConnect(deviceId, opt);

    spp.on('sppRead', (data: spp.SppReadData) => {
      if (data.clientId === this.socketId && this.readHandler !== null) {
        const ab: ArrayBuffer = data.data;
        if (ab.byteLength > 0) {
          this.readHandler(new Uint8Array(ab));
        }
      }
    });

    // 断连探测依赖写失败 + 轮询超时暴露
    void onDisconnect;
  }

  /** 写透传字节（SPP 无 MTU 分片限制，整帧一次写入） */
  async write(bytes: Uint8Array): Promise<void> {
    if (this.socketId < 0) {
      throw new Error('SPP 未连接');
    }
    await spp.sppWrite(this.socketId, bytes.buffer);
  }

  disconnect(): void {
    try {
      if (this.socketId >= 0) {
        spp.sppCloseClientSocket(this.socketId);
      }
    } catch (e) {
      // 忽略关闭异常
    }
    this.socketId = -1;
    this.readHandler = null;
  }
}
