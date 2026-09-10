export const config = {
  supabaseUrl: import.meta.env.VITE_SUPABASE_URL as string,
  supabasePublishableKey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string,
  appName: import.meta.env.VITE_APP_NAME || 'NexusMart',
  timezone: import.meta.env.VITE_APP_TIMEZONE || 'Asia/Qatar',
}
export function assertClientConfig(){
  if(!config.supabaseUrl || !config.supabasePublishableKey){
    throw new Error('NexusMart is not configured. Add VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY.')
  }
}
