// Offline integration: temporary generated workspaces and local-source validation copies.
// Only fmt, init without backend and validate; no AWS configuration or plan/apply.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {execFileSync}=require('node:child_process');
const assert=require('node:assert/strict');
const {render}=require('../tools/render-eks.cjs');
const root=path.resolve(__dirname,'..');
const binary=process.env.TERRAFORM_BIN,mirror=process.env.TERRAFORM_PROVIDER_MIRROR;
if(!binary||!mirror)throw Error('Set TERRAFORM_BIN and TERRAFORM_PROVIDER_MIRROR to existing local installations');
const env=Object.fromEntries(Object.entries(process.env).filter(([k])=>!k.startsWith('AWS_')&&!k.startsWith('TF_')));
const work=fs.mkdtempSync(path.join(os.tmpdir(),'eks-render-integration-'));
const config=path.join(work,'offline.tfrc');
fs.writeFileSync(config,`provider_installation {\n filesystem_mirror { path = ${JSON.stringify(path.resolve(mirror))} }\n}\ndisable_checkpoint = true\n`);
env.TF_CLI_CONFIG_FILE=config;env.CHECKPOINT_DISABLE='1';env.AWS_EC2_METADATA_DISABLED='true';
function validate(directory,label){
 fs.copyFileSync(path.join(root,'tests/.terraform.lock.hcl'),path.join(directory,'.terraform.lock.hcl'));
 for(const args of [['fmt','-check','-recursive'],['init','-backend=false','-input=false','-lockfile=readonly','-no-color'],['validate','-json']]){
  try{
   const output=execFileSync(binary,[`-chdir=${directory}`,...args],{env,encoding:'utf8',timeout:60000});
   if(args[0]==='validate'){const data=JSON.parse(output);assert.equal(data.valid,true);console.log(`VALIDATE OK ${label}: ${data.error_count} errors, ${data.warning_count} warnings`);}
  }catch(error){console.error('Validation directory:',directory);if(error.stdout)console.error(String(error.stdout));if(error.stderr)console.error(String(error.stderr));throw error;}
 }
}
for(const teamId of ['D001','D002']){
 const result=render({teamId,environment:'dev',sequence:1,moduleSha:'a'.repeat(40)},JSON.parse(fs.readFileSync(path.join(root,'templates/eks/selection.D001.json'))));
 const generated=path.join(work,'generated/platform-engineering-devs',result.workspace);
 fs.mkdirSync(generated,{recursive:true});
 for(const [file,text]of Object.entries(result.files))fs.writeFileSync(path.join(generated,file),text);
 const local=path.join(work,'validation',teamId);fs.mkdirSync(local,{recursive:true});
 let checked=0;
 const main=result.files['main.tf'].replace(/git::https:\/\/github.com\/roko1987-k8s\/platform-engineering-vars-tfc.git\/\/aws\/dev\/eks\/(modules\/[^?"\s]+)\?ref=[a-f0-9]{40}/g,(_,relative)=>{
  const modulePath=path.join(root,relative);assert.ok(fs.statSync(modulePath).isDirectory());checked++;return modulePath;
 });
 assert.equal(checked,8);
 for(const [file,text]of Object.entries(result.files))fs.writeFileSync(path.join(local,file),file==='main.tf'?main:text);
 // Retain negative mock test coverage as a recipe next to the TEMP root; do not run plan.
 const testDir=path.join(local,'tests');fs.mkdirSync(testDir);
 const recipe=fs.readFileSync(path.join(root,'tests/fixtures/workspace-draft.tftest.hcl.template'),'utf8').replaceAll('D001',teamId);
 fs.writeFileSync(path.join(testDir,'workspace-draft.tftest.hcl'),recipe);
 validate(local,teamId);
 console.log('Generated workspace:',generated);
}
for(const [name,source]of [['composition',path.join(root,'examples/composition')],['bootstrap',path.join(root,'automation/terraform-aws/bootstrap')]]){
 const local=path.join(work,'validation',name);fs.mkdirSync(local,{recursive:true});
 for(const file of fs.readdirSync(source).filter(x=>x.endsWith('.tf'))){
  let text=fs.readFileSync(path.join(source,file),'utf8');
  text=text.replace(/source\s*=\s*"(\.\.\/[^"\n]+)"/g,(_,relative)=>`source = "${path.resolve(source,relative)}"`);
  if(name==='composition')text=text.replace('default = "../../../eks.yaml"',`default = "${path.resolve(root,'../eks.yaml')}"`);
  text=execFileSync(binary,['fmt','-'],{input:text,encoding:'utf8'});
  fs.writeFileSync(path.join(local,file),text);
 }
 validate(local,name);
}
console.log('Temporary integration root:',work);
