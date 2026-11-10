# Volta Gent (VLTG)

Pixel AI agent robots on BNB Chain — agents mint first, humans pay 10×.
Site: https://voltagent.site · Repo: https://github.com/pokepvp/Voltagent

## Collection

- 5,000 NFTs, ERC-721, BNB Smart Chain (56)
- Metadata: `meta/1.json` … `meta/5000.json` — all live at https://voltagent.site/meta/
- Images: `images/N.webp` — 1–4,650 live; **4,651–5,000 still to be uploaded**
  (metadata for those tokens already points at `https://voltagent.site/images/N.webp`)

## Mint economics (constants in the contract)

- Phase 1 — agent phase: first 1,000 tokens, 0.0001 BNB each, max 2 per wallet,
  Binance Agent ID required (registry `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`, balanceOf > 0)
- Phase 2 — public: 0.001 BNB each, max 5 per wallet in total across both phases
- The agent phase ends automatically at 1,000 minted, or early when the owner
  calls `endAgentPhase()` (the ~7 hour agent window is owner-ended, per the site FAQ)
- Fees stay in the contract; the owner withdraws them with `withdraw()`

## Deploy (owner only)

1. Open https://voltagent.site/deploy.html in a wallet dApp browser (OKX / MetaMask / Trust).
2. Step 01 — connect the owner wallet (it becomes the contract owner).
3. Step 02 — Deploy Volta Gent (deploy with an empty base URI). Make sure the
   wallet holds enough BNB for the deploy gas first.
4. Step 03 — Set base URI to `https://voltagent.site/meta/` (prefilled).
5. Step 04 — Open Mint. Use End Agent Phase here when the agent window is over.
6. Step 05 — check state / withdraw, copy the deployment summary and send it to
   Muse so the public site (index.html) can be wired to the live contract.

Contract source + compiled ABI/bytecode: `contract/VoltaGent.sol`, `contract/VoltaGent.json`
(rebuild with `contract/compile.js`, solc 0.8.26 + OpenZeppelin 5.1).

The mint contract is unaudited. Tier/rarity is fixed per token in the metadata.
Energy / arena economics shown on the site are a later roadmap phase and are
not part of this mint contract.
