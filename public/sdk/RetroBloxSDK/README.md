# RetroBlox Unity SDK

One SDK for every RetroBlox game. Games log players in, load their
account-wide RetroBlox avatar, download/cache assets, spawn the player
and save progress — all through the RetroBlox platform API. A game never
touches a database, never sees credentials, and never rebuilds this
system per game.

```
                 RetroBlox Platform
                        |
             +----------+----------+
             |                     |
        RetroBlox API        Asset Service
   (/api/platform/*)      (/api/assets/{id})
             |                     |
             +----------+----------+
                        |
                 Unity RetroBlox SDK
                        |
          +-------------+-------------+
          |             |             |
       Game 1        Game 2        Game 3
```

## Install

1. Copy the `RetroBloxSDK` folder anywhere into `Assets/`.
2. Set the site URL once at startup (e.g. a bootstrap scene):
   ```csharp
   RetroBloxSettings.ServerUrl = "https://your-retroblox-site.example";
   RetroBloxSettings.GameId   = "your-game-id"; // for save data
   ```

## Quick start

```csharp
using RetroBlox;
using System.Collections;
using UnityEngine;

public class RetroBloxBootstrap : MonoBehaviour
{
    IEnumerator Start()
    {
        // 1. sign the player in (their RetroBlox account — one login everywhere)
        yield return RetroBloxAuth.SignIn("Nexico", "their-password",
            onError: e => Debug.LogError(e));

        // 2. spawn the local player wearing THEIR avatar, automatically
        RetroBloxPlayer.SpawnLocalPlayer();

        // 3. (optional) react to hooks
        RetroBloxEvents.PlayerSpawned += player => Debug.Log("player is in the world!");

        // 4. (optional) save progress through the platform
        yield return RetroBloxSaveData.Set("checkpoint", "{\"level\":3}");
    }
}
```

What `SpawnLocalPlayer()` does for you:

1. Gets the authenticated RetroBlox user id.
2. Requests that user's avatar from the RetroBlox API.
3. Resolves every asset id (`body_01`, `hat_15`...) through the asset service.
4. Downloads required images and caches them under `persistentDataPath`.
5. Builds the classic R6 player model from cubes + textured quads.
6. Spawns the player into the scene.

## The R6 player model + UGC placement

The player model is the classic **R6 rig** — this SDK ships the real
rigged model: `Models/R6IK.fbx` (Head, Torso, 2 Arms, 2 Legs + IK bones).

**UGC placement is SACRED.** Every accessory is rendered EXACTLY where
its creator painted it on the official template — the SDK never moves,
scales or stacks items:

| UGC type | Where it lands |
|---|---|
| `hat_*`, `gear_*` | one 1.6-unit quad per item centred on the head, 1:1 with `hat-template.png` / `gear-template.png` |
| `tshirt_*` | quad centred on the torso front, 1:1 with `tshirt-template.png` |
| `face_*` | the head front itself (`face-template.png` = the head canvas) |
| `shirt_*` | the 300x190 shirt template **zone-cropped** onto torso + both arms |
| `pants_*` | the 220x190 pants template **zone-cropped** onto both legs |

Multiple hats overlap on the head slot by design — the creator placed
them; the platform does not second-guess them.

### Using the rigged R6IK model instead of the auto-built blockhead

Drop the `R6IK` prefab into your scene and hand it to the rig binder:

```csharp
using RetroBlox;

// fetches the avatar and applies it to the rig's parts by name
// (Head, Torso, Left Arm, Right Arm, Left Leg, Right Leg —
//  case/space insensitive), plus face, clothing and UGC quads
RetroBloxRig.Apply(rigGameObject, RetroBloxAuth.Current.UserId);

RetroBloxRig.OnRigApplied += rig => Debug.Log($"{rig.name} is wearing their RetroBlox look");
```

Prefer not to use the prefab? `RetroBloxPlayer.SpawnLocalPlayer()` builds
the same R6 proportions out of cubes and works with zero scene setup.

## API surface

| Class | What it gives you |
|---|---|
| `RetroBloxAuth` | `SignIn(username, password)`, `SignOut()`, `Current` account |
| `RetroBloxAvatar` | `FetchMine()` / `Fetch(userId)` — avatar as asset ids |
| `RetroBloxAssets` | `Resolve(assetId)` + `DownloadTexture(url)` with disk cache |
| `RetroBloxPlayer` | `SpawnLocalPlayer()`, `SpawnRemotePlayer(userId, pos)` |
| `RetroBloxRig` | `Apply(rig, userId)` — dress the shipped R6IK.fbx model |
| `RetroBloxSaveData` | `Get(key)` / `Set(key, json)` per-player saves |
| `RetroBloxEvents` | `PlayerSpawned`, `SignedIn`, `PlatformError` hooks |
| `RetroBloxClient` | raw `Get/Post/Put` against the platform API |

## Platform endpoints used

| Endpoint | Purpose |
|---|---|
| `POST /api/platform/login` | username + password -> session token |
| `GET /api/platform/me` | current user + avatar (Bearer token) |
| `GET /api/users/{userId}/avatar` | public avatar config |
| `GET /api/assets/{assetId}` | asset service (color or image) |
| `GET/PUT /api/gamedata/{gameId}/{key}` | per-player game saves |

**Security model:** `Unity Game -> RetroBlox API -> Database`. The API
validates the session token before returning anything; the database and
its credentials never leave the server.

## Roadmap (already designed for)

Friends, Inventory, Achievements, Currency, Marketplace, Player Stats,
Multiplayer and Game Permissions all plug into the same platform API +
SDK pattern — new features land in the SDK, and every game gets them
for free.
