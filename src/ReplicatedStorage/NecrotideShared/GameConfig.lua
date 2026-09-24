-- GameConfig: every tuning number for NECROTIDE: LAST STAND lives here.
-- Safe to edit in Studio while the game is stopped; nothing else hardcodes balance.

local GameConfig = {}

GameConfig.GameName = "NECROTIDE: LAST STAND"
GameConfig.Tagline = "Hold the Ashvault until the Hollow Choir stops singing."

-- Economy -------------------------------------------------------------------
GameConfig.StartingSalvage = 500
GameConfig.SalvagePerHit = 10
GameConfig.SalvagePerKill = 60
GameConfig.SalvagePerHeadshotKill = 90
GameConfig.SalvagePerBoardRepair = 12
GameConfig.SalvagePerRevive = 150
GameConfig.WaveClearBonus = 100 -- multiplied by the wave number

-- Rounds --------------------------------------------------------------------
GameConfig.IntermissionFirst = 18 -- seconds before wave 1
GameConfig.IntermissionBetween = 14 -- seconds between waves
GameConfig.FinalBossWave = 20
GameConfig.BossWaveInterval = 5 -- a mini-boss spawns every N waves
GameConfig.EndlessAfterVictory = true
GameConfig.MaxAliveEnemies = 26
GameConfig.SpawnInterval = 1.05 -- seconds between spawn attempts
GameConfig.RestartDelay = 12 -- seconds after a squad wipe before the run resets

-- Enemy scaling -------------------------------------------------------------
GameConfig.EnemyBaseCount = 10
GameConfig.EnemyCountPerWave = 5
GameConfig.EnemyCountPerExtraPlayer = 0.45 -- extra fraction of the wave per extra player
GameConfig.EnemyCountCap = 80
GameConfig.HealthLinearPerWave = 0.24 -- +24% of base health per wave, early waves
GameConfig.HealthExponentialWave = 10 -- after this wave health compounds instead
GameConfig.HealthExponentialRate = 1.11
GameConfig.SpeedPerWave = 0.35
GameConfig.MaxEnemySpeed = 21

-- Players -------------------------------------------------------------------
GameConfig.BaseMaxHealth = 100
GameConfig.RegenDelay = 5 -- seconds out of combat before health regenerates
GameConfig.RegenRate = 12 -- health per second
GameConfig.BleedOutTime = 32 -- seconds downed before you are out for the wave
GameConfig.ReviveTime = 3.5 -- seconds of holding the revive prompt

-- Stations ------------------------------------------------------------------
GameConfig.CrateBaseCost = 950
GameConfig.CrateRelocateChance = 0.11 -- chance the Hollow Doll appears and moves the crate
GameConfig.CrateForcedMoveUses = 9 -- guaranteed relocate after this many pulls
GameConfig.CrateSpinTime = 3.6
GameConfig.ForgeCost = 5000
GameConfig.ForgeTime = 4.0
GameConfig.AmmoRefillCostRatio = 0.5 -- wall ammo costs half the weapon price

-- Powerups ------------------------------------------------------------------
GameConfig.PowerupDropChance = 0.035
GameConfig.PowerupLifetime = 22
GameConfig.PowerupMaxPerWave = 4

-- Barriers ------------------------------------------------------------------
GameConfig.BoardsPerBarrier = 5
GameConfig.BoardTearTime = 1.35 -- seconds an enemy needs per board
GameConfig.BoardRepairTime = 0.7 -- prompt hold time per board

-- Misc ----------------------------------------------------------------------
GameConfig.EnemyAttackRange = 6.5
GameConfig.EnemyAttackCooldown = 1.15
GameConfig.MaxWeaponSlots = 2
GameConfig.DebugLogging = false

return GameConfig
