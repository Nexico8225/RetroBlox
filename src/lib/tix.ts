/* ------------------------------------------------------------------
   TIX — the RetroBlox currency (display layer).
   Internally the wallet is still `rbxBalance` / RbxPackage / /api/rbx
   (renaming those would be a data migration for zero player value) —
   everything a PLAYER sees says Tix. One formatter keeps the header
   chip, store, catalog and admin tables consistent.
------------------------------------------------------------------ */

/** "1,000,000,000" — full grouping for tables, store and admin panels. */
export function tixFull(n: number): string {
  return Math.round(n || 0).toLocaleString('en-US')
}

/** Compact for tight spots (the header chip): 999.9K / 12.3M / 1.00B.
 *  Under a million shows the exact grouped number. */
export function tixCompact(n: number): string {
  const v = Math.round(n || 0)
  const abs = Math.abs(v)
  if (abs < 1_000_000) return tixFull(v)
  if (abs < 1_000_000_000) return `${(v / 1_000_000).toFixed(abs < 10_000_000 ? 2 : 1)}M`
  return `${(v / 1_000_000_000).toFixed(2)}B`
}

/** The currency short symbol used next to prices ("T$ 25"). */
export const TIX_SYMBOL = 'T$'

/* ------------------------------------------------------------------
   TIX PILE ICONS — the user-uploaded 3D pile renders, smallest to
   biggest. Any wallet amount maps to the pile that "matches" its
   size: store tiers, hero art, success pages and floaters all use
   the same ladder so the currency feels consistent everywhere.
------------------------------------------------------------------ */

export const TIX_PILES = {
  1: '/tix/tix-pile-1.png',
  2: '/tix/tix-pile-2.png',
  3: '/tix/tix-pile-3.png',
  4: '/tix/tix-pile-4.png',
  5: '/tix/tix-pile-5.png',
} as const

export function tixPileIcon(amount: number): string {
  if (amount >= 5000) return TIX_PILES[5]
  if (amount >= 2000) return TIX_PILES[4]
  if (amount >= 800) return TIX_PILES[3]
  if (amount >= 300) return TIX_PILES[2]
  return TIX_PILES[1]
}
