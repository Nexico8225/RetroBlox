// RetroBlox SDK — RetroBloxAvatar.cs
// The account-wide avatar. One call fetches the signed-in player's
// look (or any RetroBlox user's) as ASSET IDS — the same config the
// website's Avatar Editor saves. Change your avatar on the website,
// every game sees it next time you press play.

using System;
using System.Collections;

namespace RetroBlox
{
    [Serializable]
    public class AvatarConfig
    {
        public string body;         // "body_01"
        public string head;         // "head_03"
        public string shirt;        // "shirt_22"
        public string pants;        // "pants_08"
        public string accessories;  // JSON array string: ["hat_15","glasses_04"]
        public AvatarPartColors colors; // optional per-part Body Colors (nullable)
        public float? faceScale;    // face size multiplier from the website editor (null/1 = classic)

        /// The face decal multiplier, clamped to the same 0.5..2 range the site enforces.
        public float FaceScale => Mathf.Clamp(faceScale ?? 1f, 0.5f, 2f);
    }

    /// <summary>Advanced per-part colors from the website's Body Colors editor.
    /// Any field the website left unset comes through as null — keep the classic
    /// color for that part. Matches "colors" in the platform avatar payload.</summary>
    [Serializable]
    public class AvatarPartColors
    {
        public string head;   // "#RRGGBB" or null
        public string torso;
        public string armL;
        public string armR;
        public string legL;
        public string legR;
    }

    [Serializable]
    internal class AvatarResponse
    {
        public string userId;
        public string username;
        public AvatarConfig avatar;
    }

    public static class RetroBloxAvatar
    {
        /// <summary>Fetch the CURRENT PLAYER's avatar (requires sign-in).</summary>
        public static IEnumerator FetchMine(Action<AvatarConfig> onDone, Action<string> onError = null) =>
            Fetch(null, onDone, onError);

        /// <summary>Fetch any RetroBlox user's avatar by userId (public API).</summary>
        public static IEnumerator Fetch(string userId, Action<AvatarConfig> onDone, Action<string> onError = null)
        {
            string path = userId == null ? "/api/platform/me" : $"/api/users/{userId}/avatar";
            AvatarConfig result = null;
            string error = null;

            yield return RetroBloxClient.Get(path,
                json =>
                {
                    var res = JsonUtility.FromJson<AvatarResponse>(json);
                    if (res?.avatar == null) { error = "Avatar response was empty"; return; }
                    result = res.avatar;
                },
                msg => error = msg);

            if (error != null) onError?.Invoke(error);
            else onDone?.Invoke(result);
        }
    }
}
