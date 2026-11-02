const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {render}=require('../tools/render-eks.cjs');
const context={teamId:'D001',environment:'dev',sequence:1,moduleSha:'a'.repeat(40)}; // synthetic SHA, tests only
const selection={system:{size:'S',minimum:1,desired:1,maximum:2},user:{size:'M',minimum:1,desired:2,maximum:2}};
let tests=0;
function test(name,fn){fn();tests++;console.log('PASS '+name);}
test('D001 selection and exact remote sources',()=>{
 const r=render(context,selection), s=r.files['main.tf'];
 assert.equal(r.workspace,'workspaces/D001/terraform/aws/dev/eks-01');
 assert.match(s, /"system"\s*:\s*"S",\s*"user"\s*:\s*"M"/);
 const sources=[...s.matchAll(/source\s*=\s*"([^"]+)"/g)].map(x=>x[1]).filter(x=>x.startsWith('git::'));
 assert.equal(sources.length,8);
 for(const source of sources){
  assert.ok(source.endsWith('?ref='+context.moduleSha));
  const modulePath=source.split('//aws/dev/eks/')[1].split('?')[0];
  assert.ok(fs.statSync(path.resolve(__dirname,'..',modulePath)).isDirectory());
 }
 assert.match(r.files['backend.hcl'],/states\/D001\/aws\/dev\/eks-01\/terraform.tfstate/);
 assert.equal(Object.keys(r.files).filter(x=>x.endsWith('.tf')).length,1);
 assert.match(s,/NETWORKING_PENDING/);
 assert.match(s,/conformity\s*=\s*"pending"/);
 assert.match(s,/jsondecode\(file\(local.catalog_path\)\)/);
 assert.equal(JSON.parse(r.files['catalog.snapshot.json']).eks.nodegroups.user.sizes.M,'m7i.2xlarge');
});
test('all four S/M combinations',()=>{for(const system of ['S','M'])for(const user of ['S','M'])render(context,{system:{...selection.system,size:system},user:{...selection.user,size:user}});});
test('D002 state separation',()=>assert.match(render({...context,teamId:'D002'},selection).files['backend.hcl'],/states\/D002\//));
test('reject invalid profiles',()=>assert.throws(()=>render(context,{...selection,system:{...selection.system,size:'L'}})));
test('reject unordered, noninteger and excessive quantities',()=>{for(const desired of [0,3,1.5])assert.throws(()=>render(context,{...selection,system:{...selection.system,desired}}));assert.throws(()=>render(context,{...selection,user:{...selection.user,minimum:2,desired:1}}));});
test('reject injected developer configuration',()=>{for(const key of ['teamId','region','instance_type','role','bucket','stateKey'])assert.throws(()=>render(context,{...selection,system:{...selection.system,[key]:'untrusted'}}));});
test('reject mutable or malformed refs',()=>{for(const moduleSha of ['main','v1','../x','a'.repeat(39)])assert.throws(()=>render({...context,moduleSha},selection));});
test('reject coerced context arrays',()=>{
 assert.throws(()=>render({...context,teamId:['D001']},selection));
 assert.throws(()=>render({...context,moduleSha:[context.moduleSha]},selection));
});
// Synthetic parser responses prove policies are read, without editing the real catalog.
const YAML=require('yaml');
function withCatalog(change,fn){const parse=YAML.parse;YAML.parse=(...args)=>{const c=parse(...args);change(c.eks);return c;};try{fn();}finally{YAML.parse=parse;}}
test('catalog controls per-profile bounds',()=>withCatalog(c=>{c.nodegroups.user.max_count=1;},()=>assert.throws(()=>render(context,selection))));
test('catalog controls aggregate maximum',()=>withCatalog(c=>{c.nodegroups.limits.max_total_nodes=3;},()=>assert.throws(()=>render(context,selection))));
test('catalog EC2 mapping is preserved without renderer fallback',()=>withCatalog(c=>{c.nodegroups.user.sizes.M='SYNTHETIC_TEST_MAPPING';},()=>{
 const r=render(context,selection);
 assert.equal(JSON.parse(r.files['catalog.snapshot.json']).eks.nodegroups.user.sizes.M,'SYNTHETIC_TEST_MAPPING');
 assert.ok(!r.files['main.tf'].includes('m7i.'));
}));
test('documented D001 example equals current renderer output',()=>{
 const input=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../templates/eks/selection.D001.json')));
 const expected=render(context,input).files['main.tf'].replaceAll(context.moduleSha,'<SHA_REAL>');
 assert.equal(fs.readFileSync(path.resolve(__dirname,'../templates/eks/D001-System-S-User-M.main.tf.example'),'utf8'),expected);
});
console.log(`${tests} renderer tests passed`);
