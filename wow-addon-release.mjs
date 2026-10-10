#!/usr/bin/env node
// wow-addon-release — one command from code to CurseForge.
//
// Runs the full quality gate (lint + harness + sim), bumps the version,
// builds the zip, tags, creates the GitHub release, and prepares the
// CurseForge upload. The only manual step left is the file picker click.
//
// Usage:
//   node wow-addon-release.mjs <addon-dir> [--major|--minor|--patch] [--dry]

import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const args = process.argv.slice(2);
const addonDir = args[0];
const dry = args.includes('--dry');
const bumpType = args.includes('--major') ? 'major' : args.includes('--minor') ? 'minor' : 'patch';

if (!addonDir) {
    console.error('usage: node wow-addon-release.mjs <addon-dir> [--major|--minor|--patch] [--dry]');
    process.exit(2);
}

const log = (...a) => console.log(...a);
const sh = (cmd, opts = {}) => {
    try {
        return execSync(cmd, { encoding: 'utf8', cwd: opts.cwd || addonDir, stdio: opts.silent ? 'pipe' : 'inherit' });
    } catch (e) {
        if (!opts.ok) throw e;
        return null;
    }
};

// ---------------------------------------------------------------------------
// read state

const tocFile = fs.readdirSync(addonDir).find(f => f.toLowerCase().endsWith('.toc'));
if (!tocFile) throw new Error(`no .toc in ${addonDir}`);
const tocPath = path.join(addonDir, tocFile);
const tocText = fs.readFileSync(tocPath, 'utf8');
const meta = {};
for (const line of tocText.split('\n')) {
    const m = line.match(/^##\s*(\w+):\s*(.*)/);
    if (m) meta[m[1]] = m[2];
}
const addonName = meta.Title || path.basename(addonDir);
const currentVersion = meta.Version || '0.0.0';
const repoName = sh(`gh repo view --json name --jq .name`, { silent: true })?.trim() || path.basename(addonDir);

// bump
const [ma, mi, pa] = currentVersion.split('.').map(Number);
const newVersion = bumpType === 'major' ? `${ma + 1}.0.0` : bumpType === 'minor' ? `${ma}.${mi + 1}.0` : `${ma}.${mi}.${pa + 1}`;

log(`\n${'='.repeat(60)}`);
log(`RELEASING: ${addonName} ${currentVersion} → ${newVersion}`);
log(`Repo: Booyaka101/${repoName}`);
if (dry) log('** DRY RUN — no changes will be made **');
log('='.repeat(60));

// ---------------------------------------------------------------------------
// gate 1: fengari harness

log('\n── Gate 1: Unit tests (fengari harness) ──');
if (fs.existsSync(path.join(addonDir, 'package.json'))) {
    sh('npm test', { cwd: addonDir });
    log('  ✓ harness passed');
} else {
    log('  - no package.json, skipping');
}

// ---------------------------------------------------------------------------
// gate 2: wow-secret-lint

log('\n── Gate 2: Static analysis (wow-secret-lint) ──');
const linterPath = path.join(addonDir, '..', 'wow-secret-lint', 'bin', 'wow-secret-lint.mjs');
if (fs.existsSync(linterPath)) {
    const result = sh(`node "${linterPath}" .`, { cwd: addonDir, silent: true });
    if (result && !result.includes('error')) {
        log('  ✓ linter clean');
    } else {
        log(result);
        if (!dry) throw new Error('linter found issues');
    }
} else {
    log('  - wow-secret-lint not found as sibling, skipping');
}

// ---------------------------------------------------------------------------
// gate 3: wow-addon-sim

log('\n── Gate 3: Runtime simulation (wow-addon-sim) ──');
const simPath = path.join(addonDir, '..', 'wow-addon-sim', 'wow-addon-sim.mjs');
if (fs.existsSync(simPath)) {
    const result = sh(`node "${simPath}" .`, { cwd: addonDir, silent: true });
    if (result && result.includes('CLEAN')) {
        log('  ✓ simulation clean');
    } else {
        log(result);
        if (!dry) throw new Error('simulation found errors');
    }
} else {
    log('  - wow-addon-sim not found as sibling, skipping');
}

// ---------------------------------------------------------------------------
// bump version

if (!dry) {
    const updated = tocText.replace(`## Version: ${currentVersion}`, `## Version: ${newVersion}`);
    fs.writeFileSync(tocPath, updated);
    log(`\n✓ TOC bumped to ${newVersion}`);
}

// ---------------------------------------------------------------------------
// build zip

log('\n── Building distributable ──');
const files = [];
for (const line of tocText.split('\n')) {
    const t = line.trim();
    if (t && !t.startsWith('#') && !t.startsWith('##')) files.push(t.replace(/\\/g, '/'));
}
const stageDir = path.join(process.env.TEMP || '/tmp', `addon-release-${Date.now()}`, path.basename(addonDir));
fs.mkdirSync(stageDir, { recursive: true });
const copyFiles = [tocFile, ...files, 'README.md', 'LICENSE'].filter(f => fs.existsSync(path.join(addonDir, f)));
for (const f of copyFiles) {
    fs.copyFileSync(path.join(addonDir, f), path.join(stageDir, f));
}
const zipName = `${addonName}-${newVersion}.zip`;
const zipPath = path.join(path.dirname(stageDir), zipName);
execSync(`Compress-Archive -Path "${stageDir}" -DestinationPath "${zipPath}" -Force`, { shell: 'powershell' });
const zipSize = Math.round(fs.statSync(zipPath).size / 1024);
log(`  ✓ ${zipName} (${zipSize} KB) — ${copyFiles.length} files`);
if (dry) log(`  (dry run: zip at ${zipPath})`);

// ---------------------------------------------------------------------------
// git commit + tag + push

if (!dry) {
    log('\n── Git ──');
    sh(`git add -A`);
    sh(`git -c user.name="Booyaka101" -c user.email="booyaka101@users.noreply.github.com" commit -m "${newVersion}: released via wow-addon-release"`);
    sh('git push');
    sh(`git tag v${newVersion}`);
    sh(`git push origin v${newVersion}`);
    log(`  ✓ committed, tagged v${newVersion}, pushed`);
}

// ---------------------------------------------------------------------------
// GitHub release

if (!dry) {
    log('\n── GitHub release ──');
    const releaseNotes = `Released via wow-addon-release.\n\nChanges in ${newVersion}:\n- See [commit history](https://github.com/Booyaka101/${repoName}/commits/v${newVersion})\n`;
    const notesFile = path.join(path.dirname(zipPath), 'release-notes.md');
    fs.writeFileSync(notesFile, releaseNotes);
    sh(`gh release create v${newVersion} --title "v${newVersion}: ${addonName}" --notes-file "${notesFile}" "${zipPath}"`);
    log(`  ✓ GitHub release created`);
}

// ---------------------------------------------------------------------------
// summary

log('\n' + '='.repeat(60));
log('RELEASE COMPLETE');
log(`  ${addonName} v${newVersion}`);
log(`  Zip: ${zipName} (${zipSize} KB)`);
if (!dry) {
    log(`  GitHub: https://github.com/Booyaka101/${repoName}/releases/tag/v${newVersion}`);
    log(`  Zip path for CurseForge: ${zipPath}`);
}
log('='.repeat(60));
if (dry) log('\n(dry run — nothing was committed, tagged, or released)');

// clean up stage
if (!dry) {
    try { fs.rmSync(path.dirname(stageDir), { recursive: true }); } catch {}
}
