'use client'

/* TradeModal — build and send a trade offer from an item page.
   LEFT: what YOU give (pick from your inventory + optional Tix).
   RIGHT: what you WANT (the item you opened the modal from, pre-picked —
   you can add more of their items via their profile later).
   Sending is free: trades cost nothing to offer, declining costs nothing. */

import { useEffect, useMemo, useState } from 'react'
import { api, flash, useRetro } from '@/lib/store'

interface InvItem {
  itemId: string
  assetId: string
  name: string
  type: string
  imageFileId: string
  modelFileId: string | null
}

export interface TradeTargetItem {
  id: string
  name: string
  imageFileId: string
}

export default function TradeModal({
  target,
  targetOwnerId,
  onClose,
  onSent,
}: {
  /** the item the trade is ABOUT (pre-picked as what you want) */
  target: TradeTargetItem
  /** the owner of that item — the trade recipient */
  targetOwnerId: string
  onClose: () => void
  onSent: () => void
}) {
  const { setToast } = useRetro()
  const [inv, setInv] = useState<InvItem[]>([])
  const [picked, setPicked] = useState<string[]>([])
  const [tix, setTix] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [balance, setBalance] = useState(0)

  useEffect(() => {
    let alive = true
    ;(async () => {
      try {
        const res = await api<{ inventory: InvItem[]; user?: { rbxBalance?: number } }>('/api/me/avatar')
        if (!alive) return
        // every UGC item this account owns (a trade gives away COPIES)
        setInv(res.inventory || [])
        setBalance(typeof res.user?.rbxBalance === 'number' ? res.user.rbxBalance : 0)
      } catch {
        if (alive) setError('Could not load your inventory.')
      } finally {
        if (alive) setLoading(false)
      }
    })()
    return () => { alive = false }
  }, [])

  const tixNum = Math.max(0, Math.floor(Number(tix) || 0))
  const canSend = useMemo(
    () => !loading && !busy && (picked.length > 0 || tixNum > 0),
    [loading, busy, picked, tixNum]
  )

  function togglePick(id: string) {
    setPicked((p) => (p.includes(id) ? p.filter((x) => x !== id) : p.length >= 8 ? p : [...p, id]))
  }

  async function send() {
    setError('')
    if (tixNum > balance) {
      setError(`You only have T$ ${balance.toLocaleString('en-US')} in your wallet.`)
      return
    }
    setBusy(true)
    try {
      await api('/api/trades', {
        method: 'POST',
        body: JSON.stringify({
          toUserId: targetOwnerId,
          giveItemIds: picked,
          takeItemIds: [target.id],
          tix: tixNum,
          message: message.trim(),
        }),
      })
      flash(setToast, 'Trade offer sent!')
      onSent()
      onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The trade could not be sent.')
      setBusy(false)
    }
  }

  return (
    <div
      style={{
        position: 'fixed', inset: 0, zIndex: 95, background: 'rgba(20,32,44,0.72)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 14,
      }}
      role="dialog"
      aria-modal="true"
      aria-label={`Trade for ${target.name}`}
      onClick={(e) => { if (e.target === e.currentTarget) onClose() }}
    >
      <div className="rb-box" style={{ width: 'min(680px, 100%)', background: '#fff', maxHeight: '90vh', display: 'flex', flexDirection: 'column' }}>
        <div className="rb-panel-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span>Trade for: {target.name}</span>
          <button className="rb-btn" style={{ fontSize: 10, padding: '2px 8px' }} onClick={onClose}>✕</button>
        </div>
        <div style={{ padding: 12, overflowY: 'auto' }}>
          {/* what you want */}
          <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 6 }}>You want</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: 8, border: '1px solid #cfe0ee', background: '#f2f8fd', marginBottom: 12 }}>
            <img src={`/api/files/${target.imageFileId}`} alt={target.name} style={{ width: 44, height: 44, objectFit: 'cover', border: '1px solid #b7c6d4', background: '#fff' }} />
            <div style={{ fontSize: 12, color: '#1c2733' }}>{target.name}</div>
          </div>

          {/* what you give */}
          <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 6 }}>
            You give {picked.length > 0 && <span style={{ color: '#8ba0b3' }}>({picked.length}/8 picked)</span>}
          </div>
          {loading ? (
            <div style={{ fontSize: 11, color: '#5a6b7b', padding: '8px 0' }}>Loading your inventory...</div>
          ) : inv.length === 0 ? (
            <div style={{ fontSize: 11, color: '#5a6b7b', padding: '8px 0' }}>
              Your inventory is empty — grab something free from the Catalog first, or offer Tix below.
            </div>
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(86px, 1fr))', gap: 6, marginBottom: 12, maxHeight: 220, overflowY: 'auto' }}>
              {inv.map((it) => {
                const on = picked.includes(it.itemId)
                return (
                  <button
                    key={it.itemId}
                    type="button"
                    onClick={() => togglePick(it.itemId)}
                    aria-pressed={on}
                    title={it.name}
                    style={{
                      border: on ? '2px solid #2e9e3e' : '1px solid #b7c6d4',
                      background: '#fff', padding: 0, cursor: 'pointer', position: 'relative',
                      boxShadow: on ? '0 0 0 2px rgba(46,158,62,0.25)' : 'none',
                    }}
                  >
                    <img src={`/api/files/${it.imageFileId}`} alt={it.name} style={{ width: '100%', aspectRatio: '1', objectFit: 'cover', display: 'block', background: '#fff' }} />
                    {on && (
                      <span style={{ position: 'absolute', top: 2, right: 2, fontSize: 9, background: '#2e9e3e', color: '#fff', padding: '0 4px', borderRadius: 2 }}>✓</span>
                    )}
                  </button>
                )
              })}
            </div>
          )}

          {/* tix + message */}
          <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', alignItems: 'center', marginBottom: 8 }}>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11, color: '#1c4e7c' }}>
              Plus Tix:
              <input
                className="rb-input"
                type="number"
                min={0}
                max={balance}
                value={tix}
                onChange={(e) => setTix(e.target.value)}
                placeholder="0"
                style={{ width: 90, fontSize: 12 }}
                aria-label="Tix offered with the trade"
              />
              <span style={{ fontSize: 10, color: '#8ba0b3' }}>wallet: T$ {balance.toLocaleString('en-US')}</span>
            </label>
          </div>
          <input
            className="rb-input"
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            maxLength={300}
            placeholder="Add a note (optional) — why they should take this deal"
            style={{ width: '100%', fontSize: 12, marginBottom: 8 }}
            aria-label="Trade message"
          />

          {error && <div style={{ fontSize: 11, color: '#a81a13', marginBottom: 8 }}>{error}</div>}

          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <button className="rb-btn rb-btn-blue" style={{ fontSize: 12, padding: '7px 18px' }} disabled={!canSend} onClick={send}>
              {busy ? 'Sending...' : 'Send trade offer'}
            </button>
            <span style={{ fontSize: 10, color: '#8ba0b3' }}>Free to offer — they accept or decline, nothing moves until they accept.</span>
          </div>
        </div>
      </div>
    </div>
  )
}
