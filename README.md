# PulseStride Walking Challenge

A blockchain-based platform for global walking challenges and step-counting competitions with automated reward distribution.

## Overview

PulseStride enables users worldwide to participate in virtual marathons and step-counting competitions on the blockchain. The platform features:

- Creation and participation in walking challenges
- Verified step tracking through trusted oracles
- Automated reward distribution based on achievement
- Real-time leaderboards
- Both official and community-created challenges
- Stake-to-participate mechanism

## Architecture

The PulseStride system is built around a core smart contract that handles:

```mermaid
graph TD
    A[Participants] -->|Register & Stake| B[Challenge Contract]
    C[Oracles] -->|Submit Step Data| B
    B -->|Update| D[Leaderboard]
    B -->|Track| E[Achievements]
    B -->|Distribute| F[Rewards]
    G[Admins] -->|Create Official Challenges| B
    A -->|Create Community Challenges| B
```

### Core Components:
- Challenge Management
- Participant Registration
- Step Data Verification
- Achievement Tracking
- Reward Distribution
- Leaderboard System

## Contract Documentation

### PulseStride Contract (`pulse-stride.clar`)

The main contract managing the entire PulseStride ecosystem.

#### Key Features:
- Role-based access control (Admin, Oracle)
- Challenge creation and management
- Participant registration and tracking
- Step data submission and verification
- Achievement tracking
- Automated reward distribution
- Real-time leaderboard updates

#### Access Control
- Contract Owner: Full administrative control
- Admins: Can create official challenges and manage platform
- Oracles: Authorized to submit verified step data
- Users: Can participate in challenges and create community challenges

## Getting Started

### Prerequisites
- Clarinet
- Stacks wallet
- STX tokens for participation

### Basic Usage

1. **Creating a Challenge**
```clarity
(contract-call? .pulse-stride create-challenge
    "30-Day Walking Challenge"
    "Walk 10,000 steps daily for 30 days"
    false  ;; community challenge
    u1234567890  ;; start time
    u1237246290  ;; end time
    u300000  ;; step goal
    u200000  ;; distance goal in meters
    u100000000  ;; entry fee in microSTX
    u100  ;; max participants
    u0)  ;; initial reward pool
```

2. **Registering for a Challenge**
```clarity
(contract-call? .pulse-stride register-for-challenge u1)
```

3. **Submitting Step Data (Oracle)**
```clarity
(contract-call? .pulse-stride submit-step-data 
    u1  ;; challenge-id
    tx-sender  ;; participant
    u5000  ;; steps
    u4000)  ;; distance
```

4. **Claiming Rewards**
```clarity
(contract-call? .pulse-stride claim-rewards u1)
```

## Function Reference

### Administrative Functions
- `set-contract-owner`: Update contract owner
- `grant-role`: Assign roles to addresses
- `revoke-role`: Remove roles from addresses

### Challenge Management
- `create-challenge`: Create new walking challenge
- `end-challenge`: Conclude an active challenge
- `add-to-reward-pool`: Add funds to challenge rewards

### Participant Functions
- `register-for-challenge`: Join a challenge
- `claim-rewards`: Collect earned rewards

### Oracle Functions
- `submit-step-data`: Submit verified step counts

### Read-Only Functions
- `get-challenge`: Retrieve challenge details
- `get-participant-data`: Get participant statistics
- `get-leaderboard`: View challenge rankings
- `get-achievements`: Check participant achievements
- `get-estimated-reward`: Calculate potential rewards

## Development

### Testing
```bash
# Run contract tests
clarinet test

# Check contract deployment
clarinet console
```

### Local Development
1. Clone the repository
2. Install Clarinet
3. Deploy contracts locally:
```bash
clarinet deploy --local
```

## Security Considerations

### Known Limitations
- Relies on trusted oracles for step data
- Leaderboard limited to top 50 participants
- Challenge duration constraints (1-30 days)

### Best Practices
- Verify challenge parameters before participation
- Wait for transaction confirmation before UI updates
- Monitor oracle submissions for anomalies
- Review reward calculations before claiming

### Risk Mitigation
- Step data must increase monotonically
- Rewards locked until challenge completion
- Role-based access control for critical functions
- Challenge parameters validated at creation