const {chromium}=require('playwright');
const [style,...scenes]=process.argv.slice(2);
(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--allow-file-access-from-files']});
const p=await b.newPage({viewport:{width:1920,height:1080}});
p.on('console',m=>console.log('[page]',m.text()));p.on('pageerror',e=>{console.log('[err]',e.message);process.exit(1)});
for(const sc of (scenes.length?scenes:['street','home'])){
  const t=Date.now();
  await p.goto('http://localhost:8765/'+(style==='diorama'?'page3d.html':'page.html')+'?style='+style+'&scene='+sc);
  await p.waitForFunction(()=>window.DONE,null,{timeout:180000});
  const data=await p.evaluate(()=>document.getElementById('out').toDataURL('image/png'));
  require('fs').mkdirSync(__dirname+'/out',{recursive:true});
  require('fs').writeFileSync(`${__dirname}/out/${style}_${sc}.png`,Buffer.from(data.split(',')[1],'base64'));
  console.log(style,sc,Date.now()-t,'ms');
}
await b.close();})();
