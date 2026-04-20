// Effect ID constants — SCREAMING_SNAKE_CASE, matching the Go server's config.toml pool.
// Keep this file in sync with server/config.toml [effects] pool.
namespace LiveChaos {
    internal static class Effects {
        public const string SpawnTanks    = "SPAWN_TANKS";
        public const string BlowAll       = "BLOW_ALL";
        public const string RandomPed     = "RANDOM_PED";
        public const string WantedMax     = "WANTED_MAX";
        public const string FlipCars      = "FLIP_CARS";
        public const string ExplodePlayer = "EXPLODE_PLAYER";
        public const string ElevatePeds   = "ELEVATE_PEDS";
        public const string WantedUp      = "WANTED_UP";
        public const string WantedClear   = "WANTED_CLEAR";
        public const string HealPlayer    = "HEAL_PLAYER";
        public const string RagdollPeds   = "RAGDOLL_PEDS";
        public const string ExplodeCars   = "EXPLODE_CARS";
        public const string GiveWeapon    = "GIVE_WEAPON";
    }
}
