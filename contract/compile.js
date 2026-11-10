const fs = require('fs');
const path = require('path');
const NODE_MODULES = '/home/hatch/workspace/talvio-generator-work/contract/node_modules';
const solc = require(path.join(NODE_MODULES, 'solc'));
const sources = { 'VoltaGent.sol': { content: fs.readFileSync(path.join(__dirname, 'VoltaGent.sol'), 'utf8') } };
const input = { language: 'Solidity', sources, settings: { optimizer: { enabled: true, runs: 200 }, outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object', 'evm.deployedBytecode.object'] } } } };
function findImports(p) { const full = path.join(NODE_MODULES, p); if (fs.existsSync(full)) return { contents: fs.readFileSync(full, 'utf8') }; return { error: 'File not found: ' + p }; }
const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImports }));
if (output.errors) { for (const e of output.errors) console.log(e.severity, e.formattedMessage || e.message); if (output.errors.some(e => e.severity === 'error')) process.exit(1); }
const c = output.contracts['VoltaGent.sol']['VoltaGent'];
fs.writeFileSync(path.join(__dirname, 'VoltaGent.json'), JSON.stringify({ abi: c.abi, bytecode: '0x' + c.evm.bytecode.object, deployedBytecode: '0x' + c.evm.deployedBytecode.object }, null, 2));
console.log('VoltaGent', 'CREATION_BYTES', c.evm.bytecode.object.length / 2, 'DEPLOYED_BYTES', c.evm.deployedBytecode.object.length / 2);
console.log('FUNCTIONS', c.abi.filter(x => x.type === 'function').map(x => x.name).join(','));
console.log('OK');
