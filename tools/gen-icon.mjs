// 生成鸿蒙分层图标所需的最小 PNG（纯色 + 简单图形），无需任何依赖
// 用法: node gen-icon.mjs <输出路径> <模式: bg|fg>
import { deflateSync } from 'node:zlib';
import { writeFileSync } from 'node:fs';

const S = 216;
const mode = process.argv[3] ?? 'bg';

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const t = Buffer.from(type, 'ascii');
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([t, data])));
  return Buffer.concat([len, t, data, crcBuf]);
}

// RGBA 像素
const px = Buffer.alloc(S * S * 4);
const put = (x, y, r, g, b, a = 255) => {
  if (x < 0 || y < 0 || x >= S || y >= S) return;
  const i = (y * S + x) * 4;
  px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = a;
};

const cx = S / 2, cy = S / 2;
if (mode === 'bg') {
  // 背景：靛蓝渐变（简单近似：上深下浅）
  for (let y = 0; y < S; y++) {
    const t = y / S;
    const r = Math.round(79 - 20 * t), g = Math.round(70 + 32 * t), b = Math.round(229 - 20 * t);
    for (let x = 0; x < S; x++) put(x, y, r, g, b);
  }
} else {
  // 前景：透明底 + 白色水滴 + 白色圆环（热水意象）
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const dx = x - cx, dy = y - cy;
      const dist = Math.sqrt(dx * dx + dy * dy);
      // 外圆环
      if (dist >= 74 && dist <= 82) { put(x, y, 255, 255, 255); continue; }
      // 水滴（泪滴形：圆 + 上尖）
      const dropCx = cx, dropCy = cy + 12;
      const inCircle = (dx * dx) + ((y - dropCy) * (y - dropCy)) <= 34 * 34;
      const inTip = y >= dropCy - 34 && y <= dropCy - 22 && Math.abs(dx) <= (dropCy - y) * 0.55;
      if (inCircle || inTip) put(x, y, 255, 255, 255);
    }
  }
}

// 组装 PNG
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(S, 0);
ihdr.writeUInt32BE(S, 4);
ihdr[8] = 8;  // bit depth
ihdr[9] = 6;  // color type RGBA
const raw = Buffer.alloc((S * 4 + 1) * S);
for (let y = 0; y < S; y++) {
  raw[y * (S * 4 + 1)] = 0; // filter none
  px.copy(raw, y * (S * 4 + 1) + 1, y * S * 4, (y + 1) * S * 4);
}
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr),
  chunk('IDAT', deflateSync(raw, { level: 9 })),
  chunk('IEND', Buffer.alloc(0)),
]);
writeFileSync(process.argv[2], png);
console.log(`written ${process.argv[2]} (${png.length} bytes)`);
