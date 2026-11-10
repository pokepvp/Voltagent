// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal interface for the Volta Gent NFT contract.
interface IVoltaGent {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title VoltaArena — real-stake battles + on-chain energy + mining for Volta Gent.
///
/// Design (from the project concept, roadmap phase 05):
/// - Battle: two holders stake STAKE each; entering costs BATTLE_ENERGY energy.
///   The second entrant locks commitBlock = block.number + 2. Anyone resolves
///   after that block: seed = blockhash(commitBlock), win chance proportional
///   to tier power. Winner gets WINNER_PAYOUT (90% of the 2-stake pool), the
///   remaining 10% stays in the contract pool.
/// - If a locked battle is never resolved and the commit blockhash expires
///   (>256 blocks), both players can be refunded in full (energy stays spent).
/// - An open (unmatched) battle can be cancelled by its creator: stake and
///   energy are refunded.
/// - Energy: 100 per token, regenerates +1/hour, recharge 0.0001 BNB per 10.
/// - Mining: each token accrues MINING_RATE per hour (capped at
///   MAX_ACCRUAL_HOURS). Claiming costs CLAIM_ENERGY energy, pays at least
///   MIN_CLAIM, and only pays out of the free pool (contract balance minus
///   escrowed battle stakes) — if the pool is short, the claim reverts.
/// - Tier powers are NOT stored per token (too expensive). The owner uploads
///   one byte per token (tierBlob, index = tokenId - 1) generated from the
///   collection metadata; powerOf() maps the code to a fixed power table.
///
/// The contract is unaudited. Stakes are deliberately small because
/// blockhash-based randomness is not VRF-grade.
contract VoltaArena {
    uint256 public constant STAKE = 0.0005 ether;
    uint256 public constant WINNER_PAYOUT = 0.0009 ether;
    uint256 public constant BATTLE_ENERGY = 20;
    uint256 public constant CLAIM_ENERGY = 10;
    uint256 public constant MAX_ENERGY = 100;
    uint256 public constant ENERGY_PER_RECHARGE = 10;
    uint256 public constant RECHARGE_PRICE = 0.0001 ether; // per 10 energy
    uint256 public constant MINING_RATE = 0.00001 ether; // per hour
    uint256 public constant MIN_CLAIM = 0.0001 ether;
    uint256 public constant MAX_ACCRUAL_HOURS = 48;
    uint256 public constant RESOLVE_WINDOW = 256; // blockhash availability

    address public owner;
    IVoltaGent public immutable nft;

    /// @notice One byte per token: 0 Common, 1 Uncommon, 2 Rare, 3 Epic, 4 Legendary, 5 Mythic.
    bytes public tierBlob;

    mapping(uint256 => uint256) public storedEnergy;
    mapping(uint256 => uint256) public energyUpdated; // 0 = untouched
    mapping(uint256 => uint256) public lastClaim; // mining accrual start

    enum BattleState {
        None,
        Open,
        Locked,
        Resolved,
        Cancelled,
        Refunded
    }
    struct Battle {
        address playerA;
        uint256 tokenA;
        address playerB;
        uint256 tokenB;
        uint256 commitBlock;
        BattleState state;
        address winner;
    }
    Battle[] public battles; // battle ids start at 1 (index 0 is a dummy)
    uint256 public openBattleId; // 0 = no battle waiting for an opponent
    mapping(uint256 => uint256) public activeBattleOfToken;
    uint256 public escrow; // stakes held for Open/Locked battles

    bool private _entered;

    event BattleOpened(uint256 indexed battleId, address indexed player, uint256 tokenId);
    event BattleLocked(uint256 indexed battleId, address indexed player, uint256 tokenId, uint256 commitBlock);
    event BattleResolved(uint256 indexed battleId, address indexed winner, uint256 loserToken, uint256 winnerToken);
    event BattleCancelled(uint256 indexed battleId);
    event BattleRefunded(uint256 indexed battleId);
    event Claimed(address indexed player, uint256 indexed tokenId, uint256 amount);
    event Recharged(address indexed player, uint256 indexed tokenId, uint256 units);
    event PoolFunded(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event TierDataAppended(uint256 totalLength);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }
    modifier nonReentrant() {
        require(!_entered, "reentrant");
        _entered = true;
        _;
        _entered = false;
    }

    constructor(address nftAddress) {
        require(nftAddress != address(0), "nft is zero");
        owner = msg.sender;
        nft = IVoltaGent(nftAddress);
        battles.push(); // dummy at index 0 so real battle ids start at 1
    }

    receive() external payable {}

    // ---------------- tier data ----------------

    function appendTierData(bytes calldata chunk) external onlyOwner {
        tierBlob = bytes.concat(tierBlob, chunk);
        emit TierDataAppended(tierBlob.length);
    }

    function tierBlobLength() external view returns (uint256) {
        return tierBlob.length;
    }

    function tierOf(uint256 tokenId) public view returns (uint8) {
        if (tokenId == 0 || tokenId > tierBlob.length) return 255;
        return uint8(tierBlob[tokenId - 1]);
    }

    function powerOf(uint256 tokenId) public view returns (uint256) {
        uint8 t = tierOf(tokenId);
        if (t == 0) return 10;
        if (t == 1) return 20;
        if (t == 2) return 35;
        if (t == 3) return 55;
        if (t == 4) return 80;
        if (t == 5) return 100;
        return 0;
    }

    // ---------------- energy + mining ----------------

    function energyOf(uint256 tokenId) public view returns (uint256) {
        if (energyUpdated[tokenId] == 0) return MAX_ENERGY;
        uint256 regen = (block.timestamp - energyUpdated[tokenId]) / 3600;
        uint256 e = storedEnergy[tokenId] + regen;
        return e > MAX_ENERGY ? MAX_ENERGY : e;
    }

    function miningAccruedOf(uint256 tokenId) public view returns (uint256) {
        if (lastClaim[tokenId] == 0) return 0;
        uint256 hoursElapsed = (block.timestamp - lastClaim[tokenId]) / 3600;
        if (hoursElapsed > MAX_ACCRUAL_HOURS) hoursElapsed = MAX_ACCRUAL_HOURS;
        return hoursElapsed * MINING_RATE;
    }

    function _touch(uint256 tokenId) internal {
        if (energyUpdated[tokenId] == 0) {
            storedEnergy[tokenId] = MAX_ENERGY;
            energyUpdated[tokenId] = block.timestamp;
            lastClaim[tokenId] = block.timestamp;
        }
    }

    function _settleEnergy(uint256 tokenId) internal {
        storedEnergy[tokenId] = energyOf(tokenId);
        energyUpdated[tokenId] = block.timestamp;
    }

    function _requireTokenOwner(uint256 tokenId) internal view {
        require(nft.ownerOf(tokenId) == msg.sender, "not token owner");
    }

    function recharge(uint256 tokenId, uint256 units) external payable nonReentrant {
        require(units > 0, "units is zero");
        require(msg.value == units * RECHARGE_PRICE, "wrong value");
        _requireTokenOwner(tokenId);
        _touch(tokenId);
        uint256 e = energyOf(tokenId);
        require(e + units * ENERGY_PER_RECHARGE <= MAX_ENERGY, "energy would overflow");
        storedEnergy[tokenId] = e + units * ENERGY_PER_RECHARGE;
        energyUpdated[tokenId] = block.timestamp;
        emit Recharged(msg.sender, tokenId, units);
    }

    function claimMining(uint256 tokenId) external nonReentrant {
        _requireTokenOwner(tokenId);
        _touch(tokenId);
        uint256 accrued = miningAccruedOf(tokenId);
        require(accrued >= MIN_CLAIM, "below min claim");
        require(energyOf(tokenId) >= CLAIM_ENERGY, "not enough energy");
        require(accrued <= poolAvailable(), "pool is short");
        _settleEnergy(tokenId);
        storedEnergy[tokenId] -= CLAIM_ENERGY;
        lastClaim[tokenId] = block.timestamp;
        (bool ok, ) = payable(msg.sender).call{value: accrued}("");
        require(ok, "pay failed");
        emit Claimed(msg.sender, tokenId, accrued);
    }

    // ---------------- battles ----------------

    function enterBattle(uint256 tokenId) external payable nonReentrant {
        require(msg.value == STAKE, "wrong stake");
        _requireTokenOwner(tokenId);
        require(powerOf(tokenId) > 0, "tier not registered");
        require(activeBattleOfToken[tokenId] == 0, "token already in battle");
        _touch(tokenId);
        require(energyOf(tokenId) >= BATTLE_ENERGY, "not enough energy");
        _settleEnergy(tokenId);
        storedEnergy[tokenId] -= BATTLE_ENERGY;

        escrow += STAKE;
        if (openBattleId != 0) {
            Battle storage b = battles[openBattleId];
            require(b.state == BattleState.Open, "open battle not open");
            require(b.playerA != msg.sender, "cannot fight yourself");
            b.playerB = msg.sender;
            b.tokenB = tokenId;
            b.commitBlock = block.number + 2;
            b.state = BattleState.Locked;
            activeBattleOfToken[tokenId] = openBattleId;
            uint256 id = openBattleId;
            openBattleId = 0;
            emit BattleLocked(id, msg.sender, tokenId, b.commitBlock);
        } else {
            battles.push(
                Battle({
                    playerA: msg.sender,
                    tokenA: tokenId,
                    playerB: address(0),
                    tokenB: 0,
                    commitBlock: 0,
                    state: BattleState.Open,
                    winner: address(0)
                })
            );
            uint256 id = battles.length - 1;
            openBattleId = id;
            activeBattleOfToken[tokenId] = id;
            emit BattleOpened(id, msg.sender, tokenId);
        }
    }

    function resolveBattle(uint256 battleId) external nonReentrant {
        Battle storage b = battles[battleId];
        require(b.state == BattleState.Locked, "battle not locked");
        require(block.number > b.commitBlock, "too early");
        bytes32 bh = blockhash(b.commitBlock);
        require(bh != bytes32(0), "blockhash expired, refund instead");
        uint256 pA = powerOf(b.tokenA);
        uint256 pB = powerOf(b.tokenB);
        uint256 seed = uint256(bh);
        bool aWins = (seed % (pA + pB)) < pA;
        address winnerAddr = aWins ? b.playerA : b.playerB;
        b.state = BattleState.Resolved;
        b.winner = winnerAddr;
        activeBattleOfToken[b.tokenA] = 0;
        activeBattleOfToken[b.tokenB] = 0;
        escrow -= 2 * STAKE;
        (bool ok, ) = payable(winnerAddr).call{value: WINNER_PAYOUT}("");
        require(ok, "pay failed");
        emit BattleResolved(battleId, winnerAddr, aWins ? b.tokenB : b.tokenA, aWins ? b.tokenA : b.tokenB);
    }

    function cancelOpenBattle(uint256 battleId) external nonReentrant {
        Battle storage b = battles[battleId];
        require(b.state == BattleState.Open, "battle not open");
        require(b.playerA == msg.sender, "not battle creator");
        b.state = BattleState.Cancelled;
        activeBattleOfToken[b.tokenA] = 0;
        if (openBattleId == battleId) openBattleId = 0;
        escrow -= STAKE;
        // refund the energy spent on entry (capped at MAX by energyOf accounting)
        _settleEnergy(b.tokenA);
        storedEnergy[b.tokenA] += BATTLE_ENERGY;
        if (storedEnergy[b.tokenA] > MAX_ENERGY) storedEnergy[b.tokenA] = MAX_ENERGY;
        (bool ok, ) = payable(msg.sender).call{value: STAKE}("");
        require(ok, "refund failed");
        emit BattleCancelled(battleId);
    }

    function refundExpiredBattle(uint256 battleId) external nonReentrant {
        Battle storage b = battles[battleId];
        require(b.state == BattleState.Locked, "battle not locked");
        require(block.number > b.commitBlock + RESOLVE_WINDOW, "not expired yet");
        b.state = BattleState.Refunded;
        activeBattleOfToken[b.tokenA] = 0;
        activeBattleOfToken[b.tokenB] = 0;
        escrow -= 2 * STAKE;
        (bool okA, ) = payable(b.playerA).call{value: STAKE}("");
        require(okA, "refund A failed");
        (bool okB, ) = payable(b.playerB).call{value: STAKE}("");
        require(okB, "refund B failed");
        emit BattleRefunded(battleId);
    }

    // ---------------- views + pool ----------------

    function getBattle(uint256 battleId)
        external
        view
        returns (address playerA, uint256 tokenA, address playerB, uint256 tokenB, uint256 commitBlock, BattleState state, address winner)
    {
        Battle storage b = battles[battleId];
        return (b.playerA, b.tokenA, b.playerB, b.tokenB, b.commitBlock, b.state, b.winner);
    }

    function battleCount() external view returns (uint256) {
        return battles.length - 1;
    }

    function poolAvailable() public view returns (uint256) {
        uint256 bal = address(this).balance;
        return bal > escrow ? bal - escrow : 0;
    }

    function fundPool() external payable {
        require(msg.value > 0, "nothing sent");
        emit PoolFunded(msg.sender, msg.value);
    }

    /// @notice Owner withdraws only the free pool — escrowed stakes are untouchable.
    function withdraw() external onlyOwner nonReentrant {
        uint256 amount = poolAvailable();
        require(amount > 0, "pool empty");
        (bool ok, ) = payable(owner).call{value: amount}("");
        require(ok, "withdraw failed");
        emit Withdrawn(owner, amount);
    }
}
