/* ------------------------------------------------------------------
   RETROBLOX STEAM-STYLE ACHIEVEMENTS — badge definitions + XP/levels
   Badges are site-wide achievements awarded automatically by
   evaluateBadges() from real account activity. The profile shows a
   badge showcase; XP from badges + playtime drives the player LEVEL.

   In-game events (play sessions) call evaluateBadges too, so badges
   pop while you play — the game can toast them via the heartbeat
   response's newlyUnlocked list.
------------------------------------------------------------------ */

import { db } from '@/lib/db'

export interface BadgeDef {
  id: string
  name: string
  desc: string
  xp: number
  color: string // retro badge color
  icon: string // tiny inline-SVG path drawn by the UI (shield/star/crown...)
}

/** All site badges. Adding one here = automatically obtainable + shown. */
export const BADGES: BadgeDef[] = [
  { id: 'welcome',      name: 'Welcome Aboard',   desc: 'Join RetroBlox',                                        xp: 10,  color: '#4a90d9', icon: 'flag' },
  { id: 'first_play',   name: 'Press Start',      desc: 'Play a game for the first time',                        xp: 15,  color: '#5cb85c', icon: 'play' },
  { id: 'gamer_5',      name: 'Explorer',         desc: 'Play 5 different games',                                xp: 30,  color: '#5cb85c', icon: 'compass' },
  { id: 'gamer_15',     name: 'Game Hopper',      desc: 'Play 15 different games',                               xp: 75,  color: '#f0ad4e', icon: 'compass' },
  { id: 'time_1h',      name: 'Warmed Up',        desc: 'Play for 1 hour total',                                 xp: 20,  color: '#9b59b6', icon: 'clock' },
  { id: 'time_10h',     name: 'Dedicated',        desc: 'Play for 10 hours total',                               xp: 100, color: '#9b59b6', icon: 'clock' },
  { id: 'time_50h',     name: 'No-Life Club',     desc: 'Play for 50 hours total',                               xp: 300, color: '#e05c5c', icon: 'clock' },
  { id: 'creator',      name: 'Builder',          desc: 'Publish your first game',                               xp: 50,  color: '#f0ad4e', icon: 'hammer' },
  { id: 'creator_5',    name: 'Studio Owner',     desc: 'Publish 5 games',                                       xp: 150, color: '#f0ad4e', icon: 'hammer' },
  { id: 'ugc_creator',  name: 'Designer',         desc: 'Publish your first UGC item',                           xp: 50,  color: '#4aa3df', icon: 'shirt' },
  { id: 'shopper',      name: 'First Purchase',   desc: 'Buy something from the Catalog',                        xp: 15,  color: '#f5c542', icon: 'cart' },
  { id: 'collector_10', name: 'Collector',        desc: 'Own 10 catalog items',                                  xp: 60,  color: '#f5c542', icon: 'chest' },
  { id: 'social',       name: 'Friendly Face',    desc: 'Make your first friend',                                xp: 15,  color: '#e0709b', icon: 'friends' },
  { id: 'socializer',   name: 'Socializer',       desc: 'Post in RetroLabs',                                     xp: 15,  color: '#e0709b', icon: 'chat' },
  { id: 'veteran',      name: 'Veteran',          desc: 'Be a member for 30 days',                               xp: 40,  color: '#8a9bb0', icon: 'shield' },
]

export const BADGE_MAP: Record<string, BadgeDef> = Object.fromEntries(BADGES.map((b) => [b.id, b]))

/* ---------------- XP + LEVEL ----------------
   Level curve: level n needs 100 * n^2 XP total (1→100, 2→400, 3→900...)
   XP sources: badges (big chunks) + 1 XP per minute played + small stuff. */

export function levelForXp(xp: number) {
  let level = 0
  while (100 * (level + 1) * (level + 1) <= xp) level++
  const currentFloor = 100 * level * level
  const nextFloor = 100 * (level + 1) * (level + 1)
  return {
    level,
    xpIntoLevel: xp - currentFloor,
    xpForNextLevel: nextFloor - currentFloor,
    progressPct: Math.min(100, Math.round(((xp - currentFloor) / (nextFloor - currentFloor)) * 100)),
  }
}

/* ---------------- evaluation ---------------- */

interface BadgeProgress {
  welcome: true
  first_play: number // distinct games played
  gamer_5: number
  gamer_15: number
  time_1h: number // total seconds
  time_10h: number
  time_50h: number
  creator: number // games published
  creator_5: number
  ugc_creator: number // UGC items published
  shopper: number // purchases (inventory entries that came from the catalog)
  collector_10: number
  social: number // accepted friendships
  socializer: number // lab posts + community posts
  veteran: number // account age in days
}

async function collectProgress(userId: string): Promise<BadgeProgress> {
  const [distinctGames, totalSeconds, gamesCreated, ugcPublished, purchases, owned, friends, labPosts, communityPosts, user] =
    await Promise.all([
      db.gamePlay.count({ where: { userId } }),
      db.gamePlay.aggregate({ where: { userId }, _sum: { seconds: true } }),
      db.game.count({ where: { creatorId: userId } }),
      db.avatarItem.count({ where: { creatorId: userId, deletedAt: null } }),
      db.inventoryEntry.count({ where: { userId } }),
      db.inventoryEntry.count({ where: { userId } }),
      db.friendship.count({ where: { status: 'accepted', OR: [{ requesterId: userId }, { addresseeId: userId }] } }),
      db.labPost.count({ where: { authorId: userId } }),
      db.communityPost.count({ where: { authorId: userId } }),
      db.user.findUnique({ where: { id: userId }, select: { createdAt: true } }),
    ])

  const days = user ? Math.floor((Date.now() - new Date(user.createdAt).getTime()) / 86400000) : 0
  return {
    welcome: true,
    first_play: distinctGames,
    gamer_5: distinctGames,
    gamer_15: distinctGames,
    time_1h: totalSeconds._sum.seconds || 0,
    time_10h: totalSeconds._sum.seconds || 0,
    time_50h: totalSeconds._sum.seconds || 0,
    creator: gamesCreated,
    creator_5: gamesCreated,
    ugc_creator: ugcPublished,
    shopper: purchases,
    collector_10: owned,
    social: friends,
    socializer: labPosts + communityPosts,
    veteran: days,
  }
}

const THRESHOLDS: Record<string, (p: BadgeProgress) => boolean> = {
  welcome: () => true,
  first_play: (p) => p.first_play >= 1,
  gamer_5: (p) => p.gamer_5 >= 5,
  gamer_15: (p) => p.gamer_15 >= 15,
  time_1h: (p) => p.time_1h >= 3600,
  time_10h: (p) => p.time_10h >= 36000,
  time_50h: (p) => p.time_50h >= 180000,
  creator: (p) => p.creator >= 1,
  creator_5: (p) => p.creator_5 >= 5,
  ugc_creator: (p) => p.ugc_creator >= 1,
  shopper: (p) => p.shopper >= 1,
  collector_10: (p) => p.collector_10 >= 10,
  social: (p) => p.social >= 1,
  socializer: (p) => p.socializer >= 1,
  veteran: (p) => p.veteran >= 30,
}

/**
 * Check every badge's condition for a user and award the missing ones.
 * Returns the defs unlocked BY THIS CALL (empty if nothing new) so
 * callers can toast them ("Achievement unlocked!").
 * Cheap enough to run on every playtime heartbeat + profile view.
 */
export async function evaluateBadges(userId: string): Promise<BadgeDef[]> {
  const progress = await collectProgress(userId)
  const owned = await db.playerBadge.findMany({ where: { userId }, select: { badgeId: true } })
  const ownedSet = new Set(owned.map((o) => o.badgeId))

  const newly: BadgeDef[] = []
  for (const def of BADGES) {
    if (ownedSet.has(def.id)) continue
    if (THRESHOLDS[def.id]?.(progress)) {
      await db.playerBadge.create({ data: { userId, badgeId: def.id } }).catch(() => null)
      newly.push(def)
    }
  }
  return newly
}
