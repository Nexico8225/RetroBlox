// RetroBlox SDK — RetroBloxPlayer.cs
// THE one-liner every RetroBlox game uses:
//
//     using RetroBlox;
//
//     void Start()
//     {
//         RetroBloxPlayer.SpawnLocalPlayer();
//     }
//
// It automatically: gets the signed-in RetroBlox user, requests their
// account-wide avatar from the RetroBlox API, downloads the needed
// assets (cached), builds the R6 player model, and spawns it. Hook
// the events if your game wants to react (perk unlocks, respawns...).

using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace RetroBlox
{
    public static class RetroBloxPlayer
    {
        /// <summary>
        /// The spawned local player (null until OnLocalPlayerSpawned).
        /// </summary>
        public static GameObject LocalPlayer { get; private set; }

        public static event Action<GameObject> OnLocalPlayerSpawned;

        /// <summary>
        /// Wire YOUR glTF runtime here (once, at startup) to see real 3D UGC
        /// models. The SDK hands you the raw GLB bytes, you return a spawned
        /// GameObject (unparented — the SDK parents and places it).
        ///
        ///   Example with glTFast (com.unity.glTFast):
        ///     var import = new GltfImport();
        ///     await import.Load(glbBytes);
        ///     await import.InstantiateScene(...);  // wrap in a coroutine/async helper
        ///
        /// Until wired, 3D UGC spawns as a named placeholder cube so nothing
        /// is silently missing.
        /// </summary>
        public static Func<byte[], GameObject> GlbModelFactory;

        /// <summary>
        /// Spawn the local player wearing their RetroBlox avatar.
        /// Must be signed in first (RetroBloxAuth.SignIn) — otherwise nothing spawns.
        /// </summary>
        /// <param name="position">World spawn point (defaults to origin).</param>
        /// <param name="scale">Character size in units (defaults to 2 = classic chunky).</param>
        public static void SpawnLocalPlayer(Vector3? position = null, float scale = 2f) =>
            RetroBloxClient.Run(SpawnRoutine(RetroBloxAuth.Current?.UserId, position, scale, go =>
            {
                LocalPlayer = go;
                OnLocalPlayerSpawned?.Invoke(go);
            }));

        /// <summary>Spawn ANY RetroBlox user's avatar (e.g. other players when you add multiplayer later).</summary>
        public static void SpawnRemotePlayer(string userId, Vector3 position, float scale = 2f) =>
            RetroBloxClient.Run(SpawnRoutine(userId, position, scale, null));

        internal static IEnumerator SpawnRoutine(string userId, Vector3? position, float scale, Action<GameObject> onDone)
        {
            if (!RetroBloxClient.IsSignedIn && userId == null)
            {
                Debug.LogWarning("[RetroBlox] SpawnLocalPlayer skipped — nobody is signed in.");
                yield break;
            }

            AvatarConfig cfg = null;
            string error = null;
            yield return RetroBloxAvatar.Fetch(userId, c => cfg = c, e => error = e);
            if (error != null) { Debug.LogWarning($"[RetroBlox] avatar fetch failed: {error}"); yield break; }

            // Warm the asset cache so the builder can read colors/kinds sync.
            yield return RetroBloxAssets.Resolve(cfg.body, _ => { }, _ => { });
            yield return RetroBloxAssets.Resolve(cfg.pants, _ => { }, _ => { });
            yield return RetroBloxAssets.Resolve(cfg.shirt, _ => { }, _ => { });
            yield return RetroBloxAssets.Resolve(cfg.head, _ => { }, _ => { });
            foreach (var acc in ParseAccessories(cfg.accessories))
                yield return RetroBloxAssets.Resolve(acc, _ => { }, _ => { });

            var player = BuildBlockhead(cfg, position ?? Vector3.zero, scale);
            Debug.Log($"[RetroBlox] spawned {userId ?? "local player"} with avatar body={cfg.body} head={cfg.head}");
            onDone?.Invoke(player);
        }

        // ------------------------------------------------ avatar builder
        // The official R6 PLAYER MODEL (same rig as Models/R6IK.fbx):
        // Head 1.2^, Torso 2x2x1, Arms 1x2x1, Legs 1x2x1 studs.
        // 1 stud = 0.5 units -> the character is ~2.6 units tall.
        //
        // UGC PLACEMENT IS SACRED — the SDK never repositions anything:
        //   hat/gear  -> one quad per item, 1.6 units (48 studs) centred on
        //                the head, pixel-for-pixel with the official template
        //   t-shirt   -> quad centred on the torso front, same 1:1 rule
        //   face      -> the head front itself
        //   shirt     -> the 300x190 template CROPPED onto torso + arms
        //   pants     -> the 220x190 template CROPPED onto both legs
        // No offsets, no stacking. Whatever the creator painted is what shows.

        // clothing template geometry (top-left pixel origin) — these MUST
        // match the official shirt-template.png / pants-template.png
        private static readonly Vector2 SHIRT_TPL = new Vector2(300f, 190f);
        private static readonly Rect SHIRT_TORSO = new Rect(80f, 30f, 120f, 120f);
        private static readonly Rect SHIRT_ARM_R = new Rect(10f, 30f, 60f, 120f);
        private static readonly Rect SHIRT_ARM_L = new Rect(210f, 30f, 60f, 120f);
        private static readonly Vector2 PANTS_TPL = new Vector2(220f, 190f);
        private static readonly Rect PANTS_LEG_R = new Rect(30f, 30f, 60f, 120f);
        private static readonly Rect PANTS_LEG_L = new Rect(120f, 30f, 60f, 120f);

        internal static GameObject BuildBlockhead(AvatarConfig cfg, Vector3 at, float scale)
        {
            var root = new GameObject("RetroBloxPlayer");
            root.transform.position = at;
            root.AddComponent<Rigidbody>(); // physics-ready by default
            var collider = root.AddComponent<CapsuleCollider>();
            collider.height = 2.6f;
            collider.center = new Vector3(0, 1.3f, 0);

            var bodyInfo = ResolveSync(cfg.body);
            var shirtInfo = ResolveSync(cfg.shirt);
            var pantsInfo = ResolveSync(cfg.pants);
            Color skin = RetroBloxAssets.ToColor(bodyInfo?.color, new Color(1f, 0.83f, 0.31f));
            Color shirt = RetroBloxAssets.ToColor(shirtInfo?.color, new Color(0.18f, 0.49f, 0.77f));
            Color pants = RetroBloxAssets.ToColor(pantsInfo?.color, new Color(0.22f, 0.32f, 0.42f));

            // advanced per-part Body Colors from the website editor win when set —
            // every part falls back to its classic color otherwise
            var c = cfg.colors;
            Color headColor = PartColor(c != null ? c.head : null, skin);
            Color torsoColor = PartColor(c != null ? c.torso : null, shirt);
            Color armLColor = PartColor(c != null ? c.armL : null, skin);
            Color armRColor = PartColor(c != null ? c.armR : null, skin);
            Color legLColor = PartColor(c != null ? c.legL : null, pants);
            Color legRColor = PartColor(c != null ? c.legR : null, pants);

            // R6 legs (1x2x1 studs)
            var legR = Part(root, "Right Leg", new Vector3(-0.25f, 0.5f, 0), new Vector3(0.5f, 1f, 0.5f), legRColor);
            var legL = Part(root, "Left Leg", new Vector3(0.25f, 0.5f, 0), new Vector3(0.5f, 1f, 0.5f), legLColor);
            // R6 arms (1x2x1)
            var armR = Part(root, "Right Arm", new Vector3(-0.75f, 1.5f, 0), new Vector3(0.5f, 1f, 0.5f), armRColor);
            var armL = Part(root, "Left Arm", new Vector3(0.75f, 1.5f, 0), new Vector3(0.5f, 1f, 0.5f), armLColor);
            // R6 torso (2x2x1)
            var torso = Part(root, "Torso", new Vector3(0, 1.5f, 0), new Vector3(1f, 1f, 0.5f), torsoColor);
            // R6 head (1.2^) + face — the face quad is 62% of the head front at
            // scale 1, the classic face size (a full-head decal makes the smile
            // huge). The website's Face size slider scales it (0.5..2).
            var head = Part(root, "Head", new Vector3(0, 2.3f, 0), new Vector3(0.6f, 0.6f, 0.6f), headColor);
            float faceSize = 0.372f * cfg.FaceScale;
            AttachImageQuad(root, head, cfg.head, new Vector2(faceSize, faceSize), new Vector3(0, 0, -0.305f), flipZ: true);

            // UGC clothing art, zone-cropped exactly like the website preview
            if (!string.IsNullOrEmpty(shirtInfo?.imageUrl))
            {
                AttachImageQuad(root, torso, cfg.shirt, new Vector2(1f, 1f), new Vector3(0, 0, -0.26f), flipZ: true, uvCropPixels: SHIRT_TORSO, tplPixels: SHIRT_TPL);
                AttachImageQuad(root, armR, cfg.shirt, new Vector2(0.5f, 1f), new Vector3(0, 0, -0.26f), flipZ: true, uvCropPixels: SHIRT_ARM_R, tplPixels: SHIRT_TPL);
                AttachImageQuad(root, armL, cfg.shirt, new Vector2(0.5f, 1f), new Vector3(0, 0, -0.26f), flipZ: true, uvCropPixels: SHIRT_ARM_L, tplPixels: SHIRT_TPL);
            }
            if (!string.IsNullOrEmpty(pantsInfo?.imageUrl))
            {
                AttachImageQuad(root, legR, cfg.pants, new Vector2(0.5f, 1f), new Vector3(0, 0, -0.26f), flipZ: true, uvCropPixels: PANTS_LEG_R, tplPixels: PANTS_TPL);
                AttachImageQuad(root, legL, cfg.pants, new Vector2(0.5f, 1f), new Vector3(0, 0, -0.26f), flipZ: true, uvCropPixels: PANTS_LEG_L, tplPixels: PANTS_TPL);
            }

            // UGC accessories — EVERY item sits where its creator placed it.
            // 3D items (modelUrl + placement) are attached through a web-frame
            // that matches the site's coordinate system, and the placement is
            // applied VERBATIM — no offsets, no auto-fit, no stacking.
            // Legacy image-only hats/gear keep the classic head-slot quad.
            var accessories = ParseAccessories(cfg.accessories);
            int worn = 0;
            foreach (var acc in accessories)
            {
                if (worn >= 6) break;
                var info = ResolveSync(acc);
                if (info != null && info.kind == "tshirt")
                {
                    var tAnchor = new GameObject($"TShirt_{acc}");
                    tAnchor.transform.SetParent(root.transform, false);
                    tAnchor.transform.localPosition = new Vector3(0, 1.5f, -0.27f);
                    AttachImageQuad(root, tAnchor, acc, new Vector2(1.6f, 1.6f), Vector3.zero, flipZ: true);
                }
                else if (info != null && !string.IsNullOrEmpty(info.modelUrl) && info.placement != null && info.placement.IsValid)
                {
                    AttachModel(root, acc, info);
                }
                else // hat | gear | accessory — legacy image-only head slot
                {
                    var hAnchor = new GameObject($"Accessory_{acc}");
                    hAnchor.transform.SetParent(root.transform, false);
                    hAnchor.transform.localPosition = new Vector3(0, 2.3f, -0.31f);
                    AttachImageQuad(root, hAnchor, acc, new Vector2(1.6f, 1.6f), Vector3.zero, flipZ: true);
                }
                worn++;
            }

            root.transform.localScale = Vector3.one * scale;
            return root;
        }

        // ------------------------------------------------ 3D UGC attach

        // web placement space is 5 units tall; the blockhead is 2.6 local units
        private const float WEB_TO_LOCAL = 2.6f / 5f;

        /// <summary>
        /// Attach a creator-placed 3D UGC model. The placement is applied
        /// EXACTLY as the creator left it in the RetroBlox placement editor —
        /// through a frame whose axes match the website's (front = +Z), so
        /// what players saw on the site is what spawns in game. No shader,
        /// no auto-fit, no re-positioning — the creator's word is law.
        /// </summary>
        private static void AttachModel(GameObject root, string assetId, AssetInfo info)
        {
            var frame = new GameObject($"UGCFrame_{assetId}");
            frame.transform.SetParent(root.transform, false);
            // the blockhead's front is -Z (quads face -Z); the placement was
            // authored with front = +Z — flip the frame, keep the placement pure
            frame.transform.localRotation = Quaternion.Euler(0f, 180f, 0f);

            var holder = new GameObject($"UGCModel_{assetId}");
            holder.transform.SetParent(frame.transform, false);
            var pl = info.placement;
            holder.transform.localPosition = new Vector3(pl.p[0], pl.p[1], pl.p[2]) * WEB_TO_LOCAL;
            holder.transform.localEulerAngles = new Vector3(pl.r[0], pl.r[1], pl.r[2]);
            holder.transform.localScale = new Vector3(pl.s[0], pl.s[1], pl.s[2]);

            RetroBloxClient.Run(AttachModelRoutine(holder, info));
        }

        private static IEnumerator AttachModelRoutine(GameObject holder, AssetInfo info)
        {
            byte[] glb = null;
            yield return RetroBloxAssets.DownloadModel(info.modelUrl, b => glb = b);
            if (glb == null || glb.Length == 0 || holder == null) yield break;

            if (GlbModelFactory != null)
            {
                GameObject go = null;
                try { go = GlbModelFactory(glb); }
                catch (Exception e) { Debug.LogWarning($"[RetroBlox] GlbModelFactory failed for {info.assetId}: {e.Message}"); }
                if (go != null)
                {
                    go.transform.SetParent(holder.transform, false);
                    yield break;
                }
            }

            // No glTF runtime wired — spawn an honest placeholder (never guess
            // the look, never skip silently). Wire RetroBloxPlayer.GlbModelFactory.
            var ph = GameObject.CreatePrimitive(PrimitiveType.Cube);
            ph.name = $"{info.assetId}_glb_placeholder";
            ph.transform.SetParent(holder.transform, false);
            ph.transform.localPosition = Vector3.zero;
            ph.transform.localScale = Vector3.one * 0.2f;
            ph.GetComponent<Collider>().enabled = false;
            ph.GetComponent<Renderer>().material.color = new Color(0.4f, 0.7f, 1f, 1f);
            Debug.LogWarning($"[RetroBlox] {info.assetId} is 3D UGC — set RetroBloxPlayer.GlbModelFactory to render the real GLB ({info.modelUrl}).");
        }

        /// <summary>Cache peek (SpawnRoutine pre-resolves everything first).</summary>
        internal static AssetInfo ResolveSync(string assetId) => RetroBloxAssets.Cached(assetId);

        private static GameObject Part(GameObject root, string name, Vector3 localPos, Vector3 size, Color color)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = name;
            go.transform.SetParent(root.transform, false);
            go.transform.localPosition = localPos;
            go.transform.localScale = size;
            var renderer = go.GetComponent<Renderer>();
            renderer.material.color = color;
            return go;
        }

        /// <summary>
        /// A textured quad glued to a part — faces, clothing art, hats, gear,
        /// t-shirts. uvCropPixels crops a zone out of a clothing template
        /// (pixel coords, top-left origin) via texture scale/offset.
        /// </summary>
        private static void AttachImageQuad(GameObject root, GameObject anchor, string assetId, Vector2 size, Vector3 localOffset, bool flipZ,
            Rect? uvCropPixels = null, Vector2? tplPixels = null)
        {
            if (string.IsNullOrEmpty(assetId)) return;
            RetroBloxClient.Run(AttachRoutine(anchor, assetId, size, localOffset, flipZ, uvCropPixels, tplPixels));
        }

        private static IEnumerator AttachRoutine(GameObject anchor, string assetId, Vector2 size, Vector3 offset, bool flipZ, Rect? uvCropPixels, Vector2? tplPixels)
        {
            AssetInfo info = null;
            yield return RetroBloxAssets.Resolve(assetId, i => info = i);
            if (info == null || string.IsNullOrEmpty(info.imageUrl)) yield break;

            Texture2D tex = null;
            yield return RetroBloxAssets.DownloadTexture(info.imageUrl, t => tex = t);
            if (tex == null || anchor == null) yield break;

            var quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
            quad.name = $"{assetId}_art";
            quad.transform.SetParent(anchor.transform, false);
            quad.transform.localPosition = offset;
            quad.transform.localScale = new Vector3(size.x, size.y, 1f);
            if (flipZ) quad.transform.localRotation = Quaternion.Euler(0, 180, 0);
            quad.GetComponent<Collider>().enabled = false;
            var mat = quad.GetComponent<Renderer>().material;
            mat.mainTexture = tex;
            mat.shader = Shader.Find("Unlit/Transparent");
            if (uvCropPixels.HasValue && tplPixels.HasValue)
            {
                var crop = uvCropPixels.Value;
                var tpl = tplPixels.Value;
                // Unity UV origin is bottom-left; template origin is top-left
                mat.mainTextureScale = new Vector2(crop.width / tpl.x, crop.height / tpl.y);
                mat.mainTextureOffset = new Vector2(crop.x / tpl.x, 1f - (crop.y + crop.height) / tpl.y);
            }
        }

        private static List<string> ParseAccessories(string json)
        {
            var list = new List<string>();
            if (string.IsNullOrEmpty(json)) return list;
            try
            {
                var wrapped = JsonUtility.FromJson<AccessoryList>("{\"items\":" + json + "}");
                if (wrapped?.items != null) list.AddRange(wrapped.items);
            }
            catch { /* ignore malformed */ }
            return list;
        }

        [Serializable]
        private class AccessoryList { public string[] items; }

        /// <summary>Parse one "#RRGGBB" Body Color (null / bad hex keeps the fallback).</summary>
        private static Color PartColor(string hex, Color fallback)
        {
            Color parsed;
            return (!string.IsNullOrEmpty(hex) && ColorUtility.TryParseHtmlString(hex, out parsed)) ? parsed : fallback;
        }
    }
}
