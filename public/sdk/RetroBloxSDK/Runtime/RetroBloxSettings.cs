// RetroBlox SDK — RetroBloxSettings.cs
// One place to point the SDK at your RetroBlox site. Games never
// hardcode URLs, tokens or database info — they just use the SDK.

namespace RetroBlox
{
    public static class RetroBloxSettings
    {
        /// <summary>Root URL of the RetroBlox site (no trailing slash).</summary>
        public static string ServerUrl = "https://retroblox.example";

        /// <summary>PlayerPrefs key the session token is stored under.</summary>
        public const string TokenKey = "retroblox_token";

        /// <summary>Optional: a game id for the save-data API. Set per game.</summary>
        public static string GameId = "";
    }
}
