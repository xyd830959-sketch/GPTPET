// Read only explicit lifecycle metadata; never persist conversation text.
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';

const normal=value=>path.resolve(value).replace(/^\\\\\?\\/,'').replaceAll('\\','/').toLowerCase().replace(/\/$/,'');
const MAX_FILES=128,MAX_SEEN=1024,READ_BUDGET=1024*1024,CHUNK_BYTES=256*1024;
const endTurn=(state,key)=>{if(state.active===key||state.active===state.id+'|startup')state.active=null;};
export class CompletionMonitor {
  constructor({sessionsRoot,workspace,now=Date.now()}) {
    this.root=sessionsRoot;this.workspace=normal(workspace);this.startedAt=now;
    this.files=new Map();this.events=[];this.seen=new Set();this.nextScan=0;
    this.lastError='';this.scanError='';this.initial=true;this.cursor=0;
  }
  remember(id) {
    if(this.seen.has(id))return false;
    this.seen.add(id);
    if(this.seen.size>MAX_SEEN)this.seen=new Set([...this.seen].slice(-MAX_SEEN/2));
    return true;
  }
  track(file,state,now) {
    if(this.files.size>=MAX_FILES){
      // Prefer recent active sessions, but always bound the table and its carry buffers.
      const ranked=[...this.files].sort((a,b)=>{
        const active=row=>Boolean(row.active&&now-row.modifiedAt<300000);
        return Number(active(a[1]))-Number(active(b[1]))||a[1].modifiedAt-b[1].modifiedAt;
      });
      this.files.delete(ranked[0][0]);
    }
    this.files.set(file,state);
  }
  discover(now) {
    if(now<this.nextScan)return;
    this.nextScan=now+15000;this.scanError='';
    const candidates=[];
    const visit=(dir,depth)=>{
      if(depth>3)return;
      let entries;
      try{entries=fs.readdirSync(dir,{withFileTypes:true});}
      catch(error){this.scanError=error.code??'unavailable';if(depth===0)throw error;return;}
      for(const entry of entries){
        const file=path.join(dir,entry.name);
        if(entry.isDirectory())visit(file,depth+1);
        else if(entry.isFile()&&entry.name.endsWith('.jsonl')){
          try{
            const stat=fs.statSync(file);
            if(stat.mtimeMs>=this.startedAt-86400000)candidates.push({file,stat});
          }catch(error){if(error.code!=='ENOENT')this.scanError=error.code??'unavailable';}
        }
      }
    };
    visit(this.root,0);
    for(const {file,stat} of candidates.sort((a,b)=>b.stat.mtimeMs-a.stat.mtimeMs).slice(0,MAX_FILES)){
      if(this.files.has(file)){this.files.get(file).modifiedAt=stat.mtimeMs;continue;}
      let fd,meta;
      try{
        fd=fs.openSync(file,'r');
        const head=Buffer.alloc(Math.min(65536,stat.size));fs.readSync(fd,head,0,head.length,0);
        const first=head.toString('utf8').replace(/^\uFEFF/,'').split('\n')[0];
        const record=JSON.parse(first);if(record.type==='session_meta')meta=record.payload;
      }catch{continue;}finally{if(fd!==undefined)fs.closeSync(fd);}
      if(!meta?.cwd||normal(meta.cwd)!==this.workspace||typeof meta.source!=='string')continue;
      // Startup seeds EOF. Newly discovered files may have finished since startup.
      const offset=this.initial?stat.size:Math.max(0,stat.size-1024*1024);
      const state={offset,carry:Buffer.alloc(0),discard:offset>0&&!this.initial,id:meta.id??file,active:null,modifiedAt:stat.mtimeMs};
      if(this.initial&&now-stat.mtimeMs<120000){
        let fd;const size=Math.min(stat.size,512*1024);const tail=Buffer.alloc(size);
        try{fd=fs.openSync(file,'r');fs.readSync(fd,tail,0,size,stat.size-size);}catch{continue;}finally{if(fd!==undefined)fs.closeSync(fd);}
        let lifecycle=null,hasActivity=false;
        for(const line of tail.toString('utf8').split('\n').reverse()){
          try{
            const row=JSON.parse(line);
            if(row.type==='event_msg'&&['task_started','task_complete','turn_aborted'].includes(row.payload?.type)){lifecycle=row.payload.type;break;}
            if(row.type==='response_item'||row.type==='event_msg')hasActivity=true;
          }catch{}
        }
        if(lifecycle==='task_started'||(!lifecycle&&hasActivity))state.active=state.id+'|startup';
      }
      this.track(file,state,now);
    }
    this.initial=false;
  }
  accept(record,state,now) {
    if(record?.type!=='event_msg')return;
    const event=record.payload;if(!event||typeof event.turn_id!=='string')return;
    const at=Date.parse(record.timestamp);
    if(!Number.isFinite(at)||at<this.startedAt||at>now+2000)return;
    const key=state.id+'|'+event.turn_id;
    if(event.type==='task_started'){state.active=key;return;}
    if(event.type==='turn_aborted'){endTurn(state,key);this.remember(createHash('sha256').update(key).digest('hex'));return;}
    if(event.type!=='task_complete')return;
    endTurn(state,key);
    const id=createHash('sha256').update(key).digest('hex');
    if(!this.remember(id))return;
    if(now-at<=120000)this.events.push({id,at,kind:'reply-ready'});
    this.events=this.events.slice(-20);
  }
  poll(now=Date.now()) {
    try{this.discover(now);}catch(error){this.scanError=error.code??'unavailable';}
    try{
      let budget=READ_BUDGET;
      const entries=[...this.files];
      const start=entries.length?this.cursor%entries.length:0;
      for(let checked=0;checked<entries.length;checked++){
        if(budget<=0)break;
        const index=(start+checked)%entries.length;
        const [file,state]=entries[index];
        this.cursor=(index+1)%entries.length;
        try{
          const stat=fs.statSync(file);const size=stat.size;state.modifiedAt=stat.mtimeMs;
          if(size<state.offset){state.offset=size;state.carry=Buffer.alloc(0);state.discard=false;state.active=null;}
          const length=Math.min(size-state.offset,CHUNK_BYTES,budget);if(length<=0)continue;
          const fd=fs.openSync(file,'r');const chunk=Buffer.alloc(length);let count;
          try{count=fs.readSync(fd,chunk,0,length,state.offset);}finally{fs.closeSync(fd);}
          state.offset+=count;budget-=count;
          const data=Buffer.concat([state.carry,chunk.subarray(0,count)]);let start=0,end;
          while((end=data.indexOf(10,start))>=0){
            if(state.discard)state.discard=false;
            else if(end-start<=1024*1024){try{this.accept(JSON.parse(data.subarray(start,end).toString('utf8')),state,now);}catch{}}
            start=end+1;
          }
          state.carry=Buffer.from(data.subarray(start));
          if(state.carry.length>1024*1024){state.carry=Buffer.alloc(0);state.discard=true;}
        }catch(error){if(error.code==='ENOENT')this.files.delete(file);} // Rotation never blocks another session.
      }
      this.lastError=this.scanError;
    }catch(error){this.lastError=error.code??'unavailable';}
    return {at:now,busy:[...this.files.values()].some(state=>state.active&&now-state.modifiedAt<300000),events:this.events,source:'local-task-complete',tracked:this.files.size,error:this.lastError};
  }
}
