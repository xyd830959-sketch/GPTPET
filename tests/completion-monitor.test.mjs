import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {CompletionMonitor} from '../fox-spirit/runtime/completion-monitor.mjs';

function fixture(){
  if(!process.env.GPTPET_TEST_ROOT)throw new Error('Use the isolated test runner.');
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'fox-completion-'));
  const workspace=path.join(root,'workspace'),start=Date.now();
  const meta=(id,cwd=workspace,source='vscode')=>JSON.stringify({type:'session_meta',payload:{id,cwd,source}})+'\n';
  const event=(type,turn,at=start+1000)=>JSON.stringify({timestamp:new Date(at).toISOString(),type:'event_msg',payload:{type,turn_id:turn,last_agent_message:'synthetic-private-text'}})+'\n';
  const file=path.join(root,'main.jsonl');fs.writeFileSync(file,meta('main'));
  return {root,workspace,start,meta,event,file,monitor:new CompletionMonitor({sessionsRoot:root,workspace,now:start})};
}
test('completion events keep filtering, partial-line handling, deduplication and restart boundaries',()=>{
  const f=fixture();f.monitor.poll(f.start);
  const other=path.join(f.root,'other.jsonl'),child=path.join(f.root,'child.jsonl');
  fs.writeFileSync(other,f.meta('other',path.join(f.root,'elsewhere'))+f.event('task_complete','other'));
  fs.writeFileSync(child,f.meta('child',f.workspace,{subagent:{type:'worker'}})+f.event('task_complete','child'));
  fs.appendFileSync(f.file,f.event('task_started','one'));
  assert.equal(f.monitor.poll(f.start+2000).busy,true);
  const done=f.event('task_complete','one',f.start+3000);
  fs.appendFileSync(f.file,done.slice(0,-1));assert.equal(f.monitor.poll(f.start+4000).events.length,0);
  fs.appendFileSync(f.file,'\n'+done+f.event('turn_aborted','cancel')+f.event('task_complete','cancel'));
  const result=f.monitor.poll(f.start+17000);
  assert.equal(result.events.length,1);assert.equal(result.busy,false);
  assert(!JSON.stringify(result).includes('synthetic-private-text'));
  const restarted=new CompletionMonitor({sessionsRoot:f.root,workspace:f.workspace,now:f.start+18000});
  assert.equal(restarted.poll(f.start+18000).events.length,0);
});
test('one unreadable discovery directory does not suppress a healthy tracked completion',()=>{
  const f=fixture();f.monitor.poll(f.start);
  const blocked=path.join(f.root,'blocked');fs.mkdirSync(blocked);
  const original=fs.readdirSync;
  fs.readdirSync=function(dir,...args){if(path.resolve(dir)===blocked)throw Object.assign(new Error('synthetic access failure'),{code:'EACCES'});return original.call(this,dir,...args);};
  try{
    fs.appendFileSync(f.file,f.event('task_complete','healthy',f.start+16000));
    const result=f.monitor.poll(f.start+17000);
    assert.equal(result.events.length,1);assert.equal(result.error,'EACCES');
  }finally{fs.readdirSync=original;}
  assert.equal(f.monitor.poll(f.start+33000).error,'');
});
test('session tracking remains bounded as new sessions accumulate',()=>{
  const f=fixture();f.monitor.poll(f.start);
  for(let batch=1;batch<=6;batch++){
    for(let i=0;i<32;i++){
      const file=path.join(f.root,`session-${batch}-${i}.jsonl`);fs.writeFileSync(file,f.meta(`${batch}-${i}`));
      const date=new Date(f.start+batch*16000);fs.utimesSync(file,date,date);
    }
    f.monitor.poll(f.start+batch*16000);
    assert(f.monitor.files.size<=128,'The tracked-file table must stay bounded.');
  }
});
test('a burst of interrupted turns cannot grow the deduplication set without limit',()=>{
  const f=fixture();f.monitor.poll(f.start);
  fs.appendFileSync(f.file,Array.from({length:1300},(_,i)=>f.event('turn_aborted',`abort-${i}`)).join(''));
  f.monitor.poll(f.start+2000);
  assert(f.monitor.seen.size<=1024,'Aborted turns must use the same bounded deduplication policy.');
});
test('large earlier logs do not indefinitely starve a later file within the read budget',()=>{
  const f=fixture();
  const files=Array.from({length:5},(_,i)=>path.join(f.root,`budget-${i}.jsonl`));
  files.forEach((p,i)=>fs.writeFileSync(p,f.meta(`budget-${i}`)));
  f.monitor.poll(f.start);
  // Use the actual insertion order; the regression is independent of directory ordering.
  const order=[...f.monitor.files.keys()];
  const noisy=JSON.stringify({type:'response_item',payload:{text:'x'.repeat(1000)}})+'\n';
  order.slice(0,4).forEach(p=>fs.appendFileSync(p,noisy.repeat(900)));
  fs.appendFileSync(order[4],f.event('task_complete','not-starved'));
  f.monitor.poll(f.start+2000);
  assert.equal(f.monitor.poll(f.start+4000).events.length,1);
});
