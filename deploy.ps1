# для запуска деплоя
Get-Content .env | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        $name  = $matches[1].Trim()
        $value = $matches[2].Trim()
        [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

Write-Host "Deploying to Arbitrum Sepolia..." -ForegroundColor Cyan
Write-Host "Deployer: $env:DEPLOYER_PRIVATE_KEY" -ForegroundColor Gray

forge script script/Deploy.s.sol:Deploy `
    --rpc-url $env:ARBITRUM_SEPOLIA_RPC_URL `
    --broadcast `
    --verify `
    --etherscan-api-key $env:ARBISCAN_API_KEY `
    -vvvv

Write-Host "Done!" -ForegroundColor Green