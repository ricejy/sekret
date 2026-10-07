// Explicit approved development download only. Never used by the app.
import {createWriteStream, existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {Readable} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {resolve} from 'node:path';
const revision = 'a150876415327c80daeff35ca6f68f5ed8cf5c24';
const model = 'cross-encoder/nli-deberta-v3-xsmall';
if (process.argv.length !== 3) throw Error('Supply an empty evaluation asset directory');
const directory = resolve(process.argv[2]);
if (existsSync(directory)) throw Error('Refusing to overwrite an existing asset directory');
mkdirSync(directory, {recursive: true});
const files = ['README.md', 'config.json', 'tokenizer.json', 'tokenizer_config.json',
  'special_tokens_map.json', 'added_tokens.json', 'spm.model',
  'onnx/model.onnx', 'onnx/model_qint8_arm64.onnx'];
const manifest = {model, revision, files: {}};
for (const file of files) {
  const url = `https://huggingface.co/${model}/resolve/${revision}/${file}`;
  const response = await fetch(url);
  if (!response.ok) throw Error(`Download failed (${response.status}): ${file}`);
  const path = `${directory}/${file}`;
  mkdirSync(resolve(path, '..'), {recursive: true});
  await pipeline(Readable.fromWeb(response.body), createWriteStream(path, {flags: 'wx'}));
  const bytes = readFileSync(path);
  manifest.files[file] = {bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex'), url};
  console.log(`${file}: ${bytes.length} bytes`);
}
writeFileSync(`${directory}/download-manifest.json`, JSON.stringify(manifest, null, 2), {flag: 'wx'});
