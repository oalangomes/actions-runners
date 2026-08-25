$ErrorActionPreference = "Stop"

$wslIp = (wsl.exe hostname -I).Trim().Split()[0]
if (-not $wslIp) {
    throw "Nao foi possivel descobrir o IP da distro WSL."
}

netsh interface portproxy delete v4tov4 listenport=8766 listenaddress=0.0.0.0 | Out-Null
netsh interface portproxy add v4tov4 listenport=8766 listenaddress=0.0.0.0 connectport=8766 connectaddress=$wslIp
netsh interface portproxy show all

Write-Host "Ponte configurada para WSL $wslIp."