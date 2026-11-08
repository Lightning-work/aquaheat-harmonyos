// 测试 commandline-tools 下载直链
const urls = {
  asc: 'https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_package_901_9/69/v3/GXguSlvmS4WK5-FFdo38DA/commandline-tools-linux-x64-26.0.0.865.zip.asc?HW-CC-KV=V1&HW-CC-Date=20261031T025608Z&HW-CC-Expire=315360000000&HW-CC-Sign=2628949A306CF8B875A0DC293B99D59F14F077202F79142BC50B071F7FAC2158',
  zip: 'https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_package_901_9/69/v3/GXguSlvmS4WK5-FFdo38DA/commandline-tools-linux-x64-26.0.0.865.zip?HW-CC-KV=V1&HW-CC-Date=20261031T025608Z&HW-CC-Expire=315360000000&HW-CC-Sign=2628949A306CF8B875A0DC293B99D59F14F077202F79142BC50B071F7FAC2158',
};

async function probe(name, url) {
  try {
    const res = await fetch(url, { method: 'GET', headers: { Range: 'bytes=0-1023' } });
    const len = res.headers.get('content-length');
    const cr = res.headers.get('content-range');
    console.log(`${name}: HTTP ${res.status} | content-length=${len} | range=${cr}`);
    return res.status;
  } catch (e) {
    console.log(`${name}: FAILED ${e.message}`);
    return 0;
  }
}

await probe('ASC', urls.asc);
await probe('ZIP', urls.zip);
