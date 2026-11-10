// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IAgentId {
    function balanceOf(address account) external view returns (uint256);
}

/// @title Volta Gent (VLTG) — pixel AI agent robots on BNB Chain.
/// @notice ERC-721 mint contract matching the public site spec (voltagent.site):
/// - MAX_SUPPLY 5,000.
/// - Phase 1 (agent phase): the first AGENT_LIMIT = 1,000 tokens are agent-only.
///   Price AGENT_PRICE = 0.0001 BNB per token, max MAX_AGENT_PER_WALLET = 2 per
///   wallet during this phase, and the wallet must hold a Binance Agent ID
///   (registry AGENT_ID_REGISTRY, balanceOf > 0, checked on-chain).
/// - Phase 2 (public): price PUBLIC_PRICE = 0.001 BNB per token, open to any
///   personal wallet. The public phase starts automatically once 1,000 tokens
///   are minted, OR earlier when the owner calls endAgentPhase() (the site FAQ
///   describes the ~7 hour agent window as owner-ended by a manual transaction;
///   there is deliberately no automatic on-chain timer).
/// - MAX_PER_WALLET = 5 total per wallet across both phases.
/// - A mint that straddles the 1,000 boundary pays per token: agent-priced for
///   the tokens inside the agent allocation, public-priced for the rest, and
///   still requires an Agent ID because it includes agent-phase tokens.
/// - Fees are HELD in the contract; the owner collects them with withdraw().
/// - Personal wallets only (msg.sender == tx.origin, contract callers rejected).
/// - tokenURI = baseURI + tokenId + ".json" (meta files are N.json, 1..5000,
///   hosted at https://voltagent.site/meta/).
/// - mintOpen defaults FALSE: the owner opens mint only after baseURI is set.
/// - Tier/rarity is fixed per token in the hosted metadata (the marketplace
///   source of truth), so this contract deliberately does NOT roll a second,
///   conflicting rarity at mint. Energy / arena economics on the site are a
///   later roadmap phase (step 05) and are not part of this mint contract.
contract VoltaGent is ERC721, Ownable {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 5000;
    uint256 public constant AGENT_LIMIT = 1000;
    uint256 public constant MAX_PER_WALLET = 5;
    uint256 public constant MAX_AGENT_PER_WALLET = 2;
    uint256 public constant AGENT_PRICE = 0.0001 ether; // BNB on BNB Smart Chain
    uint256 public constant PUBLIC_PRICE = 0.001 ether; // BNB on BNB Smart Chain

    /// @notice Binance Agent ID registry on BNB Chain. Read-only check; the
    /// registry itself is not owned or controlled by this contract.
    address public constant AGENT_ID_REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    string public baseURI;
    bool public mintOpen;
    bool public agentPhase = true;
    uint256 public totalMinted;
    mapping(address => uint256) public mintedByWallet;
    mapping(address => uint256) public agentMintedByWallet;

    event BaseURISet(string baseURI);
    event AgentPhaseEnded(uint256 totalMinted);

    constructor(string memory _baseURI) ERC721("Volta Gent", "VLTG") Ownable(msg.sender) {
        baseURI = _baseURI;
    }

    /// @notice True when `wallet` holds at least one Binance Agent ID.
    function hasAgentId(address wallet) public view returns (bool) {
        return IAgentId(AGENT_ID_REGISTRY).balanceOf(wallet) > 0;
    }

    /// @notice True while agent-phase rules still apply to the next token:
    /// the owner has not ended the phase and the 1,000 agent allocation is
    /// not exhausted yet.
    function agentPhaseActive() public view returns (bool) {
        return agentPhase && totalMinted < AGENT_LIMIT;
    }

    /// @notice How many of the next `qty` tokens (minted now) would be
    /// agent-phase tokens.
    function _agentCount(uint256 qty) internal view returns (uint256) {
        if (!agentPhaseActive()) return 0;
        uint256 remaining = AGENT_LIMIT - totalMinted;
        return qty < remaining ? qty : remaining;
    }

    /// @notice Total fee for `qty` tokens minted now, priced token by token
    /// across the phase boundary. (The Agent ID gate itself is enforced in
    /// mint(), not here.)
    function quoteFor(uint256 qty) public view returns (uint256) {
        uint256 agentCount = _agentCount(qty);
        return agentCount * AGENT_PRICE + (qty - agentCount) * PUBLIC_PRICE;
    }

    /// @notice Fee for the next single token minted now.
    function currentPrice() public view returns (uint256) {
        return agentPhaseActive() ? AGENT_PRICE : PUBLIC_PRICE;
    }

    function setBaseURI(string calldata _baseURI) external onlyOwner {
        baseURI = _baseURI;
        emit BaseURISet(_baseURI);
    }

    function setMintOpen(bool _open) external onlyOwner {
        mintOpen = _open;
    }

    /// @notice End the agent phase early (owner only). After this call every
    /// remaining token sells at public rules, even if fewer than AGENT_LIMIT
    /// tokens have been minted. Irreversible.
    function endAgentPhase() external onlyOwner {
        require(agentPhase, "phase already ended");
        agentPhase = false;
        emit AgentPhaseEnded(totalMinted);
    }

    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "empty");
        (bool ok, ) = owner().call{value: bal}("");
        require(ok, "withdraw failed");
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string(abi.encodePacked(_baseURI(), tokenId.toString(), ".json"));
    }

    function mint(uint256 qty) external payable {
        require(mintOpen, "mint closed");
        require(msg.sender == tx.origin, "no contracts");
        require(qty > 0, "qty zero");
        require(mintedByWallet[msg.sender] + qty <= MAX_PER_WALLET, "max 5 per wallet");
        require(totalMinted + qty <= MAX_SUPPLY, "supply");
        uint256 agentCount = _agentCount(qty);
        if (agentCount > 0) {
            require(hasAgentId(msg.sender), "agent phase needs Agent ID");
            require(
                agentMintedByWallet[msg.sender] + agentCount <= MAX_AGENT_PER_WALLET,
                "max 2 per wallet in agent phase"
            );
        }
        uint256 fee = agentCount * AGENT_PRICE + (qty - agentCount) * PUBLIC_PRICE;
        require(msg.value == fee, "wrong fee");
        for (uint256 i = 0; i < qty; i++) {
            totalMinted += 1;
            mintedByWallet[msg.sender] += 1;
            _safeMint(msg.sender, totalMinted);
        }
        agentMintedByWallet[msg.sender] += agentCount;
        // Fees stay in the contract; the owner collects them with withdraw().
    }
}
