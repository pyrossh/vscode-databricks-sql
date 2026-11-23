# Releasing

The extension is published to the VS Code Marketplace as `pyrossh.databricks-sql`.

- Listing: https://marketplace.visualstudio.com/items?itemName=pyrossh.databricks-sql
- Publisher management: https://marketplace.visualstudio.com/manage/publishers/pyrossh/extensions/databricks-sql/hub

## Publish a new version

```sh
npm version patch --no-git-tag-version   # or minor / major
npm test
git commit -am "Release X.Y.Z: <summary>"
git tag vX.Y.Z
npx --yes @vscode/vsce publish
git push origin main vX.Y.Z
```

The Marketplace can take a few minutes to show the new version. Check it with `npx @vscode/vsce show pyrossh.databricks-sql`.

## One-time setup: publisher and token

`vsce publish` needs a Personal Access Token (PAT) for the `pyrossh` publisher saved on the machine. Check with `npx @vscode/vsce ls-publishers`; if `pyrossh` is listed, you're set.

Otherwise:

1. Sign in at https://dev.azure.com with the Microsoft account that owns the publisher, and create an organization if prompted (any name).
2. User settings (top right) → Personal access tokens → New Token:
   - Organization: **All accessible organizations**
   - Scopes: Custom defined → Show all scopes → **Marketplace → Manage**

   Copy the token; it is shown only once.
3. Make sure the publisher exists at https://marketplace.visualstudio.com/manage/publishers with ID `pyrossh`, under the same Microsoft account. (First time only: create it at https://marketplace.visualstudio.com/manage/createpublisher.)
4. Run `npx @vscode/vsce login pyrossh` and paste the token at the prompt. Nothing shows while you paste. `vsce` stores it locally and reuses it.

Never commit the token or put it in a project file; this repo is public.

Tokens expire. When publishing fails with an authorization error, create a new token and run `vsce login pyrossh` again.

## Troubleshooting

`TF400813: The user 'aaaaaaaa-…' is not authorized to access this resource` on `vsce login` means the token was rejected outright. Usual causes, most likely first:

1. The token's Organization is a single organization instead of **All accessible organizations**. This can't be edited; create a new token.
2. The scope is missing **Marketplace → Manage** (only visible after "Show all scopes").
3. The `pyrossh` publisher doesn't exist, or belongs to a different Microsoft account than the token.
4. The token was pasted incompletely or with extra whitespace.
