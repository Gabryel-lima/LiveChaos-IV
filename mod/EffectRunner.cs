// EffectRunner.cs — dispatches incoming effect IDs to game-native implementations.
// Called once per Tick from the game thread.
// Each RunXxx() method is self-contained and does not share state with others.

using System;
using System.Numerics;
using IVSDKDotNet;
using IVSDKDotNet.Enums;
using static IVSDKDotNet.Native.Natives;

namespace LiveChaos {
    internal class EffectRunner {
        private const float AOE_RADIUS   = 120.0f;
        private const float TURBO_POWER  = 70.0f;

        /// <summary>
        /// Dequeues one pending effect and executes it.
        /// Must be called from the game Tick handler.
        /// </summary>
        public void Tick(int playerHandle, int playerIdx, Vector3 playerPos) {
            string effect = PipeClient.DequeueEffect();
            if (effect == null) return;
            Dispatch(effect, playerHandle, playerIdx, playerPos);
        }

        private void Dispatch(string effect, int playerHandle, int playerIdx, Vector3 playerPos) {
            switch (effect) {
                case Effects.SpawnTanks:    RunSpawnTanks(playerPos);                            break;
                case Effects.BlowAll:       RunExplodeCars(playerHandle, playerPos);             break;
                case Effects.RandomPed:     RunRandomPed(playerPos);                             break;
                case Effects.WantedMax:     RunSetWanted(playerIdx, 6);                          break;
                case Effects.FlipCars:      RunFlipCars(playerHandle, playerPos);                break;
                case Effects.ExplodePlayer: RunExplodePlayer(playerHandle, playerPos);           break;
                case Effects.ElevatePeds:   RunElevatePeds(playerHandle, playerPos);             break;
                case Effects.WantedUp:      RunWantedUp(playerIdx);                              break;
                case Effects.WantedClear:   RunSetWanted(playerIdx, 0);                          break;
                case Effects.HealPlayer:    SET_CHAR_HEALTH(playerHandle, 200);                  break;
                case Effects.RagdollPeds:   RunRagdollPeds(playerHandle, playerPos);             break;
                case Effects.ExplodeCars:   RunExplodeCars(playerHandle, playerPos);             break;
                case Effects.GiveWeapon:    RunGiveRandomWeapon(playerHandle);                   break;
                default:
                    IVSDKDotNet.IVGame.Console.Print($"[EffectRunner] unknown effect: {effect}");
                    break;
            }
        }

        // ── Effect implementations ────────────────────────────────────────────

        private void RunSpawnTanks(Vector3 playerPos) {
            // Spawns a Rhino near the player.
            // Model hash for Rhino is 0x6D6F1DC8; adjust if needed.
            const int RHINO = unchecked((int)0x6D6F1DC8);
            REQUEST_MODEL(RHINO);
            Vector3 spawnPos = new Vector3(playerPos.X + 8f, playerPos.Y, playerPos.Z);
            CREATE_CAR(RHINO, spawnPos.X, spawnPos.Y, spawnPos.Z, out int _, true);
        }

        private void RunRandomPed(Vector3 playerPos) {
            // Spawns a random hostile ped near the player.
            const int PED_MODEL = unchecked((int)0xF6C4AA6); // generic male ped
            REQUEST_MODEL(PED_MODEL);
            Vector3 spawnPos = new Vector3(playerPos.X + 5f, playerPos.Y + 5f, playerPos.Z);
            CREATE_CHAR(1, PED_MODEL, spawnPos.X, spawnPos.Y, spawnPos.Z, out int pedHandle, false);
            SET_CHAR_RELATIONSHIP(pedHandle, 5, 0); // Hate player
        }

        private void RunExplodePlayer(int playerHandle, Vector3 playerPos) {
            ADD_EXPLOSION(playerPos.X, playerPos.Y, playerPos.Z,
                (int)eExplosion.EXPLOSION_ROCKET, 10.0f, true, false, 0.5f);
            SET_CHAR_HEALTH(playerHandle, 0);
        }

        private void RunElevatePeds(int playerHandle, Vector3 playerPos) {
            SET_CHAR_COORDINATES(playerHandle,
                new Vector3(playerPos.X, playerPos.Y, playerPos.Z + 3.0f));

            UIntPtr playerPedPtr = IVPlayerInfo.FindThePlayerPed();
            IVPool pool = IVPools.GetPedPool();
            for (int i = 0; i < pool.Count; i++) {
                UIntPtr ptr = pool.Get(i);
                if (ptr == UIntPtr.Zero || ptr == playerPedPtr) continue;
                int ped = (int)pool.GetIndex(ptr);
                if (IS_CHAR_DEAD(ped)) continue;
                GET_CHAR_COORDINATES(ped, out Vector3 pedPos);
                if (Vector3.Distance(playerPos, pedPos) > AOE_RADIUS) continue;
                SET_CHAR_COORDINATES(ped, new Vector3(pedPos.X, pedPos.Y, pedPos.Z + 3.0f));
            }
        }

        private void RunWantedUp(int playerIdx) {
            STORE_WANTED_LEVEL(playerIdx, out uint cur);
            ALTER_WANTED_LEVEL(playerIdx, (uint)Math.Min((int)cur + 1, 6));
            APPLY_WANTED_LEVEL_CHANGE_NOW(playerIdx);
        }

        private void RunSetWanted(int playerIdx, uint level) {
            ALTER_WANTED_LEVEL(playerIdx, level);
            APPLY_WANTED_LEVEL_CHANGE_NOW(playerIdx);
        }

        private void RunRagdollPeds(int playerHandle, Vector3 playerPos) {
            UIntPtr playerPedPtr = IVPlayerInfo.FindThePlayerPed();
            IVPool pool = IVPools.GetPedPool();
            for (int i = 0; i < pool.Count; i++) {
                UIntPtr ptr = pool.Get(i);
                if (ptr == UIntPtr.Zero || ptr == playerPedPtr) continue;
                int ped = (int)pool.GetIndex(ptr);
                if (IS_CHAR_DEAD(ped)) continue;
                GET_CHAR_COORDINATES(ped, out Vector3 pedPos);
                if (Vector3.Distance(playerPos, pedPos) > AOE_RADIUS) continue;
                SWITCH_PED_TO_RAGDOLL(ped, 3000, 3000, false, true, true, false);
            }
        }

        private void RunExplodeCars(int playerHandle, Vector3 playerPos) {
            int playerCar = 0;
            bool inVehicle = IS_CHAR_IN_ANY_CAR(playerHandle);
            if (inVehicle) GET_CAR_CHAR_IS_USING(playerHandle, out playerCar);

            IVPool pool = IVPools.GetVehiclePool();
            for (int i = 0; i < pool.Count; i++) {
                UIntPtr ptr = pool.Get(i);
                if (ptr == UIntPtr.Zero) continue;
                int car = (int)pool.GetIndex(ptr);
                if (inVehicle && car == playerCar) continue;
                GET_CAR_COORDINATES(car, out Vector3 carPos);
                if (Vector3.Distance(playerPos, carPos) > AOE_RADIUS) continue;
                ADD_EXPLOSION(carPos.X, carPos.Y, carPos.Z,
                    (int)eExplosion.EXPLOSION_CAR, 5.0f, true, false, 0.5f);
            }
        }

        private void RunFlipCars(int playerHandle, Vector3 playerPos) {
            int playerCar = 0;
            bool inVehicle = IS_CHAR_IN_ANY_CAR(playerHandle);
            if (inVehicle) GET_CAR_CHAR_IS_USING(playerHandle, out playerCar);

            IVPool pool = IVPools.GetVehiclePool();
            for (int i = 0; i < pool.Count; i++) {
                UIntPtr ptr = pool.Get(i);
                if (ptr == UIntPtr.Zero) continue;
                int car = (int)pool.GetIndex(ptr);
                if (inVehicle && car == playerCar) continue;
                GET_CAR_COORDINATES(car, out Vector3 carPos);
                if (Vector3.Distance(playerPos, carPos) > AOE_RADIUS) continue;
                // Flip by applying an upward force to the car
                APPLY_FORCE_TO_CAR(car, 3, 0f, 0f, 8.0f, 0f, 0f, 0f, 0, 1, 1, 1);
            }
        }

        private void RunGiveRandomWeapon(int playerHandle) {
            int[] weapons = {
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
