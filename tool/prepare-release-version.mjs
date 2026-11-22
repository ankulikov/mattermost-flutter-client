import { readFile, writeFile } from 'node:fs/promises';

const [releaseVersion, buildNumber] = process.argv.slice(2);
const semanticVersionPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

if (!semanticVersionPattern.test(releaseVersion ?? '')) {
  throw new Error(`Expected a semantic release version, received: ${releaseVersion}`);
}

if (!/^[1-9]\d*$/.test(buildNumber ?? '')) {
  throw new Error(`Expected a positive build number, received: ${buildNumber}`);
}

for (const component of releaseVersion.split('.')) {
  if (Number(component) > 65535) {
    throw new Error(`Version component exceeds the Windows limit: ${component}`);
  }
}

if (Number(buildNumber) > 65535) {
  throw new Error(`Build number exceeds the cross-platform limit: ${buildNumber}`);
}

const pubspecPath = new URL('../pubspec.yaml', import.meta.url);
const pubspec = await readFile(pubspecPath, 'utf8');
const updatedPubspec = pubspec.replace(
  /^version: .+$/m,
  `version: ${releaseVersion}+${buildNumber}`,
);

if (updatedPubspec === pubspec) {
  throw new Error('pubspec.yaml does not contain a version declaration.');
}

await writeFile(pubspecPath, updatedPubspec);
