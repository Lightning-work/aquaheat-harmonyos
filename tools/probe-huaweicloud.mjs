// 探测 huaweicloud npm ohos 子仓库上的 hvigor 版本
const candidates = [
  'https://repo.huaweicloud.com/repository/npm/ohos/@ohos%2fhvigor',
  'https://repo.huaweicloud.com/repository/npm/ohos/hvigor',
  'https://repo.huaweicloud.com/repository/npm/ohos/@ohos%2fhvigor-ohos-plugin',
];

for (const url of candidates) {
  try {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    const short = url.replace('https://repo.huaweicloud.com/repository/npm/', '');
    if (res.ok) {
      const d = await res.json();
      const vs = Object.keys(d.versions ?? {});
      console.log(`✓ ${short}  latest=${d['dist-tags']?.latest ?? '?'}  versions(${vs.length}): ${vs.slice(-8).join(', ')}`);
    } else {
      console.log(`✗ ${short}  HTTP ${res.status}`);
    }
  } catch (e) {
    console.log(`✗ ${url}  ${e.message}`);
  }
}
