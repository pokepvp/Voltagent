const fs = require('fs');
const path = require('path');
const NODE_MODULES = '/home/hatch/workspace/talvio-generator-work/contract/node_modules';
const solc = require(path.join(NODE_MODULES, 'solc'));
const { keccak256 } = require(path.join(NODE_MODULES, 'js-sha3'));

const sources = {
  'VoltaToken.sol': { content: fs.readFileSync(path.join(__dirname, 'VoltaToken.sol'), 'utf8') },
  'VoltaMining.sol': { content: fs.readFileSync(path.join(__dirname, 'VoltaMining.sol'), 'utf8') }
};
const input = { language: 'Solidity', sources, settings: { optimizer: { enabled: true, runs: 200 }, outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object', 'evm.deployedBytecode.object'] } } } };
const output = JSON.parse(solc.compile(JSON.stringify(input)));
if (output.errors) { for (const e of output.errors) console.log(e.severity, e.formattedMessage || e.message); if (output.errors.some(e => e.severity === 'error')) process.exit(1); }

function selector(sig) { return '0x' + keccak256(sig).slice(0, 8); }

const jobs = [
  { file: 'VoltaToken.sol', name: 'VoltaToken', json: 'VoltaToken.json',
    watch: ['transfer(address,uint256)', 'balanceOf(address)', 'approve(address,uint256)', 'transferFrom(address,address,uint256)', 'allowance(address,address)', 'totalSupply()', 'name()', 'symbol()', 'decimals()'] },
  { file: 'VoltaMining.sol', name: 'VoltaMining', json: 'VoltaMining.json',
    watch: ['startMining(uint256)', 'claim(uint256)', 'accruedOf(uint256)', 'lastClaimOf(uint256)', 'lastClaim(uint256)', 'reserve()', 'ratePerHour()', 'setRatePerHour(uint256)', 'withdrawTokens(uint256)', 'nft()', 'token()', 'owner()', 'MIN_CLAIM()', 'MAX_ACCRUAL_SECONDS()'] }
];

let failed = false;
for (const job of jobs) {
  const c = output.contracts[job.file][job.name];
  fs.writeFileSync(path.join(__dirname, job.json), JSON.stringify({ abi: c.abi, bytecode: '0x' + c.evm.bytecode.object, deployedBytecode: '0x' + c.evm.deployedBytecode.object }, null, 2));
  console.log(job.name, 'CREATION_BYTES', c.evm.bytecode.object.length / 2, 'DEPLOYED_BYTES', c.evm.deployedBytecode.object.length / 2);
  console.log(job.name, 'FUNCTIONS', c.abi.filter(x => x.type === 'function').map(x => x.name).join(','));
  const deployed = c.evm.deployedBytecode.object;
  for (const sig of job.watch) {
    const sel = selector(sig);
    const inAbi = c.abi.some(x => x.type === 'function' && (x.name + '(' + (x.inputs || []).map(i => i.type).join(',') + ')') === sig);
    const inDispatch = deployed.includes(sel.slice(2));
    console.log(job.name, 'SELECTOR', sig, sel, 'abi:' + (inAbi ? 'yes' : 'NO'), 'dispatch:' + (inDispatch ? 'yes' : 'NO'));
    if (!inAbi || !inDispatch) failed = true;
  }
}
if (failed) { console.error('SELECTOR CHECK FAILED'); process.exit(1); }
console.log('OK');
