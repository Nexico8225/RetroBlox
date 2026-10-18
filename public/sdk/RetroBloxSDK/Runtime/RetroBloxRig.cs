// RetroBlox SDK — RetroBloxRig.cs
// Use the OFFICIAL R6 player model (Models/R6IK.fbx — the rigged rig with
// IK bones) instead of the auto-built cube blockhead:
//
//     // drop the R6IK.fbx prefab into your scene, then:
//     RetroBloxRig.Apply(gameObject, RetroBloxAuth.Current.UserId);
//
// It fetches the player's account-wide avatar and applies it to the rig:
//   - recolors Head / Torso / Left Arm / Right Arm / Left Leg / Right Leg
//     by part name (case/space insensitive — "LeftArm" works too)
//   - face art onto the head front
//   - every hat/gear/t-shirt the player wears, EXACTLY where the creator
//     placed it (1:1 with the official templates — never repositioned)
//   - UGC shirt/pants template art cropped onto torso + arms / legs

using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace RetroBlox
{
    public static class RetroBloxRig
    {
        public static event Action<GameObject> OnRigApplied;

        /// <summary>Apply a RetroBlox avatar to a scene instance of the R6 rig.</summary>
        public static void Apply(GameObject rig, string userId) =>
            RetroBloxClient.Run(ApplyRoutine(rig, userId));

        public static IEnumerator ApplyRoutine(GameObject rig, string userId)
        {
            if (rig == null) yield break;

            AvatarConfig cfg = null;
            string error = null;
            yield return RetroBloxAvatar.Fetch(userId, c => cfg = c, e => error = e);
            if (error != null || cfg == null)
            {
                Debug.LogWarning($"[RetroBlox] rig apply failed: {error ?? "no avatar"}");
                yield break;
            }

            // warm the cache (colors + kinds), same as RetroBloxPlayer does
            yield return RetroBloxAssets.Resolve(cfg.body, _ => { }, _ => { });
            yield return RetroBloxAssets.Resolve(cfg.pants, _ => { }, _ => { });
            yield return RetroBloxAssets.Resolve(cfg.shirt, _ => { }, _ => { });
            yield return RetroBloxAssets.Resolve(cfg.head, _ => { }, _ => { });
            foreach (var acc in ParseAccessories(cfg.accessories))
                yield return RetroBloxAssets.Resolve(acc, _ => { }, _ => { });

            var parts = PartMap(rig);

            var bodyInfo = RetroBloxPlayer.ResolveSync(cfg.body);
            var shirtInfo = RetroBloxPlayer.ResolveSync(cfg.shirt);
            var pantsInfo = RetroBloxPlayer.ResolveSync(cfg.pants);
            Color skin = RetroBloxAssets.ToColor(bodyInfo?.color, new Color(1f, 0.83f, 0.31f));
            Color shirt = RetroBloxAssets.ToColor(shirtInfo?.color, new Color(0.18f, 0.49f, 0.77f));
            Color pants = RetroBloxAssets.ToColor(pantsInfo?.color, new Color(0.22f, 0.32f, 0.42f));

            Recolor(parts, "head", skin);
            Recolor(parts, "torso", shirt);
            Recolor(parts, "leftarm", skin);
            Recolor(parts, "rightarm", skin);
            Recolor(parts, "leftleg", pants);
            Recolor(parts, "rightleg", pants);

            // face on the head front (Face size slider scales it, 0.5..2)
            var head = FindPart(parts, "head");
            if (head != null)
            {
                float fs = cfg.FaceScale;
                Quad(head, cfg.head, new Vector2(1.05f * fs, 1.05f * fs), 0.56f, flipZ: true);
            }

            // UGC clothing art wrapped onto the rig parts (zone-cropped)
            var shirtInfo2 = RetroBloxPlayer.ResolveSync(cfg.shirt);
            var pantsInfo2 = RetroBloxPlayer.ResolveSync(cfg.pants);
            if (shirtInfo2?.imageUrl != null)
            {
                var torso = FindPart(parts, "torso");
                if (torso != null)
                {
                    Quad(torso, cfg.shirt, new Vector2(1.02f, 1.02f), 0.51f, flipZ: true, uvCrop: ShirtZone("torso"), tpl: SHIRT_TPL);
                    Quad(torso, cfg.shirt, new Vector2(0.52f, 1.02f), 0.51f, flipZ: true, uvCrop: ShirtZone("armL"), tpl: SHIRT_TPL, side: +1);
                    Quad(torso, cfg.shirt, new Vector2(0.52f, 1.02f), 0.51f, flipZ: true, uvCrop: ShirtZone("armR"), tpl: SHIRT_TPL, side: -1);
                }
            }
            if (pantsInfo2?.imageUrl != null)
            {
                var legL = FindPart(parts, "leftleg");
                var legR = FindPart(parts, "rightleg");
                if (legL != null) Quad(legL, cfg.pants, new Vector2(0.52f, 1.02f), 0.51f, flipZ: true, uvCrop: PantsZone("legL"), tpl: PANTS_TPL);
                if (legR != null) Quad(legR, cfg.pants, new Vector2(0.52f, 1.02f), 0.51f, flipZ: true, uvCrop: PantsZone("legR"), tpl: PANTS_TPL);
            }

            // accessories — placement is sacred, one 1:1 quad each
            var torsoPart = FindPart(parts, "torso");
            int worn = 0;
            foreach (var acc in ParseAccessories(cfg.accessories))
            {
                if (worn >= 6) break;
                var info = RetroBloxPlayer.ResolveSync(acc);
                if (info != null && info.kind == "tshirt")
                {
                    if (torsoPart != null) Quad(torsoPart, acc, new Vector2(1.7f, 1.7f), 0.52f, flipZ: true);
                }
                else if (head != null)
                {
                    Quad(head, acc, new Vector2(1.7f, 1.7f), 0.57f, flipZ: true);
                }
                worn++;
            }

            Debug.Log($"[RetroBlox] R6 rig applied for {userId} (body={cfg.body} head={cfg.head})");
            OnRigApplied?.Invoke(rig);
        }

        // ---- internals

        private static readonly Vector2 SHIRT_TPL = new Vector2(300f, 190f);
        private static readonly Rect SHIRT_TORSO = new Rect(80f, 30f, 120f, 120f);
        private static readonly Rect SHIRT_ARM_R = new Rect(10f, 30f, 60f, 120f);
        private static readonly Rect SHIRT_ARM_L = new Rect(210f, 30f, 60f, 120f);
        private static readonly Vector2 PANTS_TPL = new Vector2(220f, 190f);
        private static readonly Rect PANTS_LEG_R = new Rect(30f, 30f, 60f, 120f);
        private static readonly Rect PANTS_LEG_L = new Rect(120f, 30f, 60f, 120f);

        private static Rect? ShirtZone(string z) =>
            z == "torso" ? (Rect?)SHIRT_TORSO : z == "armL" ? (Rect?)SHIRT_ARM_L : (Rect?)SHIRT_ARM_R;
        private static Rect? PantsZone(string z) =>
            z == "legL" ? (Rect?)PANTS_LEG_L : (Rect?)PANTS_LEG_R;

        private static Dictionary<string, Renderer> PartMap(GameObject rig)
        {
            var map = new Dictionary<string, Renderer>();
            foreach (var r in rig.GetComponentsInChildren<Renderer>())
            {
                var key = Normalize(r.transform.name);
                if (!map.ContainsKey(key)) map[key] = r;
            }
            return map;
        }

        private static Renderer FindPart(Dictionary<string, Renderer> map, string key) =>
            map.TryGetValue(key, out var r) ? r : null;

        private static string Normalize(string name) =>
            name.Replace(" ", "").Replace("_", "").Replace("-", "").ToLowerInvariant();

        private static void Recolor(Dictionary<string, Renderer> map, string key, Color c)
        {
            var r = FindPart(map, key);
            if (r != null) r.material.color = c;
        }

        /// <summary>
        /// Texture quad glued in FRONT of a part's renderer bounds.
        /// depthOffset pushes it toward the camera (-z) past the part surface.
        /// side: -1 places the quad at the character's right (left arm slot),
        /// +1 at its left — used for shirt sleeves.
        /// </summary>
        private static void Quad(Renderer part, string assetId, Vector2 size, float depthOffset, bool flipZ,
            Rect? uvCrop = null, Vector2? tpl = null, int side = 0)
        {
            if (part == null || string.IsNullOrEmpty(assetId)) return;
            RetroBloxClient.Run(QuadRoutine(part, assetId, size, depthOffset, flipZ, uvCrop, tpl, side));
        }

        private static IEnumerator QuadRoutine(Renderer part, string assetId, Vector2 size, float depthOffset, bool flipZ, Rect? uvCrop, Vector2? tpl, int side)
        {
            AssetInfo info = null;
            yield return RetroBloxAssets.Resolve(assetId, i => info = i);
            if (info == null || string.IsNullOrEmpty(info.imageUrl) || part == null) yield break;

            Texture2D tex = null;
            yield return RetroBloxAssets.DownloadTexture(info.imageUrl, t => tex = t);
            if (tex == null || part == null) yield break;

            var bounds = part.bounds;
            var quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
            quad.name = $"{assetId}_rigart";
            quad.transform.position = new Vector3(
                bounds.center.x + side * (bounds.extents.x + size.x / 2f) * 1.02f,
                bounds.center.y,
                bounds.center.z - bounds.extents.z - depthOffset * 0.1f);
            quad.transform.localScale = new Vector3(size.x, size.y, 1f);
            if (flipZ) quad.transform.localRotation = Quaternion.Euler(0, 180, 0);
            quad.GetComponent<Collider>().enabled = false;
            var mat = quad.GetComponent<Renderer>().material;
            mat.mainTexture = tex;
            mat.shader = Shader.Find("Unlit/Transparent");
            if (uvCrop.HasValue && tpl.HasValue)
            {
                var c = uvCrop.Value;
                var t = tpl.Value;
                mat.mainTextureScale = new Vector2(c.width / t.x, c.height / t.y);
                mat.mainTextureOffset = new Vector2(c.x / t.x, 1f - (c.y + c.height) / t.y);
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
    }
}
