export type Locale = 'en' | 'bn' | 'ar'
export const copy = {
  en: { dashboard:'Dashboard', pos:'POS', inventory:'Inventory', purchases:'Purchases', customers:'Customers', suppliers:'Suppliers', returns:'Returns', cash:'Cash Register', reports:'Reports', audit:'Audit Log', settings:'Settings', signOut:'Sign out', qatar:'QATAR BUSINESS CONTROL' },
  bn: { dashboard:'ড্যাশবোর্ড', pos:'বিক্রয়', inventory:'স্টক', purchases:'ক্রয়', customers:'কাস্টমার', suppliers:'সাপ্লায়ার', returns:'রিটার্ন', cash:'ক্যাশ রেজিস্টার', reports:'রিপোর্ট', audit:'অডিট লগ', settings:'সেটিংস', signOut:'সাইন আউট', qatar:'কাতার বিজনেস কন্ট্রোল' },
  ar: { dashboard:'لوحة التحكم', pos:'نقطة البيع', inventory:'المخزون', purchases:'المشتريات', customers:'العملاء', suppliers:'الموردون', returns:'المرتجعات', cash:'الصندوق', reports:'التقارير', audit:'سجل التدقيق', settings:'الإعدادات', signOut:'تسجيل الخروج', qatar:'إدارة الأعمال في قطر' },
} as const
export function t(locale: Locale, key: keyof typeof copy.en){ return copy[locale][key] }

export const languageNames: Record<Locale,string> = { en:'English', bn:'বাংলা', ar:'العربية' }
