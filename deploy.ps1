$repoRoot = "D:\Jeux\addonDev\Atlasloot\AtlasLootA"
$addonName = "AtlasLoot_Worldforged"
$src = Join-Path $repoRoot $addonName
$dst = "D:\Jeux\Ascension Launcher\resources\ascension_ptr\Interface\AddOns\$addonName"

if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }

$exclude = @('.git', 'deploy.ps1', '.gitignore', '*.md')

Get-ChildItem -Path $src -Recurse | Where-Object {
    $name = $_.Name
    -not ($_.PSIsContainer) -and -not ($exclude | Where-Object { $name -like $_ })
} | ForEach-Object {
    # Preserve relative sub-path inside the addon folder
    $rel     = $_.FullName.Substring($src.Length).TrimStart('\')
    $target  = Join-Path $dst $rel
    $dir     = Split-Path $target -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    Copy-Item -Path $_.FullName -Destination $target -Force
    Write-Host "Copied: $rel"
}

Write-Host "Done -- $addonName deployed to Interface/AddOns."
