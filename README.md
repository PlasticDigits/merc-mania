# ⚔️ MERC MANIA

_Strategic Mercenary Mining Operations_

Welcome to the contested territories where mercenary companies compete for control of valuable resource extraction sites. In this high-stakes environment, tactical thinking and resource management determine who controls the wealth flowing from Africa's mineral-rich regions.

## 🏜️ The Theater of Operations

In the vast expanses of a resource-rich continent, powerful extraction sites lie scattered across contested territory. Multiple mercenary companies deploy their forces to secure these lucrative mining operations, establishing temporary control through superior firepower and strategic positioning.

Every mine tells a story of shifting allegiances, tactical victories, and the relentless pursuit of mineral wealth that drives the modern mercenary economy.

## ⚙️ Operational Systems

### Resource Command & Control

- **Central Asset Management** (`GameMaster`): Secure escrow system managing all company assets with built-in operational costs
- **Resource Intelligence** (`ResourceManager`): Comprehensive tracking of all strategic materials and supply chains
- **Extraction Facilities** (`Mine`): Capturable production sites with diminishing output over time

### Force Deployment

- **Recruitment Operations** (`MercRecruiter`): Convert resources into professional military assets
- **Personnel Management** (`MercAssetFactory`): Standardized mercenary unit creation and classification
- **Equipment Procurement** (`GameAssetFactory`): Resource token generation and distribution

### Combat Mechanics

- **Territorial Seizure**: Assault mining facilities using deployed mercenary forces
- **Defense Systems**: Fortify positions and repel hostile acquisition attempts
- **Battle Resolution**: Sophisticated power calculation based on unit levels and quantities
- **Strategic Withdrawal**: Recover assets with operational penalties to prevent total loss

## 🎯 Mission Objectives

### Primary Operations

1. **Secure Mining Rights**: Deploy mercenary forces to capture resource extraction facilities
2. **Resource Acquisition**: Extract valuable materials from controlled territories
3. **Force Multiplication**: Recruit and upgrade mercenary units using strategic resource combinations
4. **Economic Warfare**: Disrupt competitor operations while defending your own assets

### Tactical Considerations

- **Resource Diversification**: Higher-level mercenaries require multiple material types
- **Operational Security**: Fortify positions using Gold-based defense systems
- **Asset Recovery**: Strategic abandonment preserves 90% of deployed forces
- **Supply Chain Management**: All operations require Gold as base currency

## 🛡️ Strategic Framework

### Economic Principles

- **Operational Costs**: 50% asset burn rate on withdrawals maintains economic stability
- **Production Decay**: Mining output halves every 72 hours to prevent infinite resource generation
- **Combat Losses**: Failed territorial acquisitions result in complete unit loss
- **Defense Investment**: Gold expenditure provides temporary tactical advantages

### Force Structure

| Level | Classification      | Resource Requirements        |
| ----- | ------------------- | ---------------------------- |
| 1     | Local Militia       | Gold only                    |
| 2     | Professional Forces | Gold + 1 strategic material  |
| 3     | Elite Operations    | Gold + 2 strategic materials |
| 4     | Special Command     | Gold + 3 strategic materials |
| 5     | Legendary Assets    | Gold + 4 strategic materials |

## 🔧 Development Infrastructure

This project utilizes the Foundry development framework for Ethereum smart contract development.

### Core Dependencies

- **Solidity ^0.8.30**: Latest security features and gas optimizations
- **OpenZeppelin Contracts**: Industry-standard security implementations
- **Foundry Framework**: Advanced testing and deployment capabilities

### Build Operations

```shell
# Compile all contracts
forge build

# Execute comprehensive test suite
forge test

# Format codebase to standards
forge fmt

# Generate gas usage reports
forge snapshot

# Launch local development network
anvil
```

### Deployment Commands

```shell
# Deploy to target network
forge script script/Deploy.s.sol:DeployScript --rpc-url <network_url> --private-key <deployer_key>

# Interact with deployed contracts
cast <subcommand>
```

### Development Resources

```shell
# Access framework documentation
forge --help
anvil --help
cast --help
```

## 📜 License & Terms

This project operates under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. All contract code, strategic innovations, and operational methodologies are freely available for modification and redistribution under the same license terms.

The AGPL ensures that any network-deployed modifications remain open source, maintaining transparency in the mercenary operations ecosystem.

## 🎮 For Operators

See [STYLE-GUIDE.md](STYLE-GUIDE.md) for comprehensive thematic guidelines when developing additional content, narratives, or integrated systems.

---

_"In the theater of economic warfare, territorial control determines everything. Secure the assets, deploy your forces, and establish dominance over the extraction economy."_
