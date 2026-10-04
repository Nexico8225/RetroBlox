'use client'

/* DeleteConfirmFullScreen — the screen-filling "are you REALLY sure" gate.
   Deletes are PERMANENT (remove = delete = true), so the confirm takes over
   the whole screen on purpose: nothing else to click, no accidental Enter
   through a tiny dialog. Retro skin: white card on the flat page color,
   chunky border, one red action button — every other pixel stays calm. */

export interface DeleteTarget {
  id: string
  name: string
  imageFileId: string
  assetId?: string
  type?: string
}

export default function DeleteConfirmFullScreen({
  target,
  busy,
  onDelete,
  onCancel,
}: {
  target: DeleteTarget
  busy: boolean
  onDelete: () => void
  onCancel: () => void
}) {
  return (
    <div
      style={{
        position: 'fixed', inset: 0, zIndex: 120,
        background: '#e6eaf0',
        display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 16,
        overflowY: 'auto',
      }}
      role="alertdialog"
      aria-modal="true"
      aria-label={`Permanently delete ${target.name}`}
    >
      <div className="rb-box" style={{ width: 'min(520px, 100%)', padding: 0, overflow: 'hidden' }}>
        <div className="rb-panel-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span>Delete this UGC — forever?</span>
        </div>

        <div style={{ padding: 16 }}>
          {/* the thing about to be gone — its real thumbnail, big */}
          <div style={{ display: 'flex', gap: 14, alignItems: 'center', marginBottom: 14 }}>
            <div
              style={{
                width: 96, height: 96, flexShrink: 0, border: '1px solid #b7c6d4', background: '#fff',
                display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden',
              }}
            >
              <img
                src={`/api/files/${target.imageFileId}`}
                alt={target.name}
                style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain', display: 'block' }}
              />
            </div>
            <div style={{ minWidth: 0 }}>
              <div style={{ fontSize: 16, color: '#1c2733', overflowWrap: 'anywhere' }}>{target.name}</div>
              {target.assetId && (
                <div style={{ fontSize: 10, fontFamily: 'monospace', color: '#9aa7b4', marginTop: 3 }}>
                  {target.assetId}
                  {target.type ? ` · ${target.type}` : ''}
                </div>
              )}
            </div>
          </div>

          <div
            style={{
              border: '1px solid #d9b1ad', background: '#fdf3f2', padding: '10px 12px', marginBottom: 14,
              fontSize: 12, color: '#7c2d26', lineHeight: 1.55,
            }}
          >
            This deletes the item and every copy in every inventory <b>permanently</b>. There is no
            recycle bin and no restore — nobody can bring it back, not even an admin. If you just
            want it out of the store, this is still the right button.
          </div>

          <div style={{ display: 'flex', gap: 8 }}>
            <button
              className="rb-btn rb-btn-red"
              style={{ fontSize: 12, padding: '8px 16px', flex: 1 }}
              disabled={busy}
              onClick={onDelete}
            >
              {busy ? 'Deleting...' : 'Delete forever'}
            </button>
            <button className="rb-btn" style={{ fontSize: 12, padding: '8px 16px' }} disabled={busy} onClick={onCancel}>
              Keep it
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
