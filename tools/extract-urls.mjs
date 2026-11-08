// 从 HTML 提取下载直链
import { readFileSync } from 'node:fs';

const t = readFileSync(process.argv[2], 'utf8');
const re = /https?:\/\/[^\s"'<>]+\.(?:exe|zip)/gi;
const set = new Set();
let m;
while ((m = re.exec(t)) !== null) {
  set.add(m[0]);
}
[...set].forEach((u) => console.log(u));
