import { supabase } from './supabase'
import { qarToMinor } from './money'

export type CartLine = {
  product_id: string
  quantity: number
  unit_price_qar: number
}

export type PaymentLine = {
  method: 'cash' | 'card' | 'bank_transfer' | 'other'
  amount_qar: number
}

export async function checkout(input: {
  branch_id: string
  customer_id?: string | null
  discount_qar: number
  cart: CartLine[]
  payments: PaymentLine[]
}) {
  const items = input.cart.map((x) => ({
    product_id: x.product_id,
    quantity: x.quantity,
    unit_price_minor: qarToMinor(x.unit_price_qar),
  }))

  const payments = input.payments.map((x) => ({
    method: x.method,
    amount_minor: qarToMinor(x.amount_qar),
  }))

  const { data, error } = await supabase.rpc('checkout_sale', {
    p_branch_id: input.branch_id,
    p_customer_id: input.customer_id ?? null,
    p_discount_minor: qarToMinor(input.discount_qar),
    p_items: items,
    p_payments: payments,
  })

  if (error) throw error
  return data
}
