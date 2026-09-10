const KEY='nexusmart-v5-offline-intent-queue'
export type OfflineIntent={id:string;createdAt:string;type:'sale'|'other';payload:unknown}
export function getOfflineQueue():OfflineIntent[]{ try{return JSON.parse(localStorage.getItem(KEY)||'[]')}catch{return[]} }
export function enqueueOfflineIntent(intent:Omit<OfflineIntent,'id'|'createdAt'>){ const next={...intent,id:crypto.randomUUID(),createdAt:new Date().toISOString()}; localStorage.setItem(KEY,JSON.stringify([...getOfflineQueue(),next])); return next }
export function clearOfflineQueue(){localStorage.removeItem(KEY)}
