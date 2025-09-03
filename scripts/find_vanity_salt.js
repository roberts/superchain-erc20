#!/usr/bin/env node
import { keccak256, getAddress, getBytes, hexlify, zeroPadValue, concat, toBeHex } from 'ethers';
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';

const PROXY_INITCODE_HASH = '0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f';

function toLowerHex(addr) {
  return '0x' + addr.toLowerCase().replace(/^0x/, '');
}

function create2Address(deployer, salt, initCodeHash) {
  const parts = [new Uint8Array([0xff]), getBytes(deployer), getBytes(zeroPadValue(salt, 32)), getBytes(initCodeHash)];
  const digest = keccak256(concat(parts));
  return '0x' + digest.slice(26);
}

function predictCreate3(deployer, salt) {
  const proxy = create2Address(deployer, salt, PROXY_INITCODE_HASH);
  const proxyBytes = getBytes(proxy);
  // Compute keccak256( RLP([proxy, 1]) ) where encoding is fixed:
  // 0xd6 0x94 <20-byte proxy> 0x01
  const fixed = new Uint8Array(2 + 20 + 1);
  fixed[0] = 0xd6;
  fixed[1] = 0x94;
  fixed.set(proxyBytes, 2);
  fixed[fixed.length - 1] = 0x01;
  const digest = keccak256(fixed);
  return getAddress('0x' + digest.slice(26));
}

function formatSalt(i) {
  if (typeof i === 'bigint') return toBeHex(i, 32);
  return toBeHex(BigInt(i), 32);
}

function searchRange({ deployer, prefix, suffix, start, count }) {
  const targetPrefix = (prefix || '').toLowerCase();
  const targetSuffix = (suffix || '').toLowerCase();
  let s = BigInt(start);
  const end = s + BigInt(count);
  for (; s < end; s++) {
    const salt = formatSalt(s);
    const addr = toLowerHex(predictCreate3(deployer, salt));
    const hex = addr.slice(2);
    if (hex.startsWith(targetPrefix) && hex.endsWith(targetSuffix)) {
      return { salt, address: addr, checked: s.toString() };
    }
  }
  return null;
}

if (!isMainThread) {
  const res = searchRange(workerData);
  parentPort.postMessage(res);
} else {
  // Main thread: parse args and optionally spawn workers.
  const args = Object.fromEntries(process.argv.slice(2).map(a => {
    const m = a.match(/^--([^=]+)=(.*)$/);
    return m ? [m[1], m[2]] : [a.replace(/^--/, ''), true];
  }));

  if (!args.deployer || !args.prefix || !args.suffix) {
    console.error('Usage: node find_vanity_salt.js --deployer 0x... --prefix ab --suffix 12345 [--start 0] [--count 100000000] [--workers 8]');
    process.exit(1);
  }

  const deployer = getAddress(args.deployer);
  const prefix = args.prefix;
  const suffix = args.suffix;
  const start = BigInt(args.start ?? 0);
  const count = BigInt(args.count ?? 10_000_000);
  const workers = Math.max(1, Number(args.workers ?? 1));

  if (workers === 1) {
    const res = searchRange({ deployer, prefix, suffix, start, count });
    if (res) {
      console.log(`Match found: SALT3=${res.salt} ADDRESS=${res.address}`);
      process.exit(0);
    }
    console.error('No match in the given range.');
    process.exit(1);
  }

  // Split the range across workers.
  const chunk = count / BigInt(workers);
  let pending = workers;
  let done = false;
  for (let i = 0n; i < BigInt(workers); i++) {
    const wStart = start + i * chunk;
    const wCount = (i === BigInt(workers - 1)) ? (count - chunk * i) : chunk;
    const worker = new Worker(new URL(import.meta.url), { workerData: { deployer, prefix, suffix, start: wStart.toString(), count: wCount.toString() } });
    worker.on('message', (res) => {
      pending--;
      if (res && !done) {
        done = true;
        console.log(`Match found: SALT3=${res.salt} ADDRESS=${res.address}`);
        // Terminate all workers quickly.
        worker.terminate();
        process.exit(0);
      } else if (pending === 0 && !done) {
        console.error('No match in the given range.');
        process.exit(1);
      }
    });
    worker.on('error', (e) => {
      pending--;
      if (pending === 0 && !done) {
        console.error('Worker error:', e);
        process.exit(1);
      }
    });
  }
}
