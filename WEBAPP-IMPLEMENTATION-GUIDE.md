# 🏜️ MERC MANIA WEBAPP IMPLEMENTATION GUIDE

_Strategic Mercenary Mining Operations - Web3 Interface_

## 📖 Table of Contents

1. [Game Overview](#game-overview)
2. [Technology Stack & Setup](#technology-stack--setup)
3. [Smart Contract Architecture](#smart-contract-architecture)
4. [Contract Methods Reference](#contract-methods-reference)
5. [User Interface Design](#user-interface-design)
6. [Single Page App Architecture](#single-page-app-architecture)
7. [Themed Naming System](#themed-naming-system)
8. [Data Aggregation Contract](#data-aggregation-contract)
9. [Performance Optimization](#performance-optimization)
10. [Error Handling & Edge Cases](#error-handling--edge-cases)
11. [Live Updates & Notifications](#live-updates--notifications)
12. [Implementation Roadmap](#implementation-roadmap)

---

## 🎮 Game Overview

**Merc Mania** is a strategic blockchain game set in a dystopian future where mercenary companies compete for control of resource extraction sites across Africa. The game features:

- **Dynamic Resource Management**: Unlimited resource types (starting with Gold, Iron, Copper, Tantalum, Lithium, Uranium) - AI continuously adds new resources to keep the game fresh
- **Mercenary Combat**: Unlimited mercenary levels with unique artwork and increasing power requirements
- **Mine Control**: Capturable resource-producing facilities with diminishing returns
- **Economic Warfare**: Strategic resource allocation and territorial expansion
- **Rich Metadata**: Each resource and mercenary has unique PNG artwork, names, and symbols

### Core Game Loop

1. **Deposit Resources** → Secure assets in GameMaster escrow
2. **Recruit Mercenaries** → Convert resources into combat units
3. **Seize Mines** → Attack unowned or enemy-controlled extraction sites
4. **Claim Resources** → Harvest accumulated production from controlled mines
5. **Defend Territory** → Use Gold to boost defensive capabilities

---

## 🛠️ Technology Stack & Setup

### Recommended Framework

```bash
# Create Next.js 14+ project with TypeScript
npx create-next-app@latest merc-mania-webapp --typescript --tailwind --app

cd merc-mania-webapp

# Install Web3 dependencies
npm install wagmi viem @tanstack/react-query connectkit

# Install UI dependencies
npm install @radix-ui/react-dialog @radix-ui/react-tabs @radix-ui/react-tooltip
npm install @radix-ui/react-dropdown-menu @radix-ui/react-separator
npm install class-variance-authority clsx tailwind-merge lucide-react

# Install state management
npm install zustand

# Install utilities
npm install date-fns recharts framer-motion

# Development dependencies
npm install -D @types/node @types/react @types/react-dom eslint
```

### Project Structure

```
merc-mania-webapp/
├── src/
│   ├── app/
│   │   ├── layout.tsx           # Root layout with Web3 providers
│   │   └── page.tsx             # Main game interface
│   ├── components/
│   │   ├── ui/                  # shadcn/ui components
│   │   ├── game/                # Game-specific components
│   │   │   ├── MineMap.tsx      # Interactive mine grid
│   │   │   ├── PlayerDashboard.tsx # Resource/merc overview
│   │   │   ├── MercRecruitment.tsx # Mercenary recruitment UI
│   │   │   ├── BattleModal.tsx  # Combat interface
│   │   │   └── ResourceManager.tsx # Deposit/withdraw interface
│   │   └── providers/           # Web3 and state providers
│   ├── hooks/                   # Custom wagmi hooks
│   ├── lib/
│   │   ├── contracts.ts         # Contract addresses and ABIs
│   │   ├── utils.ts             # Utility functions
│   │   ├── naming.ts            # Themed naming system
│   │   └── store.ts             # Zustand store
│   └── types/                   # TypeScript type definitions
└── public/
    ├── assets/                  # Game assets (icons, sounds)
    └── metadata/                # Token metadata
```

---

## 🏗️ Smart Contract Architecture

### Core Contracts

#### 1. **GameMaster** - Central Asset Management

- **Purpose**: Secure escrow for all game tokens with 50% withdrawal penalty
- **Key Features**: Deposit/withdraw mechanics, balance management, authorization system

#### 2. **ResourceManager** - Resource Registry

- **Purpose**: Manages all valid game resources and enforces Gold requirement
- **Key Features**: Resource enumeration, validation, Gold token reference

#### 3. **MercRecruiter** - Mercenary Recruitment

- **Purpose**: Converts resource combinations into mercenary units
- **Key Features**: Level-based recruitment (resources used = merc level)

#### 4. **Mine** - Resource Production Sites

- **Purpose**: Capturable facilities that produce resources over time
- **Key Features**: Combat system, production decay, defense boosts

#### 5. **MineFactory** - Mine Deployment

- **Purpose**: Creates and tracks all mines in the game
- **Key Features**: Mine enumeration, resource-based filtering

#### 6. **MercAssetFactory** - Mercenary Token Creation

- **Purpose**: Creates and manages leveled mercenary tokens
- **Key Features**: Level-based token system, mercenary enumeration

#### 7. **GameAssetFactory** - Resource Token Creation

- **Purpose**: Creates standardized resource tokens
- **Key Features**: Token standardization, minting permissions

#### 8. **PlayerStats** - Individual Player Analytics

- **Purpose**: Tracks comprehensive statistics for each player
- **Key Features**: Deposit/withdrawal tracking, recruitment stats, combat history, mine management metrics

#### 9. **GameStats** - Global Game Analytics

- **Purpose**: Tracks game-wide statistics and aggregated data
- **Key Features**: Global token flows, total recruitment, combat statistics, activity metrics

---

## 📋 Contract Methods Reference

### GameMaster Methods

#### View Methods

```typescript
// Get player's balance of a specific token
getBalance(user: address, token: IERC20) -> uint256

// Check multiple balances efficiently (use multicall)
// Combine multiple getBalance calls
```

#### Write Methods

```typescript
// Deposit tokens into game escrow
deposit(token: IERC20, amount: uint256)

// Withdraw tokens with 50% burn penalty
withdraw(token: IERC20, amount: uint256)
```

### ResourceManager Methods

#### View Methods

```typescript
// Get all valid game resources
getAllResources() -> IERC20[]

// Get specific resource by index
getResourceAt(index: uint256) -> IERC20

// Get total resource count
getResourceCount() -> uint256

// Get Gold token address
GOLD() -> IERC20

// Check if token is valid resource
isResource(resource: IERC20) -> bool
```

### MercRecruiter Methods

#### View Methods

```typescript
// Check if player can recruit mercenaries
canRecruitMercs(player: address, resources: IERC20[], amount: uint256) -> bool

// Get mercenary level for resource combination
getRequiredLevel(resources: IERC20[]) -> uint256
```

#### Write Methods

```typescript
// Recruit mercenaries using resources
recruitMercs(resources: IERC20[], amount: uint256)
```

### Mine Methods

#### View Methods

```typescript
// Get comprehensive mine information
getMineInfo() -> MineInfo{
  resource: IERC20,
  owner: address,
  lastSeized: uint256,
  createdAt: uint256,
  defenseBoostExpiry: uint256,
  initialProductionPerDay: uint256,
  halvingPeriod: uint256
}

// Get current production rate
getCurrentProduction() -> uint256

// Get accumulated unclaimed resources
getAccumulatedResources() -> uint256

// Calculate battle power for specific mercenary deployment
calculateBattlePower(mercLevel: uint256, mercAmount: uint256, isDefending: bool) -> uint256

// Get battle history
getBattleLogCount() -> uint256
getBattleLogEntry(index: uint256) -> BattleLogEntry
getBattleLogEntries(startIndex: uint256, count: uint256) -> BattleLogEntry[]
```

#### Write Methods

```typescript
// Attack mine with mercenaries
seize(mercLevel: uint256)

// Abandon controlled mine (10% mercenary loss)
abandon()

// Collect accumulated resources
claimResources()

// Activate 8-hour defense boost (costs Gold)
activateDefenseBoost()
```

### MineFactory Methods

#### View Methods

```typescript
// Get all deployed mines
getAllMines() -> address[]

// Get mines producing specific resource
getMinesForResource(resource: IERC20) -> address[]

// Get total mine count
getMineCount() -> uint256

// Get paginated mines (newest first)
getMines(startIndex: uint256, count: uint256) -> address[]
```

### MercAssetFactory Methods

#### View Methods

```typescript
// Get mercenary token for specific level
getMercByLevel(level: uint256) -> address

// Get all mercenary tokens
getAllMercs() -> address[]

// Get total mercenary levels created
getMercCount() -> uint256

// Get highest available mercenary level
highestLevel() -> uint256
```

### PlayerStats Methods

#### View Methods

```typescript
// Get deposit statistics
getTotalDeposited(player: address, token: IERC20) -> uint256
getDepositCount(player: address) -> uint256

// Get withdrawal statistics
getTotalWithdrawn(player: address, token: IERC20) -> uint256
getTotalBurned(player: address, token: IERC20) -> uint256
getWithdrawalCount(player: address) -> uint256

// Get recruitment statistics
getMercsRecruitedByLevel(player: address, level: uint256) -> uint256
getTotalMercsRecruited(player: address) -> uint256
getRecruitmentCount(player: address) -> uint256

// Get combat statistics
getSeizeStats(player: address) -> (uint256 total, uint256 successful, uint256 failed)
getMinesSeizedFrom(player: address, previousOwner: address) -> uint256
getCombatPowerStats(player: address) -> (uint256 attackPower, uint256 defensePower)
getCombatMercStats(player: address) -> (uint256 lost, uint256 won)

// Get mine management statistics
getMinesAbandoned(player: address) -> uint256
getResourcesClaimed(player: address, resource: IERC20) -> uint256
getClaimCount(player: address) -> uint256
getDefenseBoostsActivated(player: address) -> uint256

// Get player enumeration
getPlayerCount() -> uint256
getPlayers(startIndex: uint256, count: uint256) -> address[]
```

### GameStats Methods

#### View Methods

```typescript
// Get global deposit/withdrawal statistics
getTotalDeposited(token: IERC20) -> uint256
getTotalWithdrawn(token: IERC20) -> uint256
getTotalBurned(token: IERC20) -> uint256
getTotalDepositTransactions() -> uint256
getTotalWithdrawalTransactions() -> uint256
getUniqueDepositors() -> uint256

// Get global recruitment statistics
getTotalMercsRecruitedByLevel(level: uint256) -> uint256
getTotalMercsRecruited() -> uint256
getTotalRecruitmentTransactions() -> uint256
getUniqueRecruiters() -> uint256

// Get global combat statistics
getGlobalSeizeStats() -> (uint256 total, uint256 successful, uint256 failed)
getTotalCombatPowerUsed() -> uint256
getTotalMercsLostInCombat() -> uint256

// Get global mine management statistics
getTotalMinesAbandoned() -> uint256
getTotalResourcesClaimed(resource: IERC20) -> uint256
getTotalClaimTransactions() -> uint256
getTotalDefenseBoostsActivated() -> uint256

// Get activity metrics
getTotalUniqueParticipants() -> uint256
getActivityTimeline() -> (uint256 firstActivity, uint256 lastActivity)
hasParticipated(participant: address) -> bool

// Get comprehensive overview
getGameOverview() -> (
  uint256 totalParticipants,
  uint256 totalDeposits,
  uint256 totalWithdrawals,
  uint256 totalMercs,
  uint256 totalSeizes,
  uint256 totalClaims,
  uint256 firstActivity,
  uint256 lastActivity
)
```

---

## 🎨 User Interface Design

### Theme & Aesthetics

#### Color Palette

```css
/* Primary - Military/Industrial */
--primary: 34 197 94; /* Green - Atlas Helix */
--secondary: 245 158 11; /* Amber - Gold/Resources */
--accent: 239 68 68; /* Red - Combat/Danger */

/* Neutral - Dark theme base */
--background: 9 9 11; /* Near black */
--surface: 24 24 27; /* Dark gray */
--muted: 63 63 70; /* Mid gray */

/* Resource Colors */
--gold: 245 158 11; /* Amber */
--iron: 113 113 122; /* Gray */
--copper: 194 65 12; /* Orange */
--tantalum: 139 69 19; /* Brown */
--lithium: 239 68 68; /* Red */
--uranium: 34 197 94; /* Green */
```

#### Typography

```css
/* Headers - Military stencil style */
@import url("https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700;900&display=swap");

/* Body - Technical/readable */
@import url("https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap");

.font-military {
  font-family: "Orbitron", monospace;
}
.font-body {
  font-family: "Inter", sans-serif;
}
```

### Core Components

#### 1. **PlayerDashboard** - Central HUD

```typescript
interface PlayerStats {
  address: string;
  themedName: string;
  resourceBalances: ResourceBalance[]; // Token + balance only
  mercenaryUnits: MercenaryBalance[]; // Token + balance + level only
  controlledMines: MineSnapshot[];
  totalNetWorth: bigint;
}

// Resource display component that fetches metadata separately
export function ResourceCard({ resource }: { resource: ResourceBalance }) {
  const { data: resourceMetadata } = useResourceMetadata();

  const metadata = resourceMetadata?.[resource.token] || {
    name: "Unknown Resource",
    symbol: "???",
    tokenUri: "",
  };

  return (
    <Card className="p-4">
      <div className="flex items-center space-x-3">
        <div className="w-10 h-10 rounded-lg overflow-hidden bg-muted">
          {metadata.tokenUri ? (
            <img
              src={metadata.tokenUri}
              alt={metadata.name}
              className="w-full h-full object-cover"
              onError={(e) => {
                e.currentTarget.src = "/assets/placeholder-resource.png";
              }}
            />
          ) : (
            <div className="w-full h-full flex items-center justify-center text-xs font-medium">
              {metadata.symbol}
            </div>
          )}
        </div>
        <div className="flex-1">
          <h3 className="font-medium text-sm">{metadata.name}</h3>
          <p className="text-muted-foreground text-xs">{metadata.symbol}</p>
        </div>
        <div className="text-right">
          <p className="font-mono text-sm">{formatEther(resource.balance)}</p>
        </div>
      </div>
    </Card>
  );
}

// Mercenary unit display that fetches metadata separately
export function MercenaryCard({ mercenary }: { mercenary: MercenaryBalance }) {
  const { data: mercenaryMetadata } = useMercenaryMetadata();

  const metadata = mercenaryMetadata?.[mercenary.token] || {
    name: "Unknown Mercenary",
    symbol: "???",
    tokenUri: "",
    level: mercenary.level,
  };

  return (
    <Card className="p-4">
      <div className="flex items-center space-x-3">
        <div className="w-12 h-12 rounded-lg overflow-hidden bg-muted">
          {metadata.tokenUri ? (
            <img
              src={metadata.tokenUri}
              alt={metadata.name}
              className="w-full h-full object-cover"
              onError={(e) => {
                e.currentTarget.src = "/assets/placeholder-merc.png";
              }}
            />
          ) : (
            <div className="w-full h-full flex items-center justify-center text-xs font-medium">
              L{metadata.level}
            </div>
          )}
        </div>
        <div className="flex-1">
          <div className="flex items-center space-x-2">
            <h3 className="font-medium text-sm">{metadata.name}</h3>
            <Badge variant="secondary" className="text-xs">
              Level {metadata.level}
            </Badge>
          </div>
          <p className="text-muted-foreground text-xs">
            {metadata.symbol} • {mercenary.powerPerUnit} power/unit
          </p>
        </div>
        <div className="text-right">
          <p className="font-mono text-sm">{mercenary.balance.toString()}</p>
          <p className="text-xs text-muted-foreground">
            {(
              Number(mercenary.balance) * mercenary.powerPerUnit
            ).toLocaleString()}{" "}
            total power
          </p>
        </div>
      </div>
    </Card>
  );
}
```

#### 2. **MineMap** - Strategic Overview

```typescript
interface MineDisplayData {
  address: string;
  resource: IERC20;
  owner: string | null;
  currentProduction: bigint;
  accumulatedResources: bigint;
  defenseBoostActive: boolean;
  lastBattle?: BattleLogEntry;
}
```

#### 3. **BattleInterface** - Combat Modal

```typescript
interface BattlePreview {
  attackerPower: bigint;
  defenderPower: bigint;
  winProbability: number;
  potentialLosses: bigint;
  estimatedCosts: Map<IERC20, bigint>;
}
```

#### 4. **MercenaryRecruitment** - Force Building

```typescript
interface RecruitmentOption {
  level: number;
  resourceRequirements: IERC20[];
  availableAmount: bigint;
  powerPerUnit: bigint;
  description: string;
}
```

#### 5. **PlayerStatsPanel** - Individual Analytics

```typescript
interface PlayerStatistics {
  // Token Management
  depositStats: {
    totalByToken: Map<IERC20, bigint>;
    transactionCount: number;
  };
  withdrawalStats: {
    totalByToken: Map<IERC20, bigint>;
    totalBurnedByToken: Map<IERC20, bigint>;
    transactionCount: number;
  };

  // Combat Analytics
  combatStats: {
    totalSeizeAttempts: number;
    successfulSeizes: number;
    failedSeizes: number;
    winRate: number;
    totalPowerUsed: bigint;
    mercsLost: number;
    mercsWon: number;
  };

  // Mine Management
  mineStats: {
    minesAbandoned: number;
    resourcesClaimedByToken: Map<IERC20, bigint>;
    claimCount: number;
    defenseBoostsActivated: number;
  };

  // Recruitment Analytics
  recruitmentStats: {
    totalMercsRecruited: number;
    mercsByLevel: Map<number, number>;
    recruitmentTransactions: number;
  };
}

export function PlayerStatsPanel({ playerAddress }: { playerAddress: string }) {
  const { data: playerStats } = usePlayerStats(playerAddress);

  return (
    <Card className="p-6">
      <CardHeader>
        <CardTitle className="flex items-center space-x-2">
          <BarChart3 className="h-5 w-5" />
          <span>Player Analytics</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Combat Performance */}
        <div>
          <h3 className="font-medium mb-3">Combat Performance</h3>
          <div className="grid grid-cols-2 gap-4">
            <StatsCard
              label="Win Rate"
              value={`${playerStats?.combatStats.winRate}%`}
              icon={<Target />}
            />
            <StatsCard
              label="Battles Fought"
              value={playerStats?.combatStats.totalSeizeAttempts}
              icon={<Swords />}
            />
          </div>
        </div>

        {/* Resource Management */}
        <div>
          <h3 className="font-medium mb-3">Resource Management</h3>
          <ResourceFlowChart
            deposits={playerStats?.depositStats.totalByToken}
            withdrawals={playerStats?.withdrawalStats.totalByToken}
          />
        </div>

        {/* Mine Operations */}
        <div>
          <h3 className="font-medium mb-3">Mine Operations</h3>
          <div className="grid grid-cols-3 gap-2">
            <StatsCard
              label="Claims"
              value={playerStats?.mineStats.claimCount}
              icon={<Coins />}
            />
            <StatsCard
              label="Abandoned"
              value={playerStats?.mineStats.minesAbandoned}
              icon={<XCircle />}
            />
            <StatsCard
              label="Defenses"
              value={playerStats?.mineStats.defenseBoostsActivated}
              icon={<Shield />}
            />
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
```

#### 6. **BasicAnalyticsPanel** - Simple Game Statistics

```typescript
interface BasicGameStats {
  totalParticipants: number;
  totalDeposits: number;
  totalWithdrawals: number;
  totalMercsRecruited: number;
  totalSeizeAttempts: number;
  totalClaims: number;
  gameAge: number; // days since first activity
}

export function BasicAnalyticsPanel() {
  const { data: gameStats } = useGameStats();

  return (
    <Card className="p-6">
      <CardHeader>
        <CardTitle className="flex items-center space-x-2">
          <BarChart3 className="h-5 w-5" />
          <span>Game Overview</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Key Metrics */}
        <div className="grid grid-cols-2 gap-4">
          <StatsCard
            label="Active Players"
            value={gameStats?.totalParticipants}
            icon={<Users />}
          />
          <StatsCard
            label="Total Battles"
            value={gameStats?.totalSeizeAttempts}
            icon={<Swords />}
          />
          <StatsCard
            label="Mercenaries Recruited"
            value={gameStats?.totalMercsRecruited}
            icon={<Shield />}
          />
          <StatsCard
            label="Resource Claims"
            value={gameStats?.totalClaims}
            icon={<Coins />}
          />
        </div>

        {/* Game Age */}
        <div className="pt-4 border-t">
          <div className="text-sm text-muted-foreground">Game Age</div>
          <div className="text-2xl font-semibold">
            {gameStats?.gameAge} days
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
```

---

## 📱 Single Page App Architecture

### State Management Strategy

#### Zustand Store Structure

```typescript
interface GameState {
  // User data
  playerAddress: string | null;
  playerName: string;

  // Game data
  allMines: Mine[];
  allResources: IERC20[];
  playerBalances: Map<IERC20, bigint>;
  playerMercenaries: Map<number, bigint>;

  // Statistics data
  playerStats: PlayerStatistics | null;
  gameStats: BasicGameStats | null;

  // UI state
  selectedMine: string | null;
  selectedPlayer: string | null;
  activeTab: "overview" | "mines" | "recruitment" | "analytics" | "profile";

  // Filters
  resourceFilter: IERC20 | null;
  ownerFilter: "all" | "owned" | "unowned" | "others";

  // Actions
  setSelectedMine: (address: string) => void;
  setSelectedPlayer: (address: string) => void;
  updatePlayerData: () => Promise<void>;
  refreshMineData: () => Promise<void>;
  refreshStatistics: () => Promise<void>;
}
```

#### React Query Integration

```typescript
// Custom hooks for contract data
export const usePlayerBalances = (address: string) => {
  return useQuery({
    queryKey: ["playerBalances", address],
    queryFn: async () => {
      // Fetch all resource balances using multicall
    },
    refetchInterval: 30000, // 30 seconds
  });
};

export const useAllMines = () => {
  return useQuery({
    queryKey: ["allMines"],
    queryFn: async () => {
      // Fetch all mines and their current state
    },
    refetchInterval: 60000, // 1 minute
  });
};

// Statistics-related hooks
export const usePlayerStats = (address: string) => {
  return useQuery({
    queryKey: ["playerStats", address],
    queryFn: async () => {
      // Fetch comprehensive player statistics
      const [
        depositStats,
        withdrawalStats,
        combatStats,
        mineStats,
        recruitmentStats,
      ] = await Promise.all([
        // Multiple PlayerStats contract calls
        // Use multicall for efficiency
      ]);

      return {
        depositStats,
        withdrawalStats,
        combatStats,
        mineStats,
        recruitmentStats,
      } as PlayerStatistics;
    },
    refetchInterval: 120000, // 2 minutes
    enabled: !!address,
  });
};

export const useGameStats = () => {
  return useQuery({
    queryKey: ["gameStats"],
    queryFn: async () => {
      // Fetch global game statistics
      const gameOverview = await readContract({
        address: CONTRACTS.GAME_STATS,
        abi: GameStatsABI,
        functionName: "getGameOverview",
      });

      // Additional calls for detailed metrics
      return gameOverview as GlobalAnalytics;
    },
    refetchInterval: 300000, // 5 minutes
  });
};

export const useBasicGameStats = () => {
  return useQuery({
    queryKey: ["basicGameStats"],
    queryFn: async () => {
      // Fetch basic global statistics
      const globalSnapshot = await readContract({
        address: CONTRACTS.MERC_MANIA_VIEW,
        abi: MercManiaViewABI,
        functionName: "getGlobalStatsSnapshot",
      });

      return globalSnapshot as BasicGameStats;
    },
    refetchInterval: 300000, // 5 minutes
  });
};
```

### Layout Structure

```tsx
export default function GameInterface() {
  const { activeTab } = useGameStore();

  return (
    <div className="min-h-screen bg-background">
      {/* Header with Navigation */}
      <GameHeader />

      {/* Main Content */}
      <div className="flex h-[calc(100vh-64px)]">
        {/* Left Sidebar - Player Dashboard */}
        <div className="w-80 border-r border-border">
          <div className="flex flex-col h-full">
            <PlayerDashboard />
            <div className="mt-4">
              <PlayerStatsPanel playerAddress={address} />
            </div>
          </div>
        </div>

        {/* Center Content - Tab-based */}
        <div className="flex-1">
          <Tabs
            value={activeTab}
            onValueChange={setActiveTab}
            className="h-full"
          >
            <TabsList className="w-full border-b">
              <TabsTrigger
                value="overview"
                className="flex items-center space-x-2"
              >
                <Home className="h-4 w-4" />
                <span>Overview</span>
              </TabsTrigger>
              <TabsTrigger
                value="mines"
                className="flex items-center space-x-2"
              >
                <Map className="h-4 w-4" />
                <span>Mine Map</span>
              </TabsTrigger>
              <TabsTrigger
                value="recruitment"
                className="flex items-center space-x-2"
              >
                <Users className="h-4 w-4" />
                <span>Recruitment</span>
              </TabsTrigger>
              <TabsTrigger
                value="analytics"
                className="flex items-center space-x-2"
              >
                <BarChart3 className="h-4 w-4" />
                <span>Analytics</span>
              </TabsTrigger>
            </TabsList>

            <TabsContent value="overview" className="h-full p-4">
              <GameOverview />
            </TabsContent>

            <TabsContent value="mines" className="h-full">
              <MineMap />
            </TabsContent>

            <TabsContent value="recruitment" className="h-full p-4">
              <MercenaryRecruitment />
            </TabsContent>

            <TabsContent value="analytics" className="h-full p-4">
              <BasicAnalyticsPanel />
            </TabsContent>
          </Tabs>
        </div>

        {/* Right Panel - Context Actions & Activity Feed */}
        <div className="w-96 border-l border-border">
          <div className="flex flex-col h-full">
            <ContextPanel />
            <div className="mt-4 flex-1">
              <ActivityFeed />
            </div>
          </div>
        </div>
      </div>

      {/* Modals */}
      <BattleModal />
      <RecruitmentModal />
      <ProfileModal />
    </div>
  );
}
```

---

## 👑 Themed Naming System

### Corporate Mercenary Names

Generate themed names using wallet address as RNG seed:

```typescript
// Corporate naming system based on game lore
const CORPORATE_PREFIXES = [
  // Atlas-Helix Consortium (North America/UK)
  "Atlas",
  "Helix",
  "Titan",
  "Summit",
  "Peak",
  "Apex",
  "Crown",

  // Yamato-Nordström Alliance (Europe/Pacific)
  "Yamato",
  "Nordic",
  "Frost",
  "Storm",
  "Thunder",
  "Blade",
  "Steel",

  // Crimson Phoenix Federation (Russia/Central Asia)
  "Crimson",
  "Phoenix",
  "Red",
  "Iron",
  "Bear",
  "Vanguard",
  "Elite",

  // Independent Contractors
  "Shadow",
  "Ghost",
  "Reaper",
  "Viper",
  "Wolf",
  "Raven",
  "Talon",
];

const MILITARY_SUFFIXES = [
  // Professional designations
  "Solutions",
  "Operations",
  "Group",
  "Corp",
  "Industries",
  "Tactical",
  "Defense",
  "Security",
  "Dynamics",
  "Systems",
  "Command",
  "Division",

  // Military units
  "Battalion",
  "Regiment",
  "Brigade",
  "Company",
  "Squad",
  "Unit",
  "Strike Force",
  "Guard",
  "Watch",
  "Legion",
  "Syndicate",
];

const LOCATION_MODIFIERS = [
  // African regions (game setting)
  "Sahara",
  "Congo",
  "Sahel",
  "Kalahari",
  "Atlas",
  "Rift",
  "Northern",
  "Southern",
  "Eastern",
  "Western",
  "Central",

  // Resource-based
  "Gold Coast",
  "Copper Valley",
  "Iron Ridge",
  "Lithium Plains",
];

function generateMercenaryName(walletAddress: string): string {
  // Use wallet address as seed for deterministic naming
  const seed = parseInt(walletAddress.slice(2, 10), 16);

  const prefix = CORPORATE_PREFIXES[seed % CORPORATE_PREFIXES.length];
  const modifier = LOCATION_MODIFIERS[(seed >> 8) % LOCATION_MODIFIERS.length];
  const suffix = MILITARY_SUFFIXES[(seed >> 16) % MILITARY_SUFFIXES.length];

  // Generate variations based on seed
  const nameType = seed % 4;

  switch (nameType) {
    case 0:
      return `${prefix} ${suffix}`;
    case 1:
      return `${modifier} ${prefix}`;
    case 2:
      return `${prefix} ${modifier} ${suffix}`;
    default:
      return `${modifier} ${suffix}`;
  }
}

// Examples:
// 0x1234... -> "Atlas Sahara Operations"
// 0x5678... -> "Crimson Defense Corp"
// 0x9abc... -> "Northern Wolf Battalion"
```

### Player Profile Display

```typescript
interface PlayerProfile {
  address: string;
  themedName: string;
  rank: string; // Based on controlled mines/resources
  faction:
    | "Atlas-Helix"
    | "Yamato-Nordström"
    | "Crimson-Phoenix"
    | "Independent";
  joinDate: number;
  totalBattles: number;
  minesControlled: number;
  netWorth: bigint;
}

// Generate faction based on address
function generateFaction(address: string): string {
  const seed = parseInt(address.slice(2, 6), 16);
  const factions = [
    "Atlas-Helix",
    "Yamato-Nordström",
    "Crimson-Phoenix",
    "Independent",
  ];
  return factions[seed % factions.length];
}
```

---

## 🔍 Data Aggregation Contract

The `MercManiaView.sol` contract provides efficient data fetching for the webapp with the following key capabilities:

    ### Key Data Structures

- **PlayerSnapshot**: Complete player data including balances and controlled mines
- **ResourceBalance**: Token balance information
- **MercenaryBalance**: Mercenary unit details with power calculations
- **MineSnapshot**: Current mine state including production and ownership
- **PlayerStatsSnapshot**: Comprehensive player analytics from PlayerStats contract
- **GlobalStatsSnapshot**: Game-wide statistics from GameStats contract

### Available Methods

- **`getPlayerSnapshot(address player)`** - Complete player data including resource balances, mercenary units, and controlled mines
- **`getAllMineSnapshots()`** - All mine states with production and ownership information
- **`getBattlePowerPreviews()`** - Battle power calculations for UI previews
- **`getPlayerStatsSnapshot(address player)`** - Comprehensive player analytics from PlayerStats contract
- **`getGlobalStatsSnapshot()`** - Game-wide statistics from GameStats contract

### Integration Notes

The MercManiaView contract integrates with PlayerStats and GameStats contracts to provide:

- Individual player analytics and performance metrics
- Global game statistics and trends
- Efficient batch queries to minimize RPC calls
- Optimized data structures for frontend consumption

---

## ⚡ Performance Optimization

### Data Fetching Strategy

#### Optimized Architecture: Metadata vs Balance Separation

Since **metadata NEVER changes** (names, symbols, images), we separate it from frequently-changing balance data:

```typescript
// ✅ EFFICIENT: Metadata cached forever, balances refresh regularly
const metadata = useResourceMetadata(); // staleTime: Infinity
const balances = usePlayerBalances(address); // staleTime: 5 seconds

// ❌ INEFFICIENT: Would refetch metadata constantly
// const playerData = usePlayerSnapshot(address); // includes metadata + balances
```

**Benefits:**

- **Reduced RPC calls**: Metadata fetched once per session
- **Faster updates**: Balance changes don't require metadata refetch
- **Cleaner data structures**: ResourceBalance only contains `token` + `balance`
- **Better UX**: Instant metadata loading after first fetch

#### React Query Caching

```typescript
// Optimized query configuration
export const usePlayerBalances = (address: string) => {
  return useQuery({
    queryKey: ["playerBalances", address],
    queryFn: async () => {
      const snapshot = await readContract({
        address: CONTRACTS.MERC_MANIA_VIEW,
        abi: MercManiaViewABI,
        functionName: "getPlayerSnapshot",
        args: [address],
      });
      return snapshot;
    },
    staleTime: 30000, // 5 seconds
    refetchInterval: 60000, // 1 minute
    refetchOnWindowFocus: true,
    enabled: !!address,
  });
};

// Cache resource metadata - NEVER changes so cache forever
export const useResourceMetadata = () => {
  return useQuery({
    queryKey: ["resourceMetadata"],
    queryFn: async () => {
      // Use the optimized view contract method
      const metadata = await readContract({
        address: CONTRACTS.MERC_MANIA_VIEW,
        abi: MercManiaViewABI,
        functionName: "getAllResourceMetadata",
      });

      // Convert to map for efficient lookups
      return metadata.reduce((acc, item) => {
        acc[item.token] = {
          name: item.name,
          symbol: item.symbol,
          tokenUri: item.tokenUri,
        };
        return acc;
      }, {} as Record<string, { name: string; symbol: string; tokenUri: string }>);
    },
    staleTime: Infinity, // Metadata NEVER changes
    refetchOnWindowFocus: false,
    refetchOnReconnect: false,
  });
};

// Cache mercenary metadata - NEVER changes so cache forever
export const useMercenaryMetadata = () => {
  return useQuery({
    queryKey: ["mercenaryMetadata"],
    queryFn: async () => {
      // Use the optimized view contract method
      const metadata = await readContract({
        address: CONTRACTS.MERC_MANIA_VIEW,
        abi: MercManiaViewABI,
        functionName: "getAllMercenaryMetadata",
      });

      // Convert to map for efficient lookups
      return metadata.reduce((acc, item) => {
        acc[item.token] = {
          name: item.name,
          symbol: item.symbol,
          tokenUri: item.tokenUri,
          level: item.level,
        };
        return acc;
      }, {} as Record<string, { name: string; symbol: string; tokenUri: string; level: number }>);
    },
    staleTime: Infinity, // Metadata NEVER changes
    refetchOnWindowFocus: false,
    refetchOnReconnect: false,
  });
};

// Efficient data combining - metadata + balances
export const usePlayerDataWithMetadata = (address: string) => {
  const { data: playerSnapshot } = usePlayerBalances(address);
  const { data: resourceMetadata } = useResourceMetadata();
  const { data: mercenaryMetadata } = useMercenaryMetadata();

  return useMemo(() => {
    if (!playerSnapshot || !resourceMetadata || !mercenaryMetadata) {
      return null;
    }

    return {
      ...playerSnapshot,
      resourceBalances: playerSnapshot.resourceBalances.map((resource) => ({
        ...resource,
        metadata: resourceMetadata[resource.token] || {
          name: "Unknown Resource",
          symbol: "???",
          tokenUri: "",
        },
      })),
      mercenaryUnits: playerSnapshot.mercenaryBalances.map((mercenary) => ({
        ...mercenary,
        metadata: mercenaryMetadata[mercenary.token] || {
          name: "Unknown Mercenary",
          symbol: "???",
          tokenUri: "",
          level: mercenary.level,
        },
      })),
    };
  }, [playerSnapshot, resourceMetadata, mercenaryMetadata]);
};

// Optimistic updates for instant UI feedback
export const useSeizeMine = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      mineAddress,
      mercLevel,
    }: {
      mineAddress: string;
      mercLevel: number;
    }) => {
      return await writeContract({
        address: mineAddress,
        abi: MineABI,
        functionName: "seize",
        args: [mercLevel],
      });
    },
    onMutate: async ({ mineAddress }) => {
      // Cancel outgoing refetches
      await queryClient.cancelQueries({ queryKey: ["allMines"] });

      // Snapshot previous value
      const previousMines = queryClient.getQueryData(["allMines"]);

      // Optimistically update mine owner
      queryClient.setQueryData(["allMines"], (old: MineSnapshot[]) => {
        return old?.map((mine) =>
          mine.mineAddress === mineAddress
            ? { ...mine, owner: address, lastSeized: Date.now() }
            : mine
        );
      });

      return { previousMines };
    },
    onError: (err, variables, context) => {
      // Rollback on error
      queryClient.setQueryData(["allMines"], context?.previousMines);
    },
    onSettled: () => {
      // Refetch after mutation
      queryClient.invalidateQueries({ queryKey: ["allMines"] });
    },
  });
};
```

#### Batch Contract Calls

```typescript
// Efficient multicall for multiple balances
export const useMultiplePlayerBalances = (addresses: string[]) => {
  return useQuery({
    queryKey: ["multiplePlayerBalances", addresses],
    queryFn: async () => {
      const contracts = addresses.map((address) => ({
        address: CONTRACTS.MERC_MANIA_VIEW,
        abi: MercManiaViewABI,
        functionName: "getPlayerSnapshot",
        args: [address],
      }));

      return await multicall({ contracts });
    },
    enabled: addresses.length > 0,
    staleTime: 45000,
  });
};

// Batch mine operations
export const useBatchMineData = (
  mineAddresses: string[],
  mercLevel: number,
  mercAmount: number
) => {
  return useQuery({
    queryKey: ["batchMineData", mineAddresses, mercLevel, mercAmount],
    queryFn: async () => {
      return await readContract({
        address: CONTRACTS.MERC_MANIA_VIEW,
        abi: MercManiaViewABI,
        functionName: "getBattlePowerPreviews",
        args: [
          mineAddresses,
          Array(mineAddresses.length).fill(mercLevel),
          Array(mineAddresses.length).fill(mercAmount),
        ],
      });
    },
    enabled: mineAddresses.length > 0 && mercLevel > 0 && mercAmount > 0,
  });
};
```

#### Pagination Strategy

```typescript
// Paginated mine listing with infinite scroll
export const usePaginatedMines = (pageSize: number = 20) => {
  return useInfiniteQuery({
    queryKey: ["paginatedMines", pageSize],
    queryFn: async ({ pageParam = 0 }) => {
      return await readContract({
        address: CONTRACTS.MINE_FACTORY,
        abi: MineFactoryABI,
        functionName: "getMines",
        args: [pageParam, pageSize],
      });
    },
    getNextPageParam: (lastPage, allPages) => {
      return lastPage.length === pageSize
        ? allPages.length * pageSize
        : undefined;
    },
    staleTime: 60000,
  });
};

// Virtualized mine grid for performance
import { FixedSizeGrid as Grid } from "react-window";

export function VirtualizedMineGrid({ mines }: { mines: MineSnapshot[] }) {
  const Cell = ({ columnIndex, rowIndex, style }) => {
    const index = rowIndex * COLUMNS + columnIndex;
    const mine = mines[index];

    if (!mine) return <div style={style} />;

    return (
      <div style={style}>
        <MineCard mine={mine} />
      </div>
    );
  };

  return (
    <Grid
      columnCount={COLUMNS}
      columnWidth={240}
      height={600}
      rowCount={Math.ceil(mines.length / COLUMNS)}
      rowHeight={200}
      width={1200}
    >
      {Cell}
    </Grid>
  );
}
```

---

## ⚠️ Error Handling & Edge Cases

### Common Web3 Errors

#### Wallet Connection Issues

```typescript
// Robust wallet connection handling
export function useWalletConnection() {
  const { address, isConnecting, isDisconnected } = useAccount();
  const [connectionError, setConnectionError] = useState<string | null>(null);

  const handleConnectionError = (error: Error) => {
    if (error.message.includes("User rejected")) {
      setConnectionError("Connection cancelled by user");
    } else if (error.message.includes("No injected provider")) {
      setConnectionError(
        "No wallet found. Please install MetaMask or another Web3 wallet."
      );
    } else {
      setConnectionError("Failed to connect wallet. Please try again.");
    }
  };

  return {
    address,
    isConnecting,
    isDisconnected,
    connectionError,
    handleConnectionError,
  };
}

// Network validation
export function useNetworkValidation() {
  const { chain } = useNetwork();
  const { switchNetwork } = useSwitchNetwork();

  const isCorrectNetwork = useMemo(() => {
    return chain?.id === SUPPORTED_CHAIN_ID;
  }, [chain?.id]);

  const switchToCorrectNetwork = useCallback(async () => {
    if (!isCorrectNetwork && switchNetwork) {
      try {
        await switchNetwork(SUPPORTED_CHAIN_ID);
      } catch (error) {
        toast.error("Failed to switch network. Please switch manually.");
      }
    }
  }, [isCorrectNetwork, switchNetwork]);

  return { isCorrectNetwork, switchToCorrectNetwork };
}
```

#### Transaction Error Handling

```typescript
// Comprehensive transaction error handling
export function useTransactionErrorHandler() {
  const handleTransactionError = useCallback((error: any) => {
    console.error("Transaction error:", error);

    if (error.code === 4001) {
      toast.error("Transaction cancelled by user");
    } else if (error.code === -32603) {
      toast.error(
        "Transaction failed. Please check your balance and try again."
      );
    } else if (error.message?.includes("insufficient funds")) {
      toast.error("Insufficient funds for transaction");
    } else if (error.message?.includes("gas")) {
      toast.error(
        "Transaction failed due to gas issues. Try increasing gas limit."
      );
    } else if (error.message?.includes("nonce")) {
      toast.error("Transaction nonce error. Please reset your wallet.");
    } else {
      toast.error("Transaction failed. Please try again.");
    }
  }, []);

  return { handleTransactionError };
}

// Transaction retry mechanism
export function useTransactionWithRetry() {
  const { handleTransactionError } = useTransactionErrorHandler();

  const executeWithRetry = useCallback(
    async (transactionFn: () => Promise<any>, maxRetries: number = 3) => {
      let lastError;

      for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          return await transactionFn();
        } catch (error) {
          lastError = error;

          // Don't retry user rejections
          if (error.code === 4001) {
            throw error;
          }

          // Wait before retry (exponential backoff)
          if (attempt < maxRetries) {
            await new Promise((resolve) =>
              setTimeout(resolve, 1000 * Math.pow(2, attempt - 1))
            );
          }
        }
      }

      handleTransactionError(lastError);
      throw lastError;
    },
    [handleTransactionError]
  );

  return { executeWithRetry };
}
```

### Game-Specific Error Handling

#### Mine Seizure Validation

```typescript
// Pre-transaction validation
export function useMineSeizureValidation() {
  const validateSeizure = useCallback(
    async (mineAddress: string, playerAddress: string, mercLevel: number) => {
      const errors: string[] = [];

      try {
        // Check if mine exists
        const mineInfo = await readContract({
          address: mineAddress,
          abi: MineABI,
          functionName: "getMineInfo",
        });

        // Check if player owns the mine
        if (mineInfo.owner === playerAddress) {
          errors.push("You already own this mine");
        }

        // Check mercenary availability
        const mercToken = await readContract({
          address: CONTRACTS.MERC_ASSET_FACTORY,
          abi: MercAssetFactoryABI,
          functionName: "getMercByLevel",
          args: [mercLevel],
        });

        if (mercToken === "0x0000000000000000000000000000000000000000") {
          errors.push(`Level ${mercLevel} mercenaries don't exist`);
        } else {
          const mercBalance = await readContract({
            address: CONTRACTS.GAME_MASTER,
            abi: GameMasterABI,
            functionName: "getBalance",
            args: [playerAddress, mercToken],
          });

          const minMercs = parseEther("25"); // MIN_MERCS_TO_SEIZE
          if (mercBalance < minMercs) {
            errors.push(
              `Need at least 25 Level ${mercLevel} mercenaries to attack`
            );
          }
        }

        return { isValid: errors.length === 0, errors };
      } catch (error) {
        return { isValid: false, errors: ["Failed to validate mine seizure"] };
      }
    },
    []
  );

  return { validateSeizure };
}

// Resource recruitment validation
export function useRecruitmentValidation() {
  const validateRecruitment = useCallback(
    async (playerAddress: string, resources: string[], amount: bigint) => {
      const errors: string[] = [];

      try {
        // Check if resources are valid
        const canRecruit = await readContract({
          address: CONTRACTS.MERC_RECRUITER,
          abi: MercRecruiterABI,
          functionName: "canRecruitMercs",
          args: [playerAddress, resources, amount],
        });

        if (!canRecruit) {
          errors.push("Insufficient resources for recruitment");
        }

        // Check if mercenary level exists
        const requiredLevel = await readContract({
          address: CONTRACTS.MERC_RECRUITER,
          abi: MercRecruiterABI,
          functionName: "getRequiredLevel",
          args: [resources],
        });

        const mercToken = await readContract({
          address: CONTRACTS.MERC_ASSET_FACTORY,
          abi: MercAssetFactoryABI,
          functionName: "getMercByLevel",
          args: [requiredLevel],
        });

        if (mercToken === "0x0000000000000000000000000000000000000000") {
          errors.push(
            `Level ${requiredLevel} mercenaries haven't been created yet`
          );
        }

        return { isValid: errors.length === 0, errors, requiredLevel };
      } catch (error) {
        return {
          isValid: false,
          errors: ["Failed to validate recruitment"],
          requiredLevel: 0,
        };
      }
    },
    []
  );

  return { validateRecruitment };
}
```

#### Graceful Fallbacks

```typescript
// Fallback UI components for error states
export function ErrorBoundary({ children }: { children: React.ReactNode }) {
  return (
    <ReactErrorBoundary
      FallbackComponent={({ error, resetErrorBoundary }) => (
        <Card className="p-6 text-center">
          <AlertTriangle className="h-12 w-12 mx-auto mb-4 text-destructive" />
          <h2 className="text-lg font-semibold mb-2">Something went wrong</h2>
          <p className="text-muted-foreground mb-4">
            {error.message || "An unexpected error occurred"}
          </p>
          <Button onClick={resetErrorBoundary}>Try Again</Button>
        </Card>
      )}
      onError={(error) => {
        console.error("ErrorBoundary caught an error:", error);
        // Log to analytics service
      }}
    >
      {children}
    </ReactErrorBoundary>
  );
}

// Loading fallbacks with timeout
export function useDataWithFallback<T>(
  queryResult: UseQueryResult<T>,
  fallbackData: T,
  timeoutMs: number = 10000
) {
  const [hasTimedOut, setHasTimedOut] = useState(false);

  useEffect(() => {
    if (queryResult.isLoading) {
      const timer = setTimeout(() => setHasTimedOut(true), timeoutMs);
      return () => clearTimeout(timer);
    } else {
      setHasTimedOut(false);
    }
  }, [queryResult.isLoading, timeoutMs]);

  if (hasTimedOut) {
    return { ...queryResult, data: fallbackData, isError: false };
  }

  return queryResult;
}
```

---

## 🔔 Live Updates & Notifications

### Real-time Mine Updates

#### WebSocket Integration

```typescript
// WebSocket connection for live game events
export function useGameWebSocket() {
  const [updates, setUpdates] = useState<GameUpdate[]>([]);
  const [connectionStatus, setConnectionStatus] = useState<
    "connecting" | "connected" | "disconnected"
  >("disconnected");

  useEffect(() => {
    const ws = new WebSocket(process.env.NEXT_PUBLIC_WS_ENDPOINT!);
    setConnectionStatus("connecting");

    ws.onopen = () => {
      setConnectionStatus("connected");
      console.log("WebSocket connected");
    };

    ws.onmessage = (event) => {
      try {
        const update: GameUpdate = JSON.parse(event.data);
        setUpdates((prev) => [update, ...prev.slice(0, 99)]); // Keep last 100 updates

        // Handle different update types
        switch (update.type) {
          case "MINE_SEIZED":
            handleMineSeized(update);
            break;
          case "RESOURCES_CLAIMED":
            handleResourcesClaimed(update);
            break;
          case "MERCENARIES_RECRUITED":
            handleMercenariesRecruited(update);
            break;
        }
      } catch (error) {
        console.error("Failed to parse WebSocket message:", error);
      }
    };

    ws.onclose = () => {
      setConnectionStatus("disconnected");
      // Attempt to reconnect after 5 seconds
      setTimeout(() => {
        if (ws.readyState === WebSocket.CLOSED) {
          // Reconnect logic here
        }
      }, 5000);
    };

    ws.onerror = (error) => {
      console.error("WebSocket error:", error);
      setConnectionStatus("disconnected");
    };

    return () => {
      ws.close();
    };
  }, []);

  const handleMineSeized = (update: MineSeizedUpdate) => {
    const { mineAddress, newOwner, attackerName, mineName } = update;

    // Update React Query cache
    queryClient.setQueryData(["allMines"], (oldMines: MineSnapshot[]) => {
      return oldMines?.map((mine) =>
        mine.mineAddress === mineAddress
          ? { ...mine, owner: newOwner, lastSeized: Date.now() }
          : mine
      );
    });

    // Show notification
    toast.success(`${attackerName} seized ${mineName}!`, {
      action: {
        label: "View Mine",
        onClick: () => setSelectedMine(mineAddress),
      },
    });
  };

  const handleResourcesClaimed = (update: ResourcesClaimedUpdate) => {
    const { playerAddress, mineAddress, amount, resourceType } = update;

    // Update player balances in cache
    queryClient.invalidateQueries(["playerBalances", playerAddress]);

    if (playerAddress === address) {
      toast.info(`Claimed ${formatEther(amount)} ${resourceType}!`);
    }
  };

  const handleMercenariesRecruited = (update: MercenariesRecruitedUpdate) => {
    const { playerAddress, level, amount } = update;

    // Update mercenary balances
    queryClient.invalidateQueries(["playerBalances", playerAddress]);

    if (playerAddress === address) {
      toast.success(`Recruited ${amount} Level ${level} mercenaries!`);
    }
  };

  return { updates, connectionStatus };
}

// Types for WebSocket updates
interface GameUpdate {
  type: "MINE_SEIZED" | "RESOURCES_CLAIMED" | "MERCENARIES_RECRUITED";
  timestamp: number;
}

interface MineSeizedUpdate extends GameUpdate {
  type: "MINE_SEIZED";
  mineAddress: string;
  newOwner: string;
  previousOwner: string;
  attackerName: string;
  mineName: string;
  mercLevel: number;
  attackerLosses: string;
  defenderLosses: string;
}

interface ResourcesClaimedUpdate extends GameUpdate {
  type: "RESOURCES_CLAIMED";
  playerAddress: string;
  mineAddress: string;
  amount: string;
  resourceType: string;
}

interface MercenariesRecruitedUpdate extends GameUpdate {
  type: "MERCENARIES_RECRUITED";
  playerAddress: string;
  level: number;
  amount: number;
  resourcesUsed: string[];
}
```

#### Push Notifications

```typescript
// Browser push notifications for important events
export function usePushNotifications() {
  const [permission, setPermission] =
    useState<NotificationPermission>("default");
  const { address } = useAccount();

  useEffect(() => {
    if ("Notification" in window) {
      setPermission(Notification.permission);
    }
  }, []);

  const requestPermission = async () => {
    if ("Notification" in window && permission === "default") {
      const result = await Notification.requestPermission();
      setPermission(result);
      return result;
    }
    return permission;
  };

  const sendNotification = useCallback(
    (title: string, options: NotificationOptions = {}) => {
      if (permission === "granted" && "Notification" in window) {
        new Notification(title, {
          icon: "/icon-192x192.png",
          badge: "/badge-72x72.png",
          ...options,
        });
      }
    },
    [permission]
  );

  const notifyMineAttacked = useCallback(
    (mineName: string, attackerName: string) => {
      sendNotification(`⚔️ Mine Under Attack!`, {
        body: `${attackerName} is attacking your ${mineName}`,
        tag: "mine-attack",
        requireInteraction: true,
      });
    },
    [sendNotification]
  );

  const notifyMineSeized = useCallback(
    (mineName: string, attackerName: string) => {
      sendNotification(`💥 Mine Lost!`, {
        body: `${attackerName} has seized your ${mineName}`,
        tag: "mine-seized",
        requireInteraction: true,
      });
    },
    [sendNotification]
  );

  const notifyResourcesReady = useCallback(
    (mineName: string, amount: string) => {
      sendNotification(`💰 Resources Ready!`, {
        body: `${amount} resources ready to claim from ${mineName}`,
        tag: "resources-ready",
      });
    },
    [sendNotification]
  );

  return {
    permission,
    requestPermission,
    notifyMineAttacked,
    notifyMineSeized,
    notifyResourcesReady,
  };
}
```

#### Activity Feed Component

```typescript
// Live activity feed showing recent game events
export function ActivityFeed() {
  const { updates } = useGameWebSocket();
  const { address } = useAccount();

  const filteredUpdates = useMemo(() => {
    return updates.filter((update) => {
      // Show all major events, highlight player-specific ones
      return true;
    });
  }, [updates]);

  return (
    <Card className="h-80 flex flex-col">
      <CardHeader className="pb-3">
        <CardTitle className="text-sm font-medium">Live Activity</CardTitle>
      </CardHeader>
      <CardContent className="flex-1 overflow-hidden">
        <ScrollArea className="h-full">
          <div className="space-y-2">
            {filteredUpdates.map((update, index) => (
              <ActivityItem
                key={`${update.timestamp}-${index}`}
                update={update}
                isPlayerEvent={isPlayerRelated(update, address)}
              />
            ))}
          </div>
        </ScrollArea>
      </CardContent>
    </Card>
  );
}

function ActivityItem({
  update,
  isPlayerEvent,
}: {
  update: GameUpdate;
  isPlayerEvent: boolean;
}) {
  const timeAgo = formatDistanceToNow(update.timestamp, { addSuffix: true });

  const getActivityIcon = () => {
    switch (update.type) {
      case "MINE_SEIZED":
        return <Swords className="h-4 w-4 text-destructive" />;
      case "RESOURCES_CLAIMED":
        return <Coins className="h-4 w-4 text-yellow-500" />;
      case "MERCENARIES_RECRUITED":
        return <Users className="h-4 w-4 text-primary" />;
      default:
        return <Activity className="h-4 w-4" />;
    }
  };

  const getActivityDescription = () => {
    switch (update.type) {
      case "MINE_SEIZED":
        const seizedUpdate = update as MineSeizedUpdate;
        return `${seizedUpdate.attackerName} seized ${seizedUpdate.mineName}`;
      case "RESOURCES_CLAIMED":
        const claimedUpdate = update as ResourcesClaimedUpdate;
        return `Resources claimed from mine`;
      case "MERCENARIES_RECRUITED":
        const recruitedUpdate = update as MercenariesRecruitedUpdate;
        return `${recruitedUpdate.amount} Level ${recruitedUpdate.level} mercenaries recruited`;
      default:
        return "Unknown activity";
    }
  };

  return (
    <div
      className={cn(
        "flex items-start space-x-3 p-2 rounded-lg transition-colors",
        isPlayerEvent ? "bg-primary/10" : "hover:bg-muted/50"
      )}
    >
      <div className="mt-1">{getActivityIcon()}</div>
      <div className="flex-1 min-w-0">
        <p className="text-sm text-foreground">{getActivityDescription()}</p>
        <p className="text-xs text-muted-foreground">{timeAgo}</p>
      </div>
      {isPlayerEvent && (
        <Badge variant="secondary" className="text-xs">
          You
        </Badge>
      )}
    </div>
  );
}

function isPlayerRelated(update: GameUpdate, playerAddress?: string): boolean {
  if (!playerAddress) return false;

  switch (update.type) {
    case "MINE_SEIZED":
      const seizedUpdate = update as MineSeizedUpdate;
      return (
        seizedUpdate.newOwner === playerAddress ||
        seizedUpdate.previousOwner === playerAddress
      );
    case "RESOURCES_CLAIMED":
    case "MERCENARIES_RECRUITED":
      return (update as any).playerAddress === playerAddress;
    default:
      return false;
  }
}
```

---

## 🚀 Implementation Roadmap

### Phase 1: Foundation (Week 1-2)

- [ ] Set up Next.js project with Web3 integration
- [ ] Implement wallet connection with ConnectKit
- [ ] Create basic component structure
- [ ] Implement themed naming system
- [ ] Configure contract addresses with PlayerStats and GameStats integration

### Phase 2: Core Features (Week 3-4)

- [ ] Player dashboard with resource/mercenary balances
- [ ] Mine map with interactive grid
- [ ] Basic deposit/withdraw functionality
- [ ] Mercenary recruitment interface
- [ ] Basic PlayerStatsPanel component

### Phase 3: Combat System (Week 5-6)

- [ ] Battle modal with power calculations
- [ ] Mine seizure functionality
- [ ] Battle history viewer
- [ ] Defense boost system
- [ ] Combat statistics tracking and display

### Phase 4: Analytics & Polish (Week 7-8)

- [ ] BasicAnalyticsPanel with global statistics
- [ ] Player performance metrics and trends
- [ ] Mobile responsiveness for all components
- [ ] Performance optimizations for statistics queries
- [ ] Real-time notifications and activity feeds

### Key Integration Points

#### Contract Addresses Configuration

```typescript
// lib/contracts.ts
export const CONTRACTS = {
  GAME_MASTER: "0x...",
  RESOURCE_MANAGER: "0x...",
  MERC_RECRUITER: "0x...",
  MINE_FACTORY: "0x...",
  MERC_ASSET_FACTORY: "0x...",
  PLAYER_STATS: "0x...",
  GAME_STATS: "0x...",
  MERC_MANIA_VIEW: "0x...",
} as const;
```

#### Multicall Integration

```typescript
// Use wagmi's multicall for efficient data fetching
export const usePlayerData = (address: string) => {
  return useMulticall({
    contracts: [
      // Batch all balance calls
      ...resources.map((resource) => ({
        address: CONTRACTS.GAME_MASTER,
        abi: GameMasterABI,
        functionName: "getBalance",
        args: [address, resource],
      })),
    ],
  });
};
```

This comprehensive guide provides everything needed to build a professional Merc Mania webapp that captures the strategic depth and dystopian atmosphere of the game while providing smooth Web3 integration and essential analytics capabilities.

---

_"In the theater of economic warfare, information superiority determines victory. Build the interface, deploy your forces, and establish digital dominance over the extraction economy."_
