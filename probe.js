const ts = Process.enumerateThreads();
console.log('THREADS=' + ts.length);
for (const t of ts) {
  console.log('T id=' + t.id + ' name=' + t.name + ' state=' + t.state);
}
try {
  const main = ts.find(t => t.id === 1) || ts[0];
  const bt = Thread.backtrace(main.context, Backtracer.ACCURATE);
  console.log('MAIN_BT ' + bt.slice(0, 24).map(a => {
    try { const s = DebugSymbol.fromAddress(a); return (s.moduleName||'?') + '!' + (s.name||a); } catch(e) { return String(a); }
  }).join('\n'));
} catch(e) { console.log('BT_ERR ' + e); }
