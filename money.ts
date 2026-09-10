export const QAR_MINOR = 100

export function qarToMinor(value: number): number {
  if (!Number.isFinite(value) || value < 0) throw new Error('Invalid amount')
  return Math.round(value * QAR_MINOR)
}

export function minorToQar(value: number): number {
  return value / QAR_MINOR
}

export function formatQarMinor(value: number, locale = 'en-QA'): string {
  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: 'QAR',
    minimumFractionDigits: 2,
  }).format(minorToQar(value))
}
