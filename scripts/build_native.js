#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT_DIR = path.resolve(__dirname, '..');
const NATIVE_DIR = path.join(ROOT_DIR, 'native', 'wg_boringtun');
const OUT_DIR = path.join(ROOT_DIR, 'entry', 'libs', 'arm64-v8a');
const SO_NAME = 'libwg_boringtun.so';
const OUT_SO_PATH = path.join(OUT_DIR, SO_NAME);
const NO_WSL = process.argv.includes('--no-wsl');

function findFile(root, fileName) {
  if (!fs.existsSync(root)) {
    return '';
  }

  const entries = fs.readdirSync(root, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(root, entry.name);
    if (entry.isDirectory()) {
      const found = findFile(fullPath, fileName);
      if (found.length > 0) {
        return found;
      }
    } else if (entry.isFile() && entry.name === fileName) {
      return fullPath;
    }
  }
  return '';
}

function hasCommand(command) {
  const checker = process.platform === 'win32' ? 'where' : 'command';
  const args = process.platform === 'win32' ? [command] : ['-v', command];
  const result = spawnSync(checker, args, {
    stdio: 'ignore',
    shell: process.platform !== 'win32'
  });
  return result.status === 0;
}

function toWslPath(windowsPath) {
  const match = /^([a-zA-Z]):\\(.*)$/.exec(windowsPath);
  if (match === null) {
    return '';
  }
  const drive = match[1].toLowerCase();
  const rest = match[2].replace(/\\/g, '/');
  return '/mnt/' + drive + '/' + rest;
}

function shellQuote(value) {
  return "'" + value.replace(/'/g, "'\\''") + "'";
}

function runWslBuild() {
  if (process.platform !== 'win32' || NO_WSL) {
    return false;
  }

  const wslRoot = toWslPath(ROOT_DIR);
  if (wslRoot.length === 0) {
    return false;
  }

  const command = 'export PATH="$HOME/.cargo/bin:/root/.cargo/bin:$PATH"; cd ' +
    shellQuote(wslRoot) + ' && bash scripts/build_native.sh';
  const result = spawnSync('wsl.exe', ['bash', '-lc', command], {
    cwd: ROOT_DIR,
    stdio: 'inherit'
  });
  if (result.error !== undefined) {
    return false;
  }
  if (result.status !== 0) {
    throw new Error('WSL native build failed with exit code ' + String(result.status));
  }
  if (!fs.existsSync(OUT_SO_PATH)) {
    throw new Error(SO_NAME + ' was not generated at ' + OUT_SO_PATH + ' by WSL build.');
  }
  return true;
}

function run() {
  if (!hasCommand('ohrs')) {
    if (fs.existsSync(OUT_SO_PATH)) {
      console.log('Using existing ' + OUT_SO_PATH);
      return;
    }
    if (runWslBuild()) {
      return;
    }
    throw new Error(
      'ohrs was not found in PATH and ' + SO_NAME + ' does not exist.\n' +
        'Install ohos-rs/ohrs, or run "bash scripts/build_native.sh" in WSL first.\n' +
        'Expected output: ' + OUT_SO_PATH
    );
  }

  const result = spawnSync('ohrs', ['build', '--release', '--arch', 'aarch'], {
    cwd: NATIVE_DIR,
    stdio: 'inherit',
    shell: process.platform === 'win32'
  });

  if (result.error !== undefined) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error('ohrs build failed with exit code ' + String(result.status));
  }

  let soPath = findFile(path.join(NATIVE_DIR, 'dist'), SO_NAME);
  if (soPath.length === 0) {
    soPath = findFile(path.join(NATIVE_DIR, 'target'), SO_NAME);
  }
  if (soPath.length === 0) {
    throw new Error(SO_NAME + ' was not found after ohrs build.');
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.copyFileSync(soPath, OUT_SO_PATH);
  console.log('Copied ' + soPath + ' to ' + OUT_SO_PATH);
}

run();
