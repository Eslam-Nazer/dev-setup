# Customizing

Everything you are likely to change is at the top of `editor/setup-dev-extensions.ps1`.

## Add or change an extension: `$Catalog`

Each entry is a slot with candidates in order of preference:

```powershell
@{ Name = 'PHPUnit runner'; Ids = @('calebporzio.better-phpunit', 'recca0120.vscode-phpunit') }
```

The first candidate that exists in the registry and is not deprecated gets installed.
`Role` marks slots the settings step needs: `keymap`, `icons`, `newfile`, `theme`.

## Presets: `$RecommendedPreset` and `$AuthorPreset`

Used when you choose "Recommended defaults" (neutral: no theme change, VS Code keymap) or "Author's preset" as the settings source.
Each holds: color scheme + theme extension, keymap base, compact UI, smooth caret, extra shortcuts.

## PhpStorm shortcuts → VS Code: `$ActionMap`

Maps an IntelliJ action id to a VS Code command and optional `when` clause.
Actions not in the map are listed in the log as skipped; add them here.

## PhpStorm color scheme → VS Code theme: `$ThemeMap`

```powershell
'poimandres' = @('pmndrs.pmndrs')
```

## Settings applied to every run

Search for `Set-Prop $s` in the settings section: breadcrumbs, command center, auto save,
Intelephense/Pint/Prettier formatter choices.
