using IVSDKDotNet;
using IVSDKDotNet.Enums;
using System;
using System.Net.Sockets;
using System.Numerics;
using System.Text;
using System.Threading;
using static IVSDKDotNet.Native.Natives;

// ============================================================
//  LiveChaos-IV  |  ChaosScript.cs
//  Reescrito para IV-SDK .NET v1.9.1 (IVSDKDotNetWrapper.dll)
//  Comunica com o bot Python via socket TCP 127.0.0.1:9999
//  O bot envia o nome do efeito como string terminada em '\n'
// ============================================================

namespace LiveChaos
{
    public class ChaosScript : Script
    {
        // ------- configuração do socket -------
        private const string HOST = "127.0.0.1";
        private const int    PORT = 9999;

        // ------- estado interno -------
        private TcpClient     _client;
        private NetworkStream _stream;
        private byte[]        _buffer  = new byte[256];
        private string        _pending = "";
        private readonly object _lock  = new object();

        // cooldown: evita spam no Tick
        private int  _lastEffectTick = 0;
        private const int EFFECT_COOLDOWN_MS = 500;

        // ------- turbo -------
        private const float TURBO_POWER  = 70.0f;
        private const float TURBO_RADIUS = 120.0f;

        // ============================================================
        //  CONSTRUCTOR
        // ============================================================
        public ChaosScript()
        {
            Initialized  += OnInitialized;
            Uninitialize += OnUninitialize;
            Tick         += OnTick;
        }

        // ============================================================
        //  LIFECYCLE
        // ============================================================
        private void OnInitialized(object sender, EventArgs e)
        {
            Thread receiver = new Thread(ReceiveLoop) { IsBackground = true };
            receiver.Start();
        }

        private void OnUninitialize(object sender, EventArgs e)
        {
            try { _client?.Close(); } catch { }
        }

        // ============================================================
        //  THREAD DE REDE  (nunca bloqueia o game loop)
        // ============================================================
        private void ReceiveLoop()
        {
            while (true)
            {
                try
                {
                    if (_client == null || !_client.Connected)
                        Connect();

                    int bytesRead = _stream.Read(_buffer, 0, _buffer.Length);
                    if (bytesRead > 0)
                    {
                        string msg = Encoding.UTF8.GetString(_buffer, 0, bytesRead).Trim();
                        if (!string.IsNullOrEmpty(msg))
                        {
                            lock (_lock)
                            {
                                // Último efeito recebido vence
                                _pending = msg;
                            }
                        }
                    }
                }
                catch
                {
                    // Reconecta após falha
                    _client = null;
                    Thread.Sleep(2000);
                }
            }
        }

        private void Connect()
        {
            try
            {
                _client = new TcpClient();
                _client.Connect(HOST, PORT);
                _stream = _client.GetStream();
            }
            catch
            {
                _client = null;
                Thread.Sleep(2000);
            }
        }

        // ============================================================
        //  GAME TICK  (roda na main thread do GTA IV)
        // ============================================================
        private void OnTick(object sender, EventArgs e)
        {
            // Resolve player
            int playerIdx = CONVERT_INT_TO_PLAYERINDEX(GET_PLAYER_ID());
            GET_PLAYER_CHAR(playerIdx, out int playerHandle);
            GET_CHAR_COORDINATES(playerHandle, out Vector3 playerPos);

            // Throttle: não executar efeito a cada frame
            int now = Environment.TickCount;
            if (now - _lastEffectTick >= EFFECT_COOLDOWN_MS)
            {
                string effect = null;
                lock (_lock)
                {
                    if (!string.IsNullOrEmpty(_pending))
                    {
                        effect   = _pending;
                        _pending = "";
                    }
                }
                if (effect != null)
                {
                    ExecuteEffect(effect, playerHandle, playerIdx, playerPos);
                    _lastEffectTick = now;
                }
            }

            // Turbo contínuo (roda sempre, independente de chat)
            ApplyTurboToNPCVehicles(playerHandle, playerPos);
        }

        // ============================================================
        //  DISPATCHER DE EFEITOS
        // ============================================================
        private void ExecuteEffect(string effect, int playerHandle, int playerIdx, Vector3 playerPos)
        {
            switch (effect.ToLower())
            {
                case "turbo":
                    ApplyTurboToNPCVehicles(playerHandle, playerPos);
                    break;

                case "explode_player":
                    ADD_EXPLOSION(playerPos.X, playerPos.Y, playerPos.Z,
                        (int)eExplosion.EXPLOSION_ROCKET, 10.0f, true, false, 0.5f);
                    SET_CHAR_HEALTH(playerHandle, 0);
                    break;

                case "elevate_peds":
                    ElevatePeds(playerHandle, playerPos);
                    break;

                case "wanted_up":
                    STORE_WANTED_LEVEL(playerIdx, out uint curWanted);
                    ALTER_WANTED_LEVEL(playerIdx, (uint)Math.Min((int)curWanted + 1, 6));
                    APPLY_WANTED_LEVEL_CHANGE_NOW(playerIdx);
                    break;

                case "wanted_clear":
                    ALTER_WANTED_LEVEL(playerIdx, 0u);
                    APPLY_WANTED_LEVEL_CHANGE_NOW(playerIdx);
                    break;

                case "heal_player":
                    SET_CHAR_HEALTH(playerHandle, 200);
                    break;

                case "ragdoll_peds":
                    RagdollNearbyPeds(playerHandle, playerPos);
                    break;

                case "explode_cars":
                    ExplodeNPCCars(playerHandle, playerPos);
                    break;

                case "give_weapon":
                    GiveRandomWeapon(playerHandle);
                    break;

                // Adicione novos efeitos aqui seguindo o mesmo padrão
                default:
                    break;
            }
        }

        // ============================================================
        //  EFEITOS
        // ============================================================

        private void ApplyTurboToNPCVehicles(int playerHandle, Vector3 playerPos)
        {
            int  playerCarHandle = 0;
            bool inVehicle       = IS_CHAR_IN_ANY_CAR(playerHandle);
            if (inVehicle)
                GET_CAR_CHAR_IS_USING(playerHandle, out playerCarHandle);

            IVPool pool = IVPools.GetVehiclePool();
            for (int i = 0; i < pool.Count; i++)
            {
                UIntPtr ptr = pool.Get(i);
                if (ptr == UIntPtr.Zero) continue;

                int handle = (int)pool.GetIndex(ptr);
                if (inVehicle && handle == playerCarHandle) continue;

                // Precisa ter motorista NPC
                GET_DRIVER_OF_CAR(handle, out int driverHandle);
                if (driverHandle == 0 || driverHandle == playerHandle) continue;

                // Filtrar por distância
                GET_CAR_COORDINATES(handle, out Vector3 carPos);
                if (Vector3.Distance(playerPos, carPos) > TURBO_RADIUS) continue;

                // Calcular vetor frontal via offset nativo
                GET_OFFSET_FROM_CAR_IN_WORLD_COORDS(handle, new Vector3(0f, 1f, 0f), out Vector3 fwdPoint);
                Vector3 forward = Vector3.Normalize(fwdPoint - carPos);
                Vector3 boost   = forward * TURBO_POWER;

                SET_CAR_FORWARD_SPEED(handle, TURBO_POWER);
            }
        }

        private void ElevatePeds(int playerHandle, Vector3 playerPos)
        {
            // Eleva o próprio player
            SET_CHAR_COORDINATES(playerHandle,
                new Vector3(playerPos.X, playerPos.Y, playerPos.Z + 3.0f));

            UIntPtr playerPedPtr = IVPlayerInfo.FindThePlayerPed();
            IVPool  pool         = IVPools.GetPedPool();
            for (int i = 0; i < pool.Count; i++)
            {
                UIntPtr ptr = pool.Get(i);
                if (ptr == UIntPtr.Zero || ptr == playerPedPtr) continue;

                int pedHandle = (int)pool.GetIndex(ptr);
                if (IS_CHAR_DEAD(pedHandle)) continue;

                GET_CHAR_COORDINATES(pedHandle, out Vector3 pedPos);
                if (Vector3.Distance(playerPos, pedPos) > TURBO_RADIUS) continue;

                SET_CHAR_COORDINATES(pedHandle,
                    new Vector3(pedPos.X, pedPos.Y, pedPos.Z + 3.0f));
            }
        }

        private void RagdollNearbyPeds(int playerHandle, Vector3 playerPos)
        {
            UIntPtr playerPedPtr = IVPlayerInfo.FindThePlayerPed();
            IVPool  pool         = IVPools.GetPedPool();
            for (int i = 0; i < pool.Count; i++)
            {
                UIntPtr ptr = pool.Get(i);
                if (ptr == UIntPtr.Zero || ptr == playerPedPtr) continue;

                int pedHandle = (int)pool.GetIndex(ptr);
                if (IS_CHAR_DEAD(pedHandle)) continue;

                GET_CHAR_COORDINATES(pedHandle, out Vector3 pedPos);
                if (Vector3.Distance(playerPos, pedPos) > TURBO_RADIUS) continue;

                SWITCH_PED_TO_RAGDOLL(pedHandle, 3000, 3000, false, true, true, false);
            }
        }

        private void ExplodeNPCCars(int playerHandle, Vector3 playerPos)
        {
            int  playerCarHandle = 0;
            bool inVehicle       = IS_CHAR_IN_ANY_CAR(playerHandle);
            if (inVehicle)
                GET_CAR_CHAR_IS_USING(playerHandle, out playerCarHandle);

            IVPool pool = IVPools.GetVehiclePool();
            for (int i = 0; i < pool.Count; i++)
            {
                UIntPtr ptr = pool.Get(i);
                if (ptr == UIntPtr.Zero) continue;

                int handle = (int)pool.GetIndex(ptr);
                if (inVehicle && handle == playerCarHandle) continue;

                GET_CAR_COORDINATES(handle, out Vector3 carPos);
                if (Vector3.Distance(playerPos, carPos) > TURBO_RADIUS) continue;

                ADD_EXPLOSION(carPos.X, carPos.Y, carPos.Z,
                    (int)eExplosion.EXPLOSION_CAR, 5.0f, true, false, 0.5f);
            }
        }

        private void GiveRandomWeapon(int playerHandle)
        {
            int[] weapons =
            {
                (int)eWeaponType.WEAPON_SHOTGUN,
                (int)eWeaponType.WEAPON_M4,
                (int)eWeaponType.WEAPON_SNIPERRIFLE,
                (int)eWeaponType.WEAPON_RLAUNCHER,
            };
            int weapon = weapons[new Random().Next(weapons.Length)];
            GIVE_WEAPON_TO_CHAR(playerHandle, weapon, 100, true);
        }
    }
}
