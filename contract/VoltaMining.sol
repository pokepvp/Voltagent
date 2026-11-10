// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal interface for the Volta Gent NFT contract.
interface IVoltaGentNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @notice Minimal interface for the Volta Coin (VOLT) ERC-20.
interface IVoltaCoin {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

/// @title VoltaMining — VOLT mining claims for Volta Gent holders.
///
/// Why this exists: the deployed VoltaArena contract is immutable and its
/// mining pays BNB out of a pool that has to be funded in BNB. This separate
/// contract gives players a mining claim that pays VOLT instead:
///
/// - A holder first calls startMining(tokenId) once per token. Accrual starts
///   at that moment — a token can never back-accrue to before its start, so
///   freshly minted tokens do not inherit earnings from contract launch.
/// - Accrual: ratePerHour VOLT per hour (starts at 10 VOLT/h), capped at
///   MAX_ACCRUAL_SECONDS (48 hours) of unclaimed time. Time past the cap is
///   forfeited at claim; the sub-rate remainder inside the window is kept.
/// - claim(tokenId) pays the accrued VOLT out of this contract's token
///   reserve (the owner funds the reserve by transferring VOLT here). The
///   minimum claim is MIN_CLAIM (10 VOLT); if the reserve is short the claim
///   reverts and the accrual is untouched.
/// - The owner can adjust the rate and withdraw reserve tokens (reclaim).
///
/// The contract is unaudited.
contract VoltaMining {
    uint256 public constant MIN_CLAIM = 10 ether; // 10 VOLT
    uint256 public constant MAX_ACCRUAL_SECONDS = 48 hours; // 172800

    address public owner;
    IVoltaGentNFT public immutable nft;
    IVoltaCoin public immutable token;

    uint256 public ratePerHour = 10 ether; // 10 VOLT per hour

    /// @notice Accrual start / last-claim timestamp per token. 0 = not started.
    mapping(uint256 => uint256) public lastClaim;

    bool private _entered;

    event MiningStarted(address indexed player, uint256 indexed tokenId);
    event Claimed(address indexed player, uint256 indexed tokenId, uint256 amount);
    event RateUpdated(uint256 newRate);
    event TokensWithdrawn(address indexed to, uint256 amount);

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

    constructor(address nftAddress, address tokenAddress) {
        require(nftAddress != address(0), "nft is zero");
        require(tokenAddress != address(0), "token is zero");
        owner = msg.sender;
        nft = IVoltaGentNFT(nftAddress);
        token = IVoltaCoin(tokenAddress);
    }

    // ---------------- player flow ----------------

    function startMining(uint256 tokenId) external {
        _requireTokenOwner(tokenId);
        require(lastClaim[tokenId] == 0, "already started");
        lastClaim[tokenId] = block.timestamp;
        emit MiningStarted(msg.sender, tokenId);
    }

    function claim(uint256 tokenId) external nonReentrant {
        _requireTokenOwner(tokenId);
        require(lastClaim[tokenId] != 0, "mining not started");
        uint256 amount = accruedOf(tokenId);
        require(amount >= MIN_CLAIM, "below min claim");
        require(amount <= reserve(), "reserve is short");
        uint256 elapsed = block.timestamp - lastClaim[tokenId];
        if (elapsed > MAX_ACCRUAL_SECONDS) {
            // Time beyond the 48h cap is forfeited.
            lastClaim[tokenId] = block.timestamp;
        } else {
            // Advance only by the seconds actually paid for, so the
            // remainder seconds inside the window keep accruing.
            lastClaim[tokenId] += (amount * 3600) / ratePerHour;
        }
        require(token.transfer(msg.sender, amount), "pay failed");
        emit Claimed(msg.sender, tokenId, amount);
    }

    // ---------------- views ----------------

    function accruedOf(uint256 tokenId) public view returns (uint256) {
        uint256 start = lastClaim[tokenId];
        if (start == 0) return 0;
        uint256 elapsed = block.timestamp - start;
        if (elapsed > MAX_ACCRUAL_SECONDS) elapsed = MAX_ACCRUAL_SECONDS;
        return (elapsed * ratePerHour) / 3600;
    }

    function lastClaimOf(uint256 tokenId) external view returns (uint256) {
        return lastClaim[tokenId];
    }

    /// @notice VOLT reserve available for claims.
    function reserve() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    // ---------------- owner ----------------

    function setRatePerHour(uint256 newRate) external onlyOwner {
        ratePerHour = newRate;
        emit RateUpdated(newRate);
    }

    /// @notice Reclaim/rescue reserve tokens back to the owner wallet.
    function withdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "amount is zero");
        require(amount <= reserve(), "reserve too low");
        require(token.transfer(owner, amount), "transfer failed");
        emit TokensWithdrawn(owner, amount);
    }

    // ---------------- internals ----------------

    function _requireTokenOwner(uint256 tokenId) internal view {
        require(nft.ownerOf(tokenId) == msg.sender, "not token owner");
    }
}
