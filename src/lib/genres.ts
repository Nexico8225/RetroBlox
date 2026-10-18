/**
 * GAME GENRES — the short list (v2).
 *
 * People kept scrolling a 15-genre wall, so games now ship with NINE
 * everyday genres. Legacy genres that were removed fold into their
 * closest cousin below (GENRE_FOLD) so an old "Horror" game still shows
 * up when a player browses Adventure — nothing disappears, the shelves
 * are just tidier. New uploads pick from GENRES only.
 */
export const GENRES = [
  'All Genres',
  'Adventure',
  'Building',
  'Fighting',
  'Obby',
  'Puzzle',
  'Racing',
  'RPG',
  'Tycoon',
]

// legacy genre -> the short-list genre it lives under now
export const GENRE_FOLD: Record<string, string> = {
  'FPS': 'Fighting',
  'Horror': 'Adventure',
  'Sci-Fi': 'Adventure',
  'Simulation': 'Tycoon',
  'Sports': 'Racing',
  'Town & City': 'Building',
  'Western': 'Adventure',
}

/** Every genre string that belongs on a shelf: the shelf itself + all legacy genres folded into it. */
export function genreShelf(genre: string): string[] {
  const names = [genre]
  for (const [legacy, target] of Object.entries(GENRE_FOLD)) {
    if (target === genre) names.push(legacy)
  }
  return names
}
