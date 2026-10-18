// RetroBlox SDK — RetroBloxAssets.cs
// The asset service client with LOCAL CACHING. Asset IDs ("hat_15")
// resolve to a color or an image through the RetroBlox API, and the
// downloaded image is stored under Application.persistentDataPath so
// the same asset is never downloaded twice.

using System;
using System.Collections;
using System.IO;
using UnityEngine;
using UnityEngine.Networking;

namespace RetroBlox
{
    [Serializable]
    public class AssetInfo
    {
        public string assetId;   // "hat_15"
        public string kind;      // body | head | shirt | pants | hat | face | gear | tshirt | accessory
        public string name;
        public string color;     // "#RRGGBB" (body/shirt/pants defaults)
        public string imageUrl;  // absolute URL (faces, t-shirts, clothing, UGC thumbnails)
        public string modelUrl;  // 3D UGC only — GLB model url
        public Placement3D placement; // 3D UGC only — where the creator left it
    }

    /// <summary>
    /// Creator-authored transform for 3D UGC (hats / gear / accessories).
    /// p = position, r = rotation in DEGREES, s = scale — authored in the
    /// RetroBlox placement editor, relative to the player model standing on
    /// the ground at origin, 5 units tall, facing +Z (its front).
    /// THE SACRED RULE: apply it EXACTLY as stored — never auto-fit,
    /// never re-position, never "improve" a creator's placement.
    /// </summary>
    [Serializable]
    public class Placement3D
    {
        public float[] p = new float[3];
        public float[] r = new float[3];
        public float[] s = new float[3];

        public bool IsValid =>
            p != null && p.Length == 3 && r != null && r.Length == 3 && s != null && s.Length == 3;
    }

    [Serializable]
    internal class AssetEnvelope { public AssetInfo asset; }

    public static class RetroBloxAssets
    {
        public static string CacheDir =>
            Path.Combine(Application.persistentDataPath, "retroblox_cache");

        /// <summary>Resolve an asset id to color/image info (cached in memory).</summary>
        public static IEnumerator Resolve(string assetId, Action<AssetInfo> onDone, Action<string> onError = null)
        {
            if (memory.TryGetValue(assetId, out var hit)) { onDone?.Invoke(hit); yield break; }

            string error = null;
            AssetInfo info = null;

            yield return RetroBloxClient.Get($"/api/assets/{assetId}",
                json =>
                {
                    var env = JsonUtility.FromJson<AssetEnvelope>(json);
                    info = env?.asset;
                    if (info != null) memory[assetId] = info;
                },
                msg => error = msg);

            if (error != null) onError?.Invoke(error);
            else onDone?.Invoke(info);
        }

        /// <summary>Download an asset image ( Texture2D) with disk caching.</summary>
        public static IEnumerator DownloadTexture(string imageUrl, Action<Texture2D> onDone, Action<string> onError = null)
        {
            // cache key = stable hash of the url
            string key = Hash(imageUrl);
            string file = Path.Combine(CacheDir, key + ".png");

            if (File.Exists(file))
            {
                var cached = LoadPng(file);
                if (cached != null) { onDone?.Invoke(cached); yield break; }
            }

            using (var req = UnityWebRequestTexture.GetTexture(imageUrl))
            {
                yield return req.SendWebRequest();
                if (req.result != UnityWebRequest.Result.Success)
                {
                    onError?.Invoke($"Asset download failed: {req.error}");
                    yield break;
                }
                var tex = DownloadHandlerTexture.GetContent(req);
                Directory.CreateDirectory(CacheDir);
                File.WriteAllBytes(file, tex.EncodeToPNG());
                onDone?.Invoke(tex);
            }
        }

        /// <summary>Download raw model bytes (GLB) with disk caching — 3D UGC.</summary>
        public static IEnumerator DownloadModel(string modelUrl, Action<byte[]> onDone, Action<string> onError = null)
        {
            string key = Hash(modelUrl);
            string file = Path.Combine(CacheDir, key + ".glb");

            if (File.Exists(file))
            {
                try { onDone?.Invoke(File.ReadAllBytes(file)); yield break; }
                catch { /* fall through to re-download */ }
            }

            using (var req = UnityWebRequest.Get(modelUrl))
            {
                yield return req.SendWebRequest();
                if (req.result != UnityWebRequest.Result.Success)
                {
                    onError?.Invoke($"Model download failed: {req.error}");
                    yield break;
                }
                var bytes = req.downloadHandler.data;
                Directory.CreateDirectory(CacheDir);
                File.WriteAllBytes(file, bytes);
                onDone?.Invoke(bytes);
            }
        }

        /// <summary>Sync peek into the resolve cache (null if not resolved yet).
        /// SpawnRoutine pre-resolves every id before building the character.</summary>
        public static AssetInfo Cached(string assetId) =>
            memory.TryGetValue(assetId, out var hit) ? hit : null;

        public static Color ToColor(string hex, Color fallback)
        {
            if (string.IsNullOrEmpty(hex) || (hex.Length != 7 && hex.Length != 9) || hex[0] != '#') return fallback;
            ColorUtility.TryParseHtmlString(hex, out var c);
            return c;
        }

        // ---- internals

        private static readonly System.Collections.Generic.Dictionary<string, AssetInfo> memory
            = new System.Collections.Generic.Dictionary<string, AssetInfo>();

        private static string Hash(string s)
        {
            using (var sha = System.Security.Cryptography.SHA256.Create())
            {
                var bytes = sha.ComputeHash(System.Text.Encoding.UTF8.GetBytes(s));
                var sb = new System.Text.StringBuilder();
                foreach (var b in bytes) sb.Append(b.ToString("x2"));
                return sb.ToString().Substring(0, 32);
            }
        }

        private static Texture2D LoadPng(string file)
        {
            try
            {
                var tex = new Texture2D(2, 2);
                return tex.LoadImage(File.ReadAllBytes(file)) ? tex : null;
            }
            catch { return null; }
        }
    }
}
