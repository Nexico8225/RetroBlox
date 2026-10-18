// RetroBlox SDK — RetroBloxClient.cs
// The single HTTP door to the RetroBlox platform. Every feature
// (auth, avatars, assets, saves) goes through here: JSON in, JSON
// out, Bearer token attached automatically. Nothing else in your
// game talks to the network, and NOTHING ever touches a database —
// the RetroBlox API is the only middleman.

using System;
using System.Collections;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;

namespace RetroBlox
{
    public static class RetroBloxClient
    {
        public static string Token
        {
            get => PlayerPrefs.GetString(RetroBloxSettings.TokenKey, "");
            set => PlayerPrefs.SetString(RetroBloxSettings.TokenKey, value ?? "");
        }

        public static bool IsSignedIn => !string.IsNullOrEmpty(Token);

        public static event Action<string> OnError;

        // ------------------------------------------------ generic request

        public static IEnumerator Get(string path, Action<string> onSuccess, Action<string> onError = null) =>
            Send(path, "GET", null, onSuccess, onError);

        public static IEnumerator Post(string path, string jsonBody, Action<string> onSuccess, Action<string> onError = null) =>
            Send(path, "POST", jsonBody, onSuccess, onError);

        public static IEnumerator Put(string path, string jsonBody, Action<string> onSuccess, Action<string> onError = null) =>
            Send(path, "PUT", jsonBody, onSuccess, onError);

        public static IEnumerator Send(string path, string method, string jsonBody, Action<string> onSuccess, Action<string> onError)
        {
            using (var req = new UnityWebRequest($"{RetroBloxSettings.ServerUrl}{path}", method))
            {
                req.downloadHandler = new DownloadHandlerBuffer();
                if (!string.IsNullOrEmpty(jsonBody))
                {
                    req.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(jsonBody));
                    req.SetRequestHeader("Content-Type", "application/json");
                }
                if (IsSignedIn) req.SetRequestHeader("Authorization", $"Bearer {Token}");

                yield return req.SendWebRequest();

                if (req.result != UnityWebRequest.Result.Success)
                {
                    string message = $"RetroBlox API {method} {path} failed: {req.error} {req.downloadHandler.text}";
                    onError?.Invoke(message);
                    OnError?.Invoke(message);
                    yield break;
                }
                onSuccess?.Invoke(req.downloadHandler.text);
            }
        }

        /// <summary>Bootstrap a quiet coroutine runner so games can call the SDK from anywhere.</summary>
        public static Coroutine Run(IEnumerator routine)
        {
            var runner = new GameObject("RetroBloxRunner");
            UnityEngine.Object.DontDestroyOnLoad(runner);
            return runner.AddComponent<RetroBloxRunner>().StartCoroutine(routine);
        }
    }

    internal class RetroBloxRunner : MonoBehaviour { }
}
