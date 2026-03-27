using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using Galaxy.Api;
using HarmonyLib;
using Steamworks;
using StardewModdingAPI;
using StardewModdingAPI.Events;
using StardewValley;
using StardewValley.Buildings;
using StardewValley.Network;
using StardewValley.SDKs;
using StardewValley.SDKs.GogGalaxy;
using StardewValley.SDKs.GogGalaxy.Internal;
using StardewValley.SDKs.GogGalaxy.Listeners;
using StardewValley.SDKs.Steam;

namespace StardropDashboard
{
    public class ModEntry : Mod
    {
        // ── Galaxy / Steam constants (Stardew Valley's registered credentials) ──
        private const string GalaxyClientId     = "48767653913349277";
        private const string GalaxyClientSecret = "58be5c2e55d7f535cf8c4b6bbc09d185de90b152c8c42703cc13502465f0d04a";
        private const string ServerName         = "StardropHost";

        // ── Config ────────────────────────────────────────────────
        private ModConfig Config = null!;

        // ── State ─────────────────────────────────────────────────
        private double _secondsSinceLastWrite       = 0;
        private double _secondsSinceLastGalaxyRetry = 0;
        private string _outputPath = "";

        // ── Static ref — needed by Harmony postfixes ──────────────
        private static ModEntry? _instance  = null;
        private static IModHelper? _helper  = null;

        // ── Invite code ───────────────────────────────────────────
        private static string? _cachedInviteCode = null;

        // ── Steam Game Server ─────────────────────────────────────
        private static bool     _steamInitialized = false;
        private static CSteamID _serverSteamId;
        private static Callback<SteamServersConnected_t>?    _cbConnected;
        private static Callback<SteamServerConnectFailure_t>? _cbConnectFail;
        private static Callback<SteamServersDisconnected_t>?  _cbDisconnected;

        // ── Galaxy init (deferred until Steam ID arrives) ─────────
        private static bool                            _galaxyInitComplete  = false;
        private static bool                            _galaxySignedIn      = false;
        private static SteamHelper?                    _pendingSteamHelper  = null;
        private static IAuthListener?                  _authListener        = null;
        private static IOperationalStateChangeListener? _stateChangeListener = null;

        // ── HTTP client for /steam/app-ticket ─────────────────────
        private static readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(30) };
        private static readonly string _steamAuthUrl =
            (Environment.GetEnvironmentVariable("STEAM_AUTH_URL") ?? "").TrimEnd('/');

        private static readonly JsonSerializerOptions _jsonOpts = new()
        {
            PropertyNamingPolicy   = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            WriteIndented          = true,
        };

        // ── Entry point ───────────────────────────────────────────
        public override void Entry(IModHelper helper)
        {
            _instance = this;
            _helper   = helper;

            Config      = helper.ReadConfig<ModConfig>();
            _outputPath = ResolveOutputPath();
            Directory.CreateDirectory(_outputPath);

            helper.Events.GameLoop.UpdateTicked    += OnUpdateTicked;
            helper.Events.GameLoop.GameLaunched    += OnGameLaunched;
            helper.Events.GameLoop.SaveLoaded      += OnSaveLoaded;
            helper.Events.GameLoop.ReturnedToTitle += (_, _) => WriteOffline();
            helper.Events.GameLoop.DayEnding       += (_, _) => GC.Collect();

            var harmony = new Harmony(ModManifest.UniqueID);

            // Patch 1 — GalaxySocket.GetInviteCode: capture invite code the moment Galaxy generates it
            try
            {
                harmony.Patch(
                    original: AccessTools.Method(typeof(GalaxySocket), nameof(GalaxySocket.GetInviteCode)),
                    postfix:  new HarmonyMethod(typeof(ModEntry), nameof(GalaxySocket_GetInviteCode_Postfix))
                );
                Monitor.Log("Invite code hook applied.", LogLevel.Trace);
            }
            catch (Exception ex)
            {
                Monitor.Log($"Invite code hook failed (non-fatal): {ex.Message}", LogLevel.Warn);
            }

            // Patches 2-4 — SteamHelper: redirect Client API calls to GameServer API
            try
            {
                harmony.Patch(
                    original: AccessTools.Method(typeof(SteamHelper), nameof(SteamHelper.Initialize)),
                    prefix:   new HarmonyMethod(typeof(ModEntry), nameof(SteamHelper_Initialize_Prefix))
                );
                harmony.Patch(
                    original: AccessTools.Method(typeof(SteamHelper), nameof(SteamHelper.Update)),
                    prefix:   new HarmonyMethod(typeof(ModEntry), nameof(SteamHelper_Update_Prefix))
                );
                harmony.Patch(
                    original: AccessTools.Method(typeof(SteamHelper), nameof(SteamHelper.Shutdown)),
                    prefix:   new HarmonyMethod(typeof(ModEntry), nameof(SteamHelper_Shutdown_Prefix))
                );
                Monitor.Log("SteamHelper patches applied.", LogLevel.Trace);
            }
            catch (Exception ex)
            {
                Monitor.Log($"SteamHelper patches failed (non-fatal): {ex.Message}", LogLevel.Warn);
            }

            // Patch 5 — SteamNetServer.initialize: skip (uses Client-only SteamMatchmaking.CreateLobby)
            try
            {
                var steamNetServerType = AccessTools.TypeByName("StardewValley.SDKs.Steam.SteamNetServer");
                if (steamNetServerType != null)
                {
                    harmony.Patch(
                        original: AccessTools.Method(steamNetServerType, "initialize"),
                        prefix:   new HarmonyMethod(typeof(ModEntry), nameof(SteamNetServer_Initialize_Prefix))
                    );
                    Monitor.Log("SteamNetServer.initialize patched (skip).", LogLevel.Trace);
                }
            }
            catch (Exception ex)
            {
                Monitor.Log($"SteamNetServer patch failed (non-fatal): {ex.Message}", LogLevel.Warn);
            }

            // Patches 6-7 — Fake Steam Client API calls that crash in GameServer mode
            // The game calls SteamUser.GetSteamID() and SteamFriends.GetPersonaName() in
            // various places even after we skip SteamHelper.Initialize. Without patching them,
            // they throw because SteamAPI.Init() was never called.
            try
            {
                harmony.Patch(
                    original: AccessTools.Method(typeof(Steamworks.SteamUser), nameof(Steamworks.SteamUser.GetSteamID)),
                    prefix:   new HarmonyMethod(typeof(ModEntry), nameof(SteamUser_GetSteamID_Prefix))
                );
                harmony.Patch(
                    original: AccessTools.Method(typeof(Steamworks.SteamFriends), nameof(Steamworks.SteamFriends.GetPersonaName)),
                    prefix:   new HarmonyMethod(typeof(ModEntry), nameof(SteamFriends_GetPersonaName_Prefix))
                );
                Monitor.Log("SteamUser/SteamFriends patches applied.", LogLevel.Trace);
            }
            catch (Exception ex)
            {
                Monitor.Log($"SteamUser/SteamFriends patches failed (non-fatal): {ex.Message}", LogLevel.Warn);
            }

            helper.ConsoleCommands.Add(
                "dashboard_status",
                "Force an immediate write of live-status.json.",
                (_, _) => { ForceWrite(); Monitor.Log("live-status.json written.", LogLevel.Info); }
            );

            Monitor.Log($"StardropDashboard ready. Output: {_outputPath}", LogLevel.Info);
        }

        // ── SaveLoaded — retry ticket fetch if not yet signed in ──
        // Galaxy only creates the lobby when the save loads, so this is the last
        // moment to sign in and still get an invite code. The user may have logged
        // into steam-auth after the server started but before loading the save.
        private void OnSaveLoaded(object? sender, SaveLoadedEventArgs e)
        {
            ForceWrite();

            if (_galaxyInitComplete && !_galaxySignedIn && !string.IsNullOrEmpty(_steamAuthUrl))
            {
                Monitor.Log("SaveLoaded — retrying Galaxy sign-in (user may have logged in since server started).", LogLevel.Info);
                Task.Run(() => FetchTicketAndSignIn(null));
            }
        }

        // ── GameLaunched — init Steam Game Server (anonymous) ─────
        private void OnGameLaunched(object? sender, GameLaunchedEventArgs e)
        {
            WriteOffline();
            InitSteamGameServer();
        }

        private void InitSteamGameServer()
        {
            try
            {
                // Register callbacks before Init so we don't miss the Connected event
                _cbConnected    = Callback<SteamServersConnected_t>.CreateGameServer(OnSteamServersConnected);
                _cbConnectFail  = Callback<SteamServerConnectFailure_t>.CreateGameServer(OnSteamServersConnectFailure);
                _cbDisconnected = Callback<SteamServersDisconnected_t>.CreateGameServer(OnSteamServersDisconnected);

                bool ok = GameServer.Init(
                    unIP:             0,
                    usGamePort:       24642,
                    usQueryPort:      27015,
                    eServerMode:      EServerMode.eServerModeAuthenticationAndSecure,
                    pchVersionString: Game1.version ?? "1.6.15"
                );

                if (!ok)
                {
                    Monitor.Log("GameServer.Init() returned false — invite codes unavailable.", LogLevel.Warn);
                    return;
                }

                Steamworks.SteamGameServer.SetProduct("Stardew Valley");
                Steamworks.SteamGameServer.SetGameDescription("Stardew Valley Dedicated Server");
                Steamworks.SteamGameServer.SetDedicatedServer(true);
                Steamworks.SteamGameServer.SetMaxPlayerCount(8);
                Steamworks.SteamGameServer.LogOnAnonymous();
                SteamGameServerNetworkingUtils.InitRelayNetworkAccess();

                _steamInitialized = true;
                Monitor.Log("Steam GameServer initialized (anonymous). Waiting for Steam ID...", LogLevel.Info);
            }
            catch (Exception ex)
            {
                Monitor.Log($"Steam GameServer init failed (non-fatal): {ex.Message}", LogLevel.Warn);
            }
        }

        // ── Steam server callbacks ────────────────────────────────
        private static void OnSteamServersConnected(SteamServersConnected_t _)
        {
            _serverSteamId = Steamworks.SteamGameServer.GetSteamID();
            _instance?.Monitor.Log($"Steam GameServer connected. Server ID: {_serverSteamId.m_SteamID}", LogLevel.Info);

            // Complete Galaxy init if SteamHelper.Initialize already fired (race condition)
            if (_pendingSteamHelper != null && !_galaxyInitComplete)
                _instance?.PerformGalaxyInit(_pendingSteamHelper);
        }

        private static void OnSteamServersConnectFailure(SteamServerConnectFailure_t cb)
        {
            _instance?.Monitor.Log($"Steam GameServer connect failed: {cb.m_eResult}", LogLevel.Warn);
        }

        private static void OnSteamServersDisconnected(SteamServersDisconnected_t cb)
        {
            _instance?.Monitor.Log($"Steam GameServer disconnected: {cb.m_eResult}", LogLevel.Warn);
        }

        // ── Harmony: SteamHelper.Initialize prefix ────────────────
        // Replaces SteamAPI.Init() with GameServer mode so the game uses Steam networking
        private static bool SteamHelper_Initialize_Prefix(SteamHelper __instance)
        {
            _instance?.Monitor.Log("SteamHelper.Initialize — GameServer mode.", LogLevel.Debug);
            SetSteamActive(__instance, true);

            if (_steamInitialized && _serverSteamId.IsValid())
                _instance?.PerformGalaxyInit(__instance);  // Steam ID already here
            else
                _pendingSteamHelper = __instance;           // Store for OnSteamServersConnected

            return false; // skip original
        }

        // ── Harmony: SteamHelper.Update prefix ───────────────────
        // Replaces SteamAPI.RunCallbacks() with GameServer + Galaxy callbacks
        private static bool SteamHelper_Update_Prefix(SteamHelper __instance)
        {
            if (_helper == null) return false;
            bool active = _helper.Reflection.GetField<bool>(__instance, "active").GetValue();
            if (active)
            {
                if (_steamInitialized)
                    try { GameServer.RunCallbacks(); } catch { }
                if (_galaxyInitComplete)
                    try { GalaxyInstance.ProcessData(); } catch { }
            }
            Game1.game1.IsMouseVisible = Game1.paused || Game1.options.hardwareCursor;
            return false; // skip original
        }

        // ── Harmony: SteamHelper.Shutdown prefix ─────────────────
        private static bool SteamHelper_Shutdown_Prefix()
        {
            _instance?.Monitor.Log("SteamHelper.Shutdown — GameServer mode.", LogLevel.Debug);
            _cachedInviteCode    = null;
            _galaxySignedIn      = false;
            _galaxyInitComplete  = false;
            _pendingSteamHelper  = null;
            _authListener        = null;
            _stateChangeListener = null;
            if (_steamInitialized)
            {
                try { GameServer.Shutdown(); } catch { }
                _steamInitialized = false;
            }
            return false; // skip original
        }

        // ── Harmony: SteamNetServer.initialize prefix — skip ─────
        // Game's built-in SteamNetServer.initialize() calls SteamMatchmaking.CreateLobby()
        // which requires Steam Client API (not available in GameServer mode).
        private static bool SteamNetServer_Initialize_Prefix()
        {
            _instance?.Monitor.Log("SteamNetServer.initialize skipped (GameServer mode).", LogLevel.Debug);
            return false; // skip original
        }

        // ── Harmony: SteamUser.GetSteamID prefix ─────────────────
        // SteamAPI.Init() was never called (GameServer mode), so any direct call to
        // SteamUser.GetSteamID() would crash. Return GameServer's Steam ID instead,
        // or a stable fake ID while waiting for the GameServer connection.
        private static bool SteamUser_GetSteamID_Prefix(ref CSteamID __result)
        {
            __result = (_steamInitialized && _serverSteamId.IsValid())
                ? _serverSteamId
                : new CSteamID(123456789UL);
            return false; // skip original
        }

        // ── Harmony: SteamFriends.GetPersonaName prefix ──────────
        // Same reason as above — Steam Client API unavailable in GameServer mode.
        private static bool SteamFriends_GetPersonaName_Prefix(ref string __result)
        {
            __result = ServerName;
            return false; // skip original
        }

        // ── Galaxy init (runs once Steam ID is confirmed) ─────────
        private void PerformGalaxyInit(SteamHelper steamHelper)
        {
            if (_galaxyInitComplete) return;
            _pendingSteamHelper = null;

            try
            {
                Monitor.Log("Initializing GOG Galaxy SDK for invite codes...", LogLevel.Info);
                GalaxyInstance.Init(new InitParams(GalaxyClientId, GalaxyClientSecret, "."));

                _authListener        = CreateGalaxyAuthListener(steamHelper);
                _stateChangeListener = CreateGalaxyStateChangeListener(steamHelper);

                _galaxyInitComplete = true;

                if (!string.IsNullOrEmpty(_steamAuthUrl))
                {
                    // Fetch app ticket from steam-auth and sign in to Galaxy (non-blocking)
                    Task.Run(() => FetchTicketAndSignIn(steamHelper));
                }
                else
                {
                    Monitor.Log("STEAM_AUTH_URL not set — invite codes need steam-auth logged in.", LogLevel.Warn);
                    SetSteamNetworking(steamHelper, CreateSteamNetHelper());
                    SetSteamConnectionFinished(steamHelper, true);
                }
            }
            catch (Exception ex)
            {
                Monitor.Log($"Galaxy init failed (non-fatal): {ex.Message}", LogLevel.Warn);
                SetSteamNetworking(steamHelper, CreateSteamNetHelper());
                SetSteamConnectionFinished(steamHelper, true);
            }
        }

        // steamHelper is null on the SaveLoaded retry path (connection state already finalised)
        private async Task FetchTicketAndSignIn(SteamHelper? steamHelper)
        {
            try
            {
                Monitor.Log("Requesting Steam app ticket from steam-auth...", LogLevel.Info);
                var response = await _http.GetAsync($"{_steamAuthUrl}/steam/app-ticket");

                if (!response.IsSuccessStatusCode)
                {
                    var body = await response.Content.ReadAsStringAsync();
                    Monitor.Log($"steam-auth returned {(int)response.StatusCode}: {body}", LogLevel.Warn);
                    Monitor.Log("Log in via the Steam panel to enable invite codes.", LogLevel.Warn);
                    if (steamHelper != null)
                    {
                        SetSteamNetworking(steamHelper, CreateSteamNetHelper());
                        SetSteamConnectionFinished(steamHelper, true);
                    }
                    return;
                }

                var json   = await response.Content.ReadAsStringAsync();
                var doc    = JsonDocument.Parse(json);
                var b64    = doc.RootElement.GetProperty("app_ticket").GetString() ?? "";
                var ticket = Convert.FromBase64String(b64);

                Monitor.Log($"App ticket received ({ticket.Length} bytes). Signing into Galaxy...", LogLevel.Info);
                _galaxySignedIn = true;
                GalaxyInstance.User().SignInSteam(ticket, (uint)ticket.Length, ServerName);
                // Galaxy auth result arrives via _authListener / _stateChangeListener callbacks
            }
            catch (Exception ex)
            {
                Monitor.Log($"App ticket fetch failed (non-fatal): {ex.Message}", LogLevel.Warn);
                Monitor.Log("Log in via the Steam panel to enable invite codes.", LogLevel.Warn);
                if (steamHelper != null)
                {
                    SetSteamNetworking(steamHelper, CreateSteamNetHelper());
                    SetSteamConnectionFinished(steamHelper, true);
                }
            }
        }

        // ── Galaxy listeners ──────────────────────────────────────
        private IAuthListener CreateGalaxyAuthListener(SteamHelper steamHelper)
        {
            var listenerType = AccessTools.TypeByName("StardewValley.SDKs.GogGalaxy.Listeners.GalaxyAuthListener");

            Action onSuccess = () =>
                Monitor.Log("Galaxy auth success.", LogLevel.Info);

            Action<IAuthListener.FailureReason> onFailure = (reason) =>
            {
                Monitor.Log($"Galaxy auth failure: {reason}", LogLevel.Warn);
                if (steamHelper.Networking == null)
                    SetSteamNetworking(steamHelper, CreateSteamNetHelper());
                SetSteamConnectionFinished(steamHelper, true);
            };

            Action onLost = () =>
            {
                Monitor.Log("Galaxy auth lost.", LogLevel.Warn);
                if (steamHelper.Networking == null)
                    SetSteamNetworking(steamHelper, CreateSteamNetHelper());
                SetSteamConnectionFinished(steamHelper, true);
            };

            return (IAuthListener)Activator.CreateInstance(listenerType, onSuccess, onFailure, onLost)!;
        }

        private IOperationalStateChangeListener CreateGalaxyStateChangeListener(SteamHelper steamHelper)
        {
            var listenerType = AccessTools.TypeByName("StardewValley.SDKs.GogGalaxy.Listeners.GalaxyOperationalStateChangeListener");

            Action<uint> onStateChange = (state) =>
            {
                if ((state & 1) != 0)
                    Monitor.Log("Galaxy signed in.", LogLevel.Debug);

                if ((state & 2) != 0)
                {
                    Monitor.Log("Galaxy logged on — invite codes active.", LogLevel.Info);
                    // Networking may already be set from the initial fallback (ticket fetch failed
                    // at launch). Don't overwrite it, but always mark Galaxy as connected —
                    // SetSteamGalaxyConnected(true) switches sdk.Networking to GalaxyNetHelper,
                    // which TryLateAddGalaxyServer then uses to create the GalaxyNetServer.
                    if (steamHelper.Networking == null)
                    {
                        SetSteamNetworking(steamHelper, CreateSteamNetHelper());
                        SetSteamConnectionFinished(steamHelper, true);
                    }
                    SetSteamGalaxyConnected(steamHelper, true);
                    TryLateAddGalaxyServer();
                }
            };

            return (IOperationalStateChangeListener)Activator.CreateInstance(listenerType, onStateChange)!;
        }

        // ── Late-add Galaxy server (race condition recovery) ──────
        // Called when Galaxy logs on after the game server is already running.
        // Adds a GalaxyNetServer to Game1.server's internal servers list so the
        // Galaxy lobby is created and an invite code becomes available.
        // Must be called AFTER SetSteamGalaxyConnected(true) — that call switches
        // sdk.Networking to GalaxyNetHelper so CreateServer() produces the right type.
        private static void TryLateAddGalaxyServer()
        {
            try
            {
                if (Game1.server == null)
                {
                    _instance?.Monitor.Log("TryLateAddGalaxyServer: Game1.server is null, skipping.", LogLevel.Debug);
                    return;
                }

                var sdkGetter = AccessTools.PropertyGetter(
                    AccessTools.TypeByName("StardewValley.Program"), "sdk");
                var sdk = sdkGetter?.Invoke(null, null) as SDKHelper;
                if (sdk?.Networking == null)
                {
                    _instance?.Monitor.Log("TryLateAddGalaxyServer: sdk.Networking is null, skipping.", LogLevel.Debug);
                    return;
                }

                var serversField = _helper!.Reflection.GetField<List<Server>>(Game1.server, "servers");
                var servers = serversField.GetValue();

                // Don't add a second GalaxyNetServer if one already exists
                bool alreadyHasGalaxy = false;
                foreach (var s in servers)
                    if (s.GetType().Name == "GalaxyNetServer") { alreadyHasGalaxy = true; break; }

                if (alreadyHasGalaxy)
                {
                    _instance?.Monitor.Log("TryLateAddGalaxyServer: GalaxyNetServer already present.", LogLevel.Debug);
                    return;
                }

                _instance?.Monitor.Log("Late-adding GalaxyNetServer (Galaxy logged on after server created)...", LogLevel.Info);
                var galaxyServer = sdk.Networking.CreateServer(Game1.server);
                if (galaxyServer != null)
                {
                    servers.Add(galaxyServer);
                    galaxyServer.initialize();
                    _instance?.Monitor.Log("GalaxyNetServer added — invite code should appear shortly.", LogLevel.Info);
                }
                else
                {
                    _instance?.Monitor.Log("TryLateAddGalaxyServer: CreateServer returned null.", LogLevel.Warn);
                }
            }
            catch (Exception ex)
            {
                _instance?.Monitor.Log($"TryLateAddGalaxyServer failed (non-fatal): {ex.Message}", LogLevel.Warn);
            }
        }

        // ── SteamHelper reflection helpers ────────────────────────
        private static void SetSteamActive(SteamHelper h, bool v) =>
            _helper!.Reflection.GetField<bool>(h, "active").SetValue(v);
        private static void SetSteamConnectionFinished(SteamHelper h, bool v) =>
            _helper!.Reflection.GetProperty<bool>(h, "ConnectionFinished").SetValue(v);
        private static void SetSteamGalaxyConnected(SteamHelper h, bool v) =>
            _helper!.Reflection.GetProperty<bool>(h, "GalaxyConnected").SetValue(v);
        private static void SetSteamNetworking(SteamHelper h, SDKNetHelper n) =>
            _helper!.Reflection.GetField<SDKNetHelper>(h, "networking").SetValue(n);

        private static SDKNetHelper CreateSteamNetHelper()
        {
            var type = AccessTools.TypeByName("StardewValley.SDKs.Steam.SteamNetHelper");
            return (SDKNetHelper)Activator.CreateInstance(type)!;
        }

        // ── Harmony postfix — fires when Galaxy generates invite code ──
        private static void GalaxySocket_GetInviteCode_Postfix(string __result)
        {
            if (string.IsNullOrEmpty(__result)) return;
            if (__result == _cachedInviteCode) return;

            _cachedInviteCode = __result;
            _instance?.Monitor.Log($"[InviteCode] Captured: {__result}", LogLevel.Debug);
            _instance?.ForceWrite();
        }

        // ── Resolve output directory ──────────────────────────────
        private string ResolveOutputPath()
        {
            if (!string.IsNullOrWhiteSpace(Config.OutputDirectory))
                return Config.OutputDirectory;
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            return Path.Combine(home, ".local", "share", "stardrop");
        }

        private string LiveStatusFile => Path.Combine(_outputPath, "live-status.json");

        // ── Tick update ───────────────────────────────────────────
        private void OnUpdateTicked(object? sender, UpdateTickedEventArgs e)
        {
            if (!Context.IsWorldReady) return;

            // Keep multiplayer network settings tuned for low latency.
            // These revert to defaults if not re-applied each tick.
            Game1.Multiplayer.defaultInterpolationTicks      = 7;  // default: 15
            Game1.Multiplayer.farmerDeltaBroadcastPeriod     = 1;  // default: 3
            Game1.Multiplayer.locationDeltaBroadcastPeriod   = 1;  // default: 3
            Game1.Multiplayer.worldStateDeltaBroadcastPeriod = 1;  // default: 3

            double elapsed = Game1.currentGameTime.ElapsedGameTime.TotalSeconds;
            _secondsSinceLastWrite += elapsed;

            if (_secondsSinceLastWrite >= Config.UpdateIntervalSeconds)
            {
                _secondsSinceLastWrite = 0;
                WriteStatus();
            }

            // Retry Galaxy sign-in every 30s while running but not yet signed in.
            // Covers the case where the user opens the panel and logs into steam-auth
            // after the save has already loaded (the SaveLoaded one-shot is already gone).
            if (_galaxyInitComplete && !_galaxySignedIn && !string.IsNullOrEmpty(_steamAuthUrl))
            {
                _secondsSinceLastGalaxyRetry += elapsed;
                if (_secondsSinceLastGalaxyRetry >= 30)
                {
                    _secondsSinceLastGalaxyRetry = 0;
                    Task.Run(() => FetchTicketAndSignIn(null));
                }
            }
        }

        // ── Write offline tombstone ───────────────────────────────
        private void WriteOffline()
        {
            _cachedInviteCode            = null;
            _galaxySignedIn              = false;
            _secondsSinceLastGalaxyRetry = 0;
            WriteToDisk(new LiveStatus
            {
                Timestamp   = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                ServerState = "offline",
            });
        }

        private void ForceWrite()
        {
            if (Context.IsWorldReady) WriteStatus();
            else WriteOffline();
        }

        private void WriteStatus()
        {
            try { WriteToDisk(CollectStatus()); }
            catch (Exception ex)
            {
                Monitor.Log($"Failed to write live-status.json: {ex.Message}", LogLevel.Warn);
            }
        }

        private LiveStatus CollectStatus()
        {
            // -- Players --
            var players = new List<PlayerData>();
            foreach (var farmer in Game1.getOnlineFarmers())
            {
                try
                {
                    players.Add(new PlayerData
                    {
                        Name         = farmer.Name,
                        UniqueId     = farmer.UniqueMultiplayerID.ToString(),
                        IsHost       = farmer.IsMainPlayer,
                        IsOnline     = true,
                        Health       = farmer.health,
                        MaxHealth    = farmer.maxHealth,
                        Stamina      = farmer.stamina,
                        MaxStamina   = farmer.maxStamina.Value,
                        Money        = farmer.Money,
                        TotalEarned  = (long)farmer.totalMoneyEarned,
                        LocationName = farmer.currentLocation?.Name ?? "",
                        DaysPlayed   = (int)farmer.stats.DaysPlayed,
                        Skills       = new SkillData
                        {
                            Farming  = farmer.FarmingLevel,
                            Mining   = farmer.MiningLevel,
                            Foraging = farmer.ForagingLevel,
                            Fishing  = farmer.FishingLevel,
                            Combat   = farmer.CombatLevel,
                            Luck     = farmer.LuckLevel,
                        },
                    });
                }
                catch (Exception ex)
                {
                    Monitor.Log($"Error reading player {farmer?.Name}: {ex.Message}", LogLevel.Trace);
                }
            }

            // -- Cabins --
            var cabins = new List<CabinData>();
            foreach (var building in Game1.getFarm().buildings)
            {
                if (building.indoors.Value is StardewValley.Locations.Cabin cabin)
                {
                    var owner = cabin.owner;
                    bool isOnline = false;
                    if (owner != null)
                        foreach (var f in Game1.getOnlineFarmers())
                            if (f.UniqueMultiplayerID == owner.UniqueMultiplayerID)
                                { isOnline = true; break; }

                    cabins.Add(new CabinData
                    {
                        OwnerName     = owner?.Name ?? "",
                        IsOwnerOnline = isOnline,
                        TileX         = building.tileX.Value,
                        TileY         = building.tileY.Value,
                        IsUpgraded    = building.daysOfConstructionLeft.Value <= 0,
                    });
                }
            }

            // -- Weather --
            string weather = Game1.isRaining    ? "rain"
                           : Game1.isSnowing    ? "snow"
                           : Game1.isLightning  ? "storm"
                           : Game1.isDebrisWeather ? "wind"
                           : "sunny";

            // -- Festival --
            bool isFestival = Game1.isFestival();
            string festivalName = isFestival && Game1.CurrentEvent != null
                ? Game1.CurrentEvent.FestivalName ?? ""
                : "";

            // -- Time formatting --
            int timeInt = Game1.timeOfDay;
            int hours   = timeInt / 100;
            int minutes = timeInt % 100;
            bool isPm   = hours >= 12;
            int hours12 = hours > 12 ? hours - 12 : hours == 0 ? 12 : hours;
            string timeStr = $"{hours12}:{minutes:D2} {(isPm ? "PM" : "AM")}";

            // -- Invite code (from Harmony hook; fall back to polling) --
            string? inviteCode = _cachedInviteCode;
            if (string.IsNullOrEmpty(inviteCode))
            {
                try { inviteCode = Game1.server?.getInviteCode(); } catch { }
                if (!string.IsNullOrEmpty(inviteCode))
                    _cachedInviteCode = inviteCode;
            }

            return new LiveStatus
            {
                Timestamp        = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                ServerState      = "running",
                InviteCode       = inviteCode,
                FarmName         = Game1.player.farmName.Value ?? "",
                Season           = Game1.currentSeason ?? "",
                Day              = Game1.dayOfMonth,
                Year             = Game1.year,
                GameTimeMinutes  = timeInt,
                DayTimeFormatted = timeStr,
                Weather          = weather,
                IsFestivalDay    = isFestival,
                FestivalName     = festivalName,
                SharedMoney      = Game1.player.Money,
                Players          = players,
                Cabins           = cabins,
            };
        }

        // ── Write to disk (atomic via temp file) ──────────────────
        private void WriteToDisk(LiveStatus status)
        {
            string json    = JsonSerializer.Serialize(status, _jsonOpts);
            string tmpFile = LiveStatusFile + ".tmp";
            File.WriteAllText(tmpFile, json);
            File.Move(tmpFile, LiveStatusFile, overwrite: true);
        }
    }
}
