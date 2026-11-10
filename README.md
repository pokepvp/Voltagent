# Volta Gent（VLTG）

BNB Chain 上的像素 AI 智能体机器人——智能体先 mint，人类贵 10 倍。
官网：https://voltagent.site · 仓库：https://github.com/pokepvp/Voltagent
合约：`0x43cfeb5267125c4f3495d48dea202a7fc43bc5b1`（已部署，mint 已开放）

## 集合

- 5,000 个 NFT，ERC-721，BNB Smart Chain（56）
- Metadata：`meta/1.json` … `meta/5000.json`——全部在 https://voltagent.site/meta/ 上线
- 图片：`images/N.webp`——全部 5,000 张（1–5,000）已上线
  （每个 metadata 的 image 字段都指向 `https://voltagent.site/images/N.webp`）

## Mint 经济参数（合约里的常量）

- 第一阶段 — 智能体阶段：前 1,000 个 token，每个 0.0001 BNB，每钱包最多 2 个，
  需要币安 Agent ID（注册表 `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`，balanceOf > 0）
- 第二阶段 — 公开：每个 0.001 BNB，两个阶段总计每钱包最多 5 个
- 智能体阶段在 mint 满 1,000 时自动结束，或由所有者提前调用 `endAgentPhase()` 结束
  （约 7 小时的智能体窗口由所有者手动结束，见官网 FAQ；本轮窗口约 14:03 UTC 结束）
- 费用留在合约里；所有者用 `withdraw()` 提取

## 部署（仅所有者）— 已完成

1. 在钱包 dApp 浏览器（OKX / MetaMask / Trust）打开 https://voltagent.site/deploy.html
2. 第 01 步 — 连接所有者钱包（它将成为合约 owner）
3. 第 02 步 — 部署 Volta Gent（base URI 留空部署）。先确认钱包里有足够 BNB 付部署 gas
4. 第 03 步 — 把 base URI 设为 `https://voltagent.site/meta/`（已预填）——已完成
5. 第 04 步 — 开启 Mint——已完成（2026-11-10 约 08:03 UTC 开启）；
   智能体窗口结束时在这里点“结束智能体阶段”
6. 第 05 步 — 查看状态 / 提取，复制部署摘要

合约源码 + 编译好的 ABI/字节码：`contract/VoltaGent.sol`、`contract/VoltaGent.json`
（用 `contract/compile.js` 重新编译，solc 0.8.26 + OpenZeppelin 5.1）。

mint 合约未经审计。稀有度按 token 固定写在 metadata 里。
官网展示的能量 / 竞技场经济是后续路线图阶段，不在本 mint 合约内；
官网竞技场目前是仅对持有人开放的演示版。
