const fs = require('fs');
const path = require('path');
const NODE_MODULES = '/home/hatch/workspace/talvio-generator-work/contract/node_modules';
const solc = require(path.join(NODE_MODULES, 'solc'));
const sources = { 'VoltaArena.sol': { content: fs.readFileSync(path.join(__dirname, 'VoltaArena.sol'), 'utf8') } };
const input = { language: 'Solidity', sources, settings: { optimizer: { enabled: true, runs: 200 }, outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object', 'evm.deployedBytecode.object'] } } } };
const output = JSON.parse(solc.compile(JSON.stringify(input)));
if (output.errors) { for (const e of output.errors) console.log(e.severity, e.formattedMessage || e.message); if (output.errors.some(e => e.severity === 'error')) process.exit(1); }
const c = output.contracts['VoltaArena.sol']['VoltaArena'];
fs.writeFileSync(path.join(__dirname, 'VoltaArena.json'), JSON.stringify({ abi: c.abi, bytecode: '0x' + c.evm.bytecode.object, deployedBytecode: '0x' + c.evm.deployedBytecode.object }, null, 2));
console.log('VoltaArena', 'CREATION_BYTES', c.evm.bytecode.object.length / 2, 'DEPLOYED_BYTES', c.evm.deployedBytecode.object.length / 2);
console.log('FUNCTIONS', c.abi.filter(x => x.type === 'function').map(x => x.name).join(','));
console.log('OK');
