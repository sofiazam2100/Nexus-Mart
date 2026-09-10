export type Role = 'owner' | 'manager' | 'cashier' | 'accountant' | 'inventory'

export type PaymentMethod = 'cash' | 'card' | 'bank_transfer' | 'other'

export type Product = {
  id: string
  branch_id: string | null
  organization_id: string
  sku: string | null
  barcode: string | null
  name_en: string
  name_ar: string
  name_bn: string
  cost_minor: number
  selling_minor: number
  stock_qty: number
  reorder_level: number
  active: boolean
}
