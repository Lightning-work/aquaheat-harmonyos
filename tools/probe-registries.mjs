// 探测 @ohos/hvigor 在哪些 registry 可用
const candidates = [
  'https://repo.huaweicloud.com/repository/npm/@ohos%2fhvigor',
  'https://mirrors.huaweicloud.com/repository/npm/@ohos%2fhvigor',
  'https://ohpm.openharmony.cn/ohpm/@ohos/hvigor',
  'https://ohpm.openharmony.cn/ohpm/@ohos%2Fhvigor',
  'https://registry.npmmirror.com/@ohos%2fhvigor',
  'https://registry.npmjs.org/@ohos%2fhvigor',
];

for (const url of candidates) {
  try {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    const short = url.replace('https://', '');
    if (res.ok) {
      const d = await res.json();
      const vs = Object.keys(d.versions ?? {});
      const latest = d['dist-tags']?.latest ?? '?';
      console.log(`✓ ${short}  latest=${latest}  versions(${vs.length}): ${vs.slice(-6).join(', ')}`);
    } else {
      console.log(`✗ ${short}  HTTP ${res.status}`);
    }
  } catch (e) {
    console.log(`✗ ${url}  ${e.message}`);
  }
}
