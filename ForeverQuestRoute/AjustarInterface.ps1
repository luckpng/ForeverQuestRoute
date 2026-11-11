param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(10000, 999999)]
    [int]$InterfaceVersion
)

$manifestPath = Join-Path $PSScriptRoot 'ForeverQuestRoute.toc'
$content = Get-Content -LiteralPath $manifestPath -Raw
$updated = $content -replace '(?m)^## Interface: \d+', "## Interface: $InterfaceVersion"
Set-Content -LiteralPath $manifestPath -Value $updated -Encoding utf8 -NoNewline
Write-Output "Manifesto atualizado para Interface $InterfaceVersion. Reinicie o jogo ou use /reload."
