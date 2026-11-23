# Databricks SQL (Lakeflow)

TextMate syntax highlighting for Databricks SQL, including the Lakeflow Declarative Pipelines dialect. Declarative only: no activation code.

## Install

From the [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=pyrossh.databricks-sql): search for "Databricks SQL (Lakeflow)" in the Extensions view, or run:

```sh
code --install-extension pyrossh.databricks-sql
```

## What it highlights

- Comments (`--`, `/* */`), strings, backtick identifiers, numbers (`10L`, `1.5BD`, exponents).
- `${...}` pipeline config substitution, including inside strings.
- Lakeflow DDL: `CREATE OR REFRESH STREAMING TABLE`, `MATERIALIZED VIEW`, `LIVE VIEW`, `CREATE FLOW`, `AUTO CDC INTO`, `KEYS`, `SEQUENCE BY`, `STORED AS SCD TYPE 1|2`, `APPLY AS DELETE WHEN`, `COLUMNS * EXCEPT`, `TRACK HISTORY ON`, `CONSTRAINT name EXPECT (...) ON VIOLATION DROP ROW | FAIL UPDATE`, `CLUSTER BY [AUTO]`, `TBLPROPERTIES`, `STREAM(...)`, `LIVE.` prefix and more.
- Dataset names after `CREATE ... TABLE/VIEW/FLOW` (`catalog.schema.name`, backticks, `${...}.name`).
- General Spark/Databricks SQL keywords, DDL/DCL, types (including nested `ARRAY<>`, `MAP<,>`, `STRUCT<a: t>`), built-in functions, other function calls, `::`, `:` JSON path, `||`, comparison and arithmetic operators.

## How files get the language

- Any `**/src_sql/**/*.sql` file is picked up automatically (other `.sql` files keep the default SQL mode).
- Files ending in `.dbsql`.
- Any other file: Command Palette, "Change Language Mode", "Databricks SQL".

Files in this language get their own file icon (`icons/databricks-sql.svg`) in the Explorer and tabs. The active file icon theme wins if it maps the file's name or extension itself; with the default Seti theme the Databricks icon shows.

## Reinstall after edits

```sh
cd vscode-databricks-sql
npm install
npm test
npx --yes @vscode/vsce package
code --install-extension "databricks-sql-$(node -p "require('./package.json').version").vsix" --force
```

Then run "Developer: Reload Window". Check with `code --list-extensions | grep -i databricks-sql`.

## Known limits

TextMate is regex based: keyword-vs-identifier decisions are lexical (for example a column named `day` is coloured as a keyword), and `<`/`>` inside `ARRAY<...>` rely on matching the closing `>`.

## Development

```sh
npm ci && npm test
```

Tests use Lakeflow SQL fixtures in `test/fixtures/src_sql`. Set `DBSQL_SQL_DIR=/path/to/src_sql` to test against a live pipeline.

To publish a new version to the Marketplace, see [RELEASING.md](RELEASING.md).
