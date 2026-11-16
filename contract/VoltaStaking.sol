// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title VoltaStaking — stake Volta Gent (VLTG) NFTs, earn VOLT Points.
/// @notice Holders stake VLTG NFTs and earn non-transferable VOLT Points at
///         POINTS_PER_DAY = 10 points per staked NFT per day. There is NO
///         lockup: unstake anytime. Points are NOT a token and NOT a yield —
///         they are just a stored balance inside this contract (no transfer
///         functions, no BNB involved) that unlocks priority access and
///         future rewards in the Volta Gent ecosystem.
/// - Points accrue per token from the moment it is staked (per-token
///   checkpoint). claimPoints() settles every staked token of the caller:
///   the accrued points move into the caller's stored pointsBalance and
///   each token's checkpoint advances ONLY by the time actually converted
///   into points, so sub-day remainders keep accruing instead of being lost.
/// - Unstaking auto-claims that token's accrued points first, then returns
///   the NFT.
/// - The NFT contract (VoltaGentV2) is wired after deployment: the
///   constructor takes an initial address (may be address(0)) and the owner
///   can update it anytime with setNftContract(). stake() reverts while no
///   NFT contract is set.
/// - The owner can NEVER seize staked NFTs: there is deliberately no admin
///   function that moves staked tokens out of this contract.
contract VoltaStaking is Ownable, ERC721Holder {
    uint256 public constant POINTS_PER_DAY = 10;

    /// @notice The VLTG NFT contract whose tokens can be staked.
    address public nftContract;

    /// @notice Claimed (stored) VOLT Points per user. Non-transferable.
    mapping(address => uint256) public pointsBalance;

    /// @notice Recorded staker of a token (address(0) = not staked here).
    mapping(uint256 => address) public stakerOf;

    /// @notice Accrual checkpoint (timestamp) per staked token.
    mapping(uint256 => uint256) public checkpointOf;

    // Token ids staked per user + each token's index in its staker's array
    // (swap-and-pop removal on unstake).
    mapping(address => uint256[]) private _stakedTokens;
    mapping(uint256 => uint256) private _stakedIndex;

    uint256 private _totalStaked;

    event Staked(address indexed user, uint256 indexed tokenId);
    event Unstaked(address indexed user, uint256 indexed tokenId);
    event PointsClaimed(address indexed user, uint256 points);
    event NftContractSet(address indexed nftContract);

    constructor(address initialNftContract) Ownable(msg.sender) {
        nftContract = initialNftContract;
    }

    /// @notice Point the staking contract at the VLTG NFT contract (owner
    /// only). Call this after VoltaGentV2 is deployed.
    function setNftContract(address newNftContract) external onlyOwner {
        nftContract = newNftContract;
        emit NftContractSet(newNftContract);
    }

    /// @notice Total NFTs currently staked, across all users.
    function totalStaked() external view returns (uint256) {
        return _totalStaked;
    }

    /// @notice Token ids currently staked by `user`.
    function stakedOf(address user) external view returns (uint256[] memory) {
        return _stakedTokens[user];
    }

    /// @notice Unclaimed points accrued by one staked token right now.
    function _claimableOfToken(uint256 tokenId) internal view returns (uint256) {
        if (stakerOf[tokenId] == address(0)) return 0;
        return ((block.timestamp - checkpointOf[tokenId]) * POINTS_PER_DAY) / 1 days;
    }

    /// @notice Total unclaimed points across all tokens staked by `user`.
    function claimablePoints(address user) external view returns (uint256) {
        uint256 total = 0;
        uint256[] storage ids = _stakedTokens[user];
        for (uint256 i = 0; i < ids.length; i++) {
            total += _claimableOfToken(ids[i]);
        }
        return total;
    }

    /// @notice Settle one token: move its accrued points into the staker's
    /// stored balance and advance the checkpoint only by the time that was
    /// actually converted into points (sub-day remainder is preserved).
    function _settle(uint256 tokenId) internal returns (uint256 accrued) {
        accrued = _claimableOfToken(tokenId);
        if (accrued > 0) {
            pointsBalance[stakerOf[tokenId]] += accrued;
            checkpointOf[tokenId] += (accrued * 1 days) / POINTS_PER_DAY;
        }
    }

    /// @notice Stake VLTG NFTs. The caller must own them and have approved
    /// this contract on the NFT contract. No lockup.
    function stake(uint256[] calldata tokenIds) external {
        require(nftContract != address(0), "NFT contract not set");
        require(tokenIds.length > 0, "no tokens");
        IERC721 nft = IERC721(nftContract);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(stakerOf[tokenId] == address(0), "already staked");
            stakerOf[tokenId] = msg.sender;
            checkpointOf[tokenId] = block.timestamp;
            _stakedIndex[tokenId] = _stakedTokens[msg.sender].length;
            _stakedTokens[msg.sender].push(tokenId);
            _totalStaked += 1;
            nft.transferFrom(msg.sender, address(this), tokenId);
            emit Staked(msg.sender, tokenId);
        }
    }

    /// @notice Unstake VLTG NFTs. Accrued points for each token are claimed
    /// into the caller's stored balance first, then the NFT is returned.
    function unstake(uint256[] calldata tokenIds) external {
        require(tokenIds.length > 0, "no tokens");
        IERC721 nft = IERC721(nftContract);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(stakerOf[tokenId] == msg.sender, "not your stake");
            _settle(tokenId);
            // swap-and-pop removal from the staker's array
            uint256 idx = _stakedIndex[tokenId];
            uint256 lastId = _stakedTokens[msg.sender][_stakedTokens[msg.sender].length - 1];
            _stakedTokens[msg.sender][idx] = lastId;
            _stakedIndex[lastId] = idx;
            _stakedTokens[msg.sender].pop();
            delete _stakedIndex[tokenId];
            delete stakerOf[tokenId];
            delete checkpointOf[tokenId];
            _totalStaked -= 1;
            nft.transferFrom(address(this), msg.sender, tokenId);
            emit Unstaked(msg.sender, tokenId);
        }
    }

    /// @notice Claim accrued points from all of the caller's staked tokens
    /// into their stored points balance.
    function claimPoints() external {
        uint256[] storage ids = _stakedTokens[msg.sender];
        uint256 total = 0;
        for (uint256 i = 0; i < ids.length; i++) {
            total += _settle(ids[i]);
        }
        emit PointsClaimed(msg.sender, total);
    }
}
