import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import vsctm from 'vscode-textmate';
import onig from 'vscode-oniguruma';

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// Lakeflow SQL fixtures copied from a real pipeline; set DBSQL_SQL_DIR to test against a live src_sql/ instead.
const pipelineDir = process.env.DBSQL_SQL_DIR ? path.resolve(process.env.DBSQL_SQL_DIR) : path.join(root, 'test/fixtures/src_sql');

const wasm = fs.readFileSync(require.resolve('vscode-oniguruma/release/onig.wasm')).buffer;
const onigLib = onig.loadWASM(wasm).then(() => ({
  createOnigScanner: (p) => new onig.OnigScanner(p),
  createOnigString: (s) => new onig.OnigString(s),
}));
const registry = new vsctm.Registry({
  onigLib,
  loadGrammar: async (scope) => scope === 'source.databricks-sql'
    ? vsctm.parseRawGrammar(fs.readFileSync(path.join(root, 'syntaxes/databricks-sql.tmLanguage.json'), 'utf8'), 'g.json')
    : null,
});

function walk(d) {
  return fs.readdirSync(d, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(path.join(d, e.name)) : e.name.endsWith('.sql') ? [path.join(d, e.name)] : []);
}

// Returns [{line, text, scopes[], lineEndDepth}] tokens per line.
function tokenize(grammar, text) {
  let stack = vsctm.INITIAL;
  const out = [];
  text.split(/\r?\n/).forEach((line, i) => {
    const r = grammar.tokenizeLine(line, stack);
    for (const t of r.tokens) out.push({ line: i + 1, text: line.slice(t.startIndex, t.endIndex), scopes: t.scopes });
    stack = r.ruleStack;
    out.push({ line: i + 1, eol: true, depth: stack.depth });
  });
  return out;
}

const grammar = await registry.loadGrammar('source.databricks-sql');
const sample = tokenize(grammar, fs.readFileSync(path.join(root, 'samples/kitchen-sink.dbsql'), 'utf8'));

function has(tokens, text, scopeFragment) {
  return tokens.some((t) => !t.eol && t.text === text && t.scopes.some((s) => s.includes(scopeFragment)));
}

test('(a) grammar loads and every regex compiles', () => {
  assert.ok(grammar, 'grammar loaded');
  assert.ok(sample.length > 100);
});

test('(b) spot tokens have expected scopes', () => {
  const cases = [
    ['CREATE OR REFRESH', 'keyword.other.lakeflow'],
    ['STREAMING TABLE', 'keyword.other.lakeflow'],
    ['MATERIALIZED VIEW', 'keyword.other.lakeflow'],
    ['id_present', 'entity.name.constraint'],
    ['ON VIOLATION DROP ROW', 'keyword.other.lakeflow'],
    ['ON VIOLATION FAIL UPDATE', 'keyword.other.lakeflow'],
    ['${my_pipeline.landing_root}', 'variable.other.substitution'],
    ['DECIMAL', 'storage.type'],
    ['try_cast', 'support.function.builtin'],
    ['my_udf', 'entity.name.function'],
    ['-- Kitchen sink for the Databricks SQL grammar', 'comment.line'],
    ["'bronze'", 'string.quoted.single'],
    ['main.${my_pipeline.schema}.events_raw', 'entity.name.type'],
    ['STORED AS SCD TYPE 2', 'keyword.other.lakeflow'],
    ['COLUMNS * EXCEPT', 'keyword.other.lakeflow'],
    ['QUALIFY', 'keyword.control'],
    ['::', 'keyword.operator.cast'],
    ['||', 'keyword.operator.concatenation'],
    ['10L', 'constant.numeric'],
    ['1.5BD', 'constant.numeric'],
    ['NULL', 'constant.language'],
  ];
  for (const [text, scope] of cases) {
    // multi-token expectations (names containing substitutions) are checked by joined text
    const ok = has(sample, text, scope) ||
      sample.filter((t) => !t.eol && t.scopes.some((s) => s.includes(scope))).map((t) => t.text).join('').includes(text.replace(/\s+/g, ' ')) ||
      sample.filter((t) => !t.eol && t.scopes.some((s) => s.includes(scope))).map((t) => t.text).join('|').includes(text);
    assert.ok(ok, `expected ${JSON.stringify(text)} to carry ${scope}`);
  }
  // substitution highlighted inside a string
  assert.ok(sample.some((t) => !t.eol && t.text === '${my_pipeline.landing_root}' && t.scopes.some((s) => s.includes('string.quoted'))));
});

const files = walk(pipelineDir);
test('pipeline SQL files found', () => assert.ok(files.length >= 10, `found ${files.length}`));

for (const f of files) {
  test(`(c) no unterminated string/comment: ${path.relative(pipelineDir, f)}`, () => {
    const toks = tokenize(grammar, fs.readFileSync(f, 'utf8'));
    const bad = toks.filter((t) => t.eol && t.depth !== 1);
    assert.deepEqual(bad.map((b) => b.line), [], 'lines ending inside a nested scope');
    // sanity: file has keyword tokens
    assert.ok(toks.some((t) => !t.eol && t.scopes.some((s) => s.includes('keyword.other.lakeflow'))));
  });
}

test('real files: key tokens', () => {
  const toks = tokenize(grammar, fs.readFileSync(path.join(pipelineDir, 'silver/transactions.sql'), 'utf8'));
  assert.ok(has(toks, 'txn_id_present', 'entity.name.constraint'));
  assert.ok(has(toks, 'transactions_checked', 'entity.name.type'));
  assert.ok(has(toks, 'try_cast', 'support.function.builtin'));
});

test('=> and >= share the same operator scope', () => {
  const toks = tokenize(grammar, "SELECT * FROM read_files('x', format => 'csv') WHERE a >= 1;");
  const scopeOf = (text) => toks.find((t) => !t.eol && t.text === text)?.scopes.at(-1);
  assert.equal(scopeOf('=>'), 'keyword.operator.comparison.databricks-sql');
  assert.equal(scopeOf('=>'), scopeOf('>='));
});

test('language-configuration has no angle brackets in brackets/colorizedBracketPairs', () => {
  const cfg = JSON.parse(fs.readFileSync(path.join(root, 'language-configuration.json'), 'utf8'));
  assert.ok(Array.isArray(cfg.colorizedBracketPairs));
  for (const key of ['brackets', 'colorizedBracketPairs']) {
    for (const pair of cfg[key]) {
      assert.ok(!pair.includes('<') && !pair.includes('>'), `${key} contains angle bracket`);
    }
  }
});
