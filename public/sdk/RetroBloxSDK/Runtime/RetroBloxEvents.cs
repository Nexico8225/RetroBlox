// RetroBlox SDK — RetroBloxEvents.cs
// Networking + platform hooks your game can subscribe to. Today the
// SDK covers auth, avatar, assets and saves; these events are the
// seams where Friends, Inventory, Achievements, Currency, Marketplace,
// Player Stats, Multiplayer and Game Permissions plug in later —
// without rewriting a single game.

using System;
using UnityEngine;

namespace RetroBlox
{
    public static class RetroBloxEvents
    {
        /// <summary>Player just spawned wearing their RetroBlox avatar.</summary>
        public static event Action<GameObject> PlayerSpawned
        {
            add => RetroBloxPlayer.OnLocalPlayerSpawned += value;
            remove => RetroBloxPlayer.OnLocalPlayerSpawned -= value;
        }

        /// <summary>Sign-in flow finished (account or error).</summary>
        public static event Action<RetroBloxAccount> SignedIn
        {
            add => RetroBloxAuth.OnSignedIn += value;
            remove => RetroBloxAuth.OnSignedIn -= value;
        }

        /// <summary>Any platform request failed (offline, token expired...).</summary>
        public static event Action<string> PlatformError
        {
            add => RetroBloxClient.OnError += value;
            remove => RetroBloxClient.OnError -= value;
        }
    }
}
