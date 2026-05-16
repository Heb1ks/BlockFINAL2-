#верификация
Get-Content .env | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), "Process")
    }
}

$deployer = "0xb914Baa3d17f129c02B8103a9011AF7c60a56254"
$verifierUrl = "https://api.etherscan.io/v2/api?chainid=421614"

$contracts = @(
    @{ addr="0x4b733e9e1328F5b7FE865cA87cb073f98A12195f"; name="src/GameToken.sol:GameToken";           args=$(cast abi-encode "constructor(address)" $deployer) },
    @{ addr="0xAe867dF3d109e54FC5E56b5a89661F353CcC9C46"; name="src/GameItems.sol:GameItems";           args="" },
    @{ addr="0x4B3b639da23fd9765A106E45a02f6C4F9C86d9fF"; name="src/GameFactory.sol:GameFactory";       args=$(cast abi-encode "constructor(address)" $deployer) },
    @{ addr="0x36E6D1a755c9b81c24C138f4c3FbaCeBe2AbEdB5"; name="src/GameAMM.sol:GameAMM";               args="" },
    @{ addr="0x642F030B5aB0a6d8Bcf6700f328bbD82DD8F821f"; name="src/GameVault.sol:GameVault";           args="" },
    @{ addr="0x3A05363578B06a92fCFa7A2C8C57684f72F89B5c"; name="src/NFTRentalVault.sol:NFTRentalVault"; args="" },
    @{ addr="0x38Fd68F4b1DF77937a05F268952f885Bf73dE97E"; name="src/LootDrop.sol:LootDrop";             args="" }
)

foreach ($c in $contracts) {
    Write-Host "Verifying $($c.name)..." -ForegroundColor Cyan
    if ($c.args -ne "") {
        forge verify-contract $c.addr $c.name `
            --rpc-url $env:ARBITRUM_SEPOLIA_RPC_URL `
            --etherscan-api-key $env:ARBISCAN_API_KEY `
            --verifier-url $verifierUrl `
            --constructor-args $c.args `
            --compiler-version 0.8.34 `
            --optimizer-runs 200
    } else {
        forge verify-contract $c.addr $c.name `
            --rpc-url $env:ARBITRUM_SEPOLIA_RPC_URL `
            --etherscan-api-key $env:ARBISCAN_API_KEY `
            --verifier-url $verifierUrl `
            --compiler-version 0.8.34 `
            --optimizer-runs 200
    }
}

Write-Host "All done!" -ForegroundColor Green