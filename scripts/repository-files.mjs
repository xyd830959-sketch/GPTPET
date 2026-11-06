import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const localDirectories=new Set(['.git','node_modules','work','dist','state','verification-data','experiment-data','test-results','codex-wallpaper-profile']);
export function isLocalOnly(relative){
  const parts=relative.replaceAll('\\','/').split('/');
  const name=parts.at(-1);
  return parts.some(part=>localDirectories.has(part)) ||
    /^(?:installation\.json(?:\.(?:new|previous))?|(?:auth|credentials)\.json)$|^\.env(?:\.|$)|\.(?:pem|key|log)$/i.test(name)&&name!=='.env.example' ||
    /(?:^|\/)runtime\/ffmpeg\/[^/]+\.exe$/i.test(relative) ||
    relative==='fox-spirit/preview.png';
}
export function listDistributionFiles(root){
  root=path.resolve(root);
  if(fs.existsSync(path.join(root,'.git'))){
    const result=spawnSync('git',['ls-files','--cached','--others','--exclude-standard','-z'],{cwd:root,encoding:'utf8',windowsHide:true,maxBuffer:32*1024*1024});
    if(result.status!==0)throw new Error('Cannot enumerate the repository distribution inventory.');
    return [...new Set(result.stdout.split('\0').filter(Boolean))].map(relative=>{
      const full=path.resolve(root,relative);
      if(!full.startsWith(root+path.sep))throw new Error('Distribution path escapes the repository.');
      return full;
    });
  }
  const files=[];
  function visit(directory){
    for(const entry of fs.readdirSync(directory,{withFileTypes:true})){
      const full=path.join(directory,entry.name),relative=path.relative(root,full).replaceAll('\\','/');
      if(isLocalOnly(relative))continue;
      if(entry.isDirectory()&&!entry.isSymbolicLink())visit(full);else files.push(full);
    }
  }
  visit(root);return files;
}
