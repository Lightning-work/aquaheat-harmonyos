// 探测 repo.harmonyos.com npm 仓库
const candidates = [
  'https://repo.harmonyos.com/npm/@ohos%2fhvigor',
  'https://repo.harmonyos.com/npm/@ohos%2fhvigor-ohos-plugin',
];

for (const url of candidates) {
  try {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    const short = url.replace('https://repo.harmonyos.com/npm/', '');
    if (res.ok) {
      const d = await res.json();
      const vs = Object.keys(d.versions ?? {});
      console.log(`✓ ${short}  latest=${d['dist-tags']?.latest ?? '?'}  versions(${vs.length}): ${vs.slice(-10).join(', ')}`);
    } else {
      console.log(`✗ ${short}  HTTP ${res.status}`);
    }
  } catch (e) {
    console.log(`✗ ${url}  ${e.message}`);
  }
}
