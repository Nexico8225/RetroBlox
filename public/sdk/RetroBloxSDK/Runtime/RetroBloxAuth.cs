// RetroBlox SDK — RetroBloxAuth.cs
// Sign a player into their RetroBlox account from inside any game.
// The SDK sends credentials to the RetroBlox API and keeps the session
// token on the device. Credentials never go anywhere else, and the
// database stays on the server where it belongs.

using System;
using System.Collections;

namespace RetroBlox
{
    [Serializable]
    internal class LoginResponse
    {
        public bool ok;
        public string token;
        public string userId;
        public string username;
        public string error;
    }

    [Serializable]
    public class RetroBloxAccount
    {
        public string UserId;
        public string Username;
    }

    public static class RetroBloxAuth
    {
        public static RetroBloxAccount Current { get; private set; }

        /// <summary>Fired once sign-in (or sign-out) changes the current account.</summary>
        public static event Action<RetroBloxAccount> OnSignedIn;
        public static event Action OnSignedOut;

        public static IEnumerator SignIn(string username, string password, Action<RetroBloxAccount> onDone = null, Action<string> onError = null)
        {
            string body = JsonUtility.ToJson(new LoginRequest { username = username, password = password });
            string error = null;

            yield return RetroBloxClient.Post("/api/platform/login", body,
                json =>
                {
                    var res = JsonUtility.FromJson<LoginResponse>(json);
                    if (res == null || !res.ok)
                    {
                        error = res?.error ?? "Sign-in failed";
                        return;
                    }
                    RetroBloxClient.Token = res.token;
                    Current = new RetroBloxAccount { UserId = res.userId, Username = res.username };
                },
                msg => error = msg);

            if (error != null) onError?.Invoke(error);
            else
            {
                OnSignedIn?.Invoke(Current);
                onDone?.Invoke(Current);
            }
        }

        public static void SignOut()
        {
            RetroBloxClient.Token = null;
            Current = null;
            OnSignedOut?.Invoke();
        }
    }

    [Serializable]
    internal class LoginRequest { public string username; public string password; }
}
