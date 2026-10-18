// RetroBlox SDK — RetroBloxSaveData.cs
// Per-player game saves through the platform. No servers to rent, no
// files to manage: every save is scoped to (game, player, key) and
// only the signed-in player can touch their own data.

using System;
using System.Collections;
using UnityEngine.Networking;

namespace RetroBlox
{
    public static class RetroBloxSaveData
    {
        /// <summary>Read a save slot for the current player.</summary>
        public static IEnumerator Get(string key, Action<string> onDone, Action<string> onError = null)
        {
            string gameId = RetroBloxSettings.GameId;
            if (string.IsNullOrEmpty(gameId))
            {
                onError?.Invoke("RetroBloxSettings.GameId is not set — add your game's id in the inspector.");
                yield break;
            }

            string value = null;
            string error = null;
            yield return RetroBloxClient.Get($"/api/gamedata/{gameId}/{UnityWebRequest.EscapeURL(key)}",
                json =>
                {
                    var res = JsonUtility.FromJson<SaveEnvelope>(json);
                    value = res?.value;
                },
                msg => error = msg);

            if (error != null) onError?.Invoke(error);
            else onDone?.Invoke(value);
        }

        /// <summary>Write a save slot for the current player (any JSON string).</summary>
        public static IEnumerator Set(string key, string jsonValue, Action onDone = null, Action<string> onError = null)
        {
            string gameId = RetroBloxSettings.GameId;
            if (string.IsNullOrEmpty(gameId))
            {
                onError?.Invoke("RetroBloxSettings.GameId is not set.");
                yield break;
            }

            string error = null;
            string body = "{\"value\":" + (jsonValue ?? "null") + "}";
            yield return RetroBloxClient.Put($"/api/gamedata/{gameId}/{UnityWebRequest.EscapeURL(key)}", body,
                _ => { }, msg => error = msg);

            if (error != null) onError?.Invoke(error);
            else onDone?.Invoke();
        }

        [Serializable]
        private class SaveEnvelope { public string key; public string value; }
    }
}
