// 验证用户提供的 zip 直链
const url = process.argv[2];
const res = await fetch(url, { method: 'GET', headers: { Range: 'bytes=0-1023' } });
console.log(`HTTP ${res.status} | range=${res.headers.get('content-range')} | type=${res.headers.get('content-type')}`);
