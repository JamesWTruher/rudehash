# files, directories
$ConfigFile = [io.path]::combine($PSScriptRoot, "rudehash.json")
$MinersDir = [io.path]::combine($PSScriptRoot, "miners")
$ToolsDir = [io.path]::combine($PSScriptRoot, "tools")
$TempDir = [io.path]::combine($PSScriptRoot, "temp")

# make sure math functions work regardless of regional settings
[cultureinfo]::CurrentCulture = [cultureinfo]::InvariantCulture

# globals
[System.Collections.Hashtable]$Config = @{}
[System.Collections.Hashtable]$FileConfig = @{}
# current keys: Api CoinMode DevMining Port Rates
[System.Collections.Hashtable]$SessionConfig = @{}
$FirstRun = $false
$FirstLoop = $true
$MinerPort = 28178
$BlockchainUrl = "https://blockchain.info/ticker"
$MonitoringUrl = "https://rudehash.org/monitor/miner.php"
$MphStatsUrl = "https://miningpoolhubstats.com/api/worker/"
$ZergpoolCoinsUrl = "http://api.zergpool.com:8080/api/currencies"
$MinerApiErrorStr = "Malformed miner API response."

Clear-Host

function Exit-RudeHash ()
{
	Read-Host -Prompt "Press Enter to exit..."
	Exit
}

function Write-Pretty ($BgColor, $String)
{
	$WindowWidth = $Host.UI.RawUI.MaxWindowSize.Width

	ForEach ($Line in $($String -split "`r`n"))
	{
		$SpaceCount = $WindowWidth - ($Line.length % $WindowWidth)
		$Line += " " * $SpaceCount

		Write-Host -ForegroundColor White -BackgroundColor $BgColor $Line
	}
}

function Write-PrettyDots ()
{
	$WindowWidth = $Host.UI.RawUI.MaxWindowSize.Width - 1
	$String += "`u{2219}" * $WindowWidth

	Write-Pretty DarkCyan $String
}

function Write-PrettyHeader ()
{
	Write-PrettyDots
	Write-Pretty DarkCyan "RudeHash NVIDIA Miner `u{00a9} gradinkov"
	Write-PrettyDots
}

function Write-PrettyError ($String)
{
	Write-Pretty Red $String
}

function Write-PrettyDebug ($String)
{
	Write-Pretty Magenta $String
}

function Write-PrettyInfo ($String)
{
	Write-Pretty DarkBlue $String
}

function Write-PrettyEarnings ($String)
{
	Write-Pretty DarkGreen $String
}

if (Test-Path $ConfigFile)
{
	try
	{
		$Config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json -AsHashtable

		# make sure we don't fail if the file is empty
		if (-Not ($Config))
		{
			[System.Collections.Hashtable]$Config = @{}
			$FirstRun = $true
		}
	}
	catch [System.Management.Automation.PSInvalidOperationException]
	{
		Write-PrettyError "Error parsing '$ConfigFile'! Do you have an option set multiple times?"
		Exit-RudeHash
	}
	catch
	{
		Write-PrettyError "Error accessing '$ConfigFile'!"
		Exit-RudeHash
	}
}
else
{
	$FirstRun = $true

	try
	{
		New-Item $ConfigFile -ItemType File | Out-Null
	}
	catch
	{
		Write-PrettyError "Error creating '$ConfigFile'!"
		Exit-RudeHash
	}
}

$Pools =
@{
	"miningpoolhub" =
	@{
		Name = "Mining Pool Hub"
		PoolFee = 1.1
		Authless = $false
		Regions = $true
		StratumProto = 0
		Algos =
		@{
			"ethash" = @{ Server = "%REGION%ethash-hub.miningpoolhub.com"; Port = 17020 }
			"equihash" = @{ Server = "%REGION%equihash-hub.miningpoolhub.com"; Port = 17023 }
			"lyra2v2" = @{ Server = "hub.miningpoolhub.com"; Port = 17018 }
			"lyra2z" = @{ Server = "%REGION%lyra2z-hub.miningpoolhub.com"; Port = 17025 }
			"neoscrypt" = @{ Server = "hub.miningpoolhub.com"; Port = 17012 }
		}
		Coins =
		@{
			"btg" = @{ Server = "%REGION%equihash-hub.miningpoolhub.com"; Port = 20595 }
			"eth" = @{ Server = "%REGION%ethash-hub.miningpoolhub.com"; Port = 20535 }
			"ftc" = @{ Server = "hub.miningpoolhub.com"; Port = 20510 }
			"mona" = @{ Server = "hub.miningpoolhub.com"; Port = 20593 }
			"vtc" = @{ Server = "hub.miningpoolhub.com"; Port = 20507 }
			"xzc" = @{ Server = "%REGION%lyra2z-hub.miningpoolhub.com"; Port = 20581 }
			"zcl" = @{ Server = "%REGION%equihash-hub.miningpoolhub.com"; Port = 20575 }
			"zec" = @{ Server = "%REGION%equihash-hub.miningpoolhub.com"; Port = 20570 }
			"zen" = @{ Server = "%REGION%equihash-hub.miningpoolhub.com"; Port = 20594 }
		}
	}

	"nicehash" =
	@{
		Name = "NiceHash"
		PoolFee = 2
		Authless = $true
		Regions = $true
		StratumProto = 2
		ApiUrl = "https://api.nicehash.com/api?method=stats.global.current"
		Algos =
		@{
			"equihash" = @{ Server = "equihash.%REGION%nicehash.com"; Port = 3357; Modifier = 1000000; Id = 24 }
			"ethash" = @{ Server = "daggerhashimoto.%REGION%nicehash.com"; Port = 3353; Modifier = 1000000000; Id = 20 }
			"lyra2v2" = @{ Server = "lyra2rev2.%REGION%nicehash.com"; Port = 3347; Modifier = 1000000000000; Id = 14 }
			"neoscrypt" = @{ Server = "neoscrypt.%REGION%nicehash.com"; Port = 3341; Modifier = 1000000000; Id = 8 }
			"nist5" = @{ Server = "nist5.%REGION%nicehash.com"; Port = 3340; Modifier = 1000000000; Id = 7 }
		}
	}

	"poolr" =
	@{
		Name = "Poolr"
		PoolFee = 0.4
		Authless = $true
		Regions = $false
		StratumProto = 0
		Coins =
		@{
			"bwk" = @{ Server = "poolr.io"; Port = 3833 }
			"flm" = @{ Server = "poolr.io"; Port = 8333 }
		}
	}

	"suprnova" =
	@{
		Name = "Suprnova"
		PoolFee = 1.0
		Authless = $false
		Regions = $false
		StratumProto = 2
		Coins =
		@{
			"bsd" = @{ Server = "bsd.suprnova.cc"; Port = 8686 }
			"btcp" = @{ Server = "btcp.suprnova.cc"; Port = 6822 }
			"btg" = @{ Server = "btg.suprnova.cc"; Port = 8816 }
			"btx" = @{ Server = "btx.suprnova.cc"; Port = 3629 }
			"crs" = @{ Server = "crs.suprnova.cc"; Port = 4155 }
			"eth" = @{ Server = "eth.suprnova.cc"; Port = 5000 }
			"grlc" = @{ Server = "grlc.suprnova.cc"; Port = 8600 }
			"mona" = @{ Server = "mona.suprnova.cc"; Port = 2995 }
			"kreds" = @{ Server = "kreds.suprnova.cc"; Port = 7196 }
			"poly" = @{ Server = "poly.suprnova.cc"; Port = 7935 }
			"rvn" = @{ Server = "rvn.suprnova.cc"; Port = 6667 }
			"vtc" = @{ Server = "vtc.suprnova.cc"; Port = 5678 }
			"xzc" = @{ Server = "xzc.suprnova.cc"; Port = 1596 }
			"zcl" = @{ Server = "zcl.suprnova.cc"; Port = 4042 }
			"zec" = @{ Server = "zec.suprnova.cc"; Port = 2142 }
			"zen" = @{ Server = "zen.suprnova.cc"; Port = 3618 }
		}
	}

	"zergpool" =
	@{
		Name = "Zergpool"
		PoolFee = 0.5
		Authless = $true
		Regions = $true
		StratumProto = 0
		ApiUrl = "http://api.zergpool.com:8080/api/status"
		Algos =
		@{
			"bitcore" = @{ Server = "%REGION%mine.zergpool.com"; Port = 3556; Modifier = 1000000 }
			"hsr" = @{ Server = "%REGION%mine.zergpool.com"; Port = 7433; Modifier = 1000000 }
			"keccakc" = @{ Server = "%REGION%mine.zergpool.com"; Port = 5134; Modifier = 1000000000 }
			"lyra2v2" = @{ Server = "%REGION%mine.zergpool.com"; Port = 4533; Modifier = 1000000 }
			"lyra2z" = @{ Server = "%REGION%mine.zergpool.com"; Port = 4553; Modifier = 1000000 }
			"neoscrypt" = @{ Server = "%REGION%mine.zergpool.com"; Port = 4233; Modifier = 1000000 }
			"nist5" = @{ Server = "%REGION%mine.zergpool.com"; Port = 3833; Modifier = 1000000 }
			"phi" = @{ Server = "%REGION%mine.zergpool.com"; Port = 8333; Modifier = 1000000 }
			"x16r" = @{ Server = "%REGION%mine.zergpool.com"; Port = 3636; Modifier = 1000000 }
			"xevan" = @{ Server = "%REGION%mine.zergpool.com"; Port = 3739; Modifier = 1000000 }
		}
		Coins =
		@{
			"bsd" = @{ Server = "%REGION%mine.zergpool.com"; Port = 3739 }
			"btx" = @{ Server = "%REGION%mine.zergpool.com"; Port = 3556 }
			"crea" = @{ Server = "%REGION%mine.zergpool.com"; Port = 5134 }
			"flm" = @{ Server = "%REGION%mine.zergpool.com"; Port = 8333 }
			"ftc" = @{ Server = "%REGION%mine.zergpool.com"; Port = 4233 }
			"hsr" = @{ Server = "%REGION%mine.zergpool.com"; Port = 7433 }
			"ifx" = @{ Server = "%REGION%mine.zergpool.com"; Port = 4553 }
			"lux" = @{ Server = "%REGION%mine.zergpool.com"; Port = 8333 }
			"mona" = @{ Server = "%REGION%mine.zergpool.com"; Port = 4533 }
			"rvn" = @{ Server = "%REGION%mine.zergpool.com"; Port = 3636 }
			"tzc" = @{ Server = "%REGION%mine.zergpool.com"; Port = 4233 }
			"vtc" = @{ Server = "%REGION%mine.zergpool.com"; Port = 4533 }
			"xlr" = @{ Server = "%REGION%mine.zergpool.com"; Port = 3739 }
		}
	}

	"zpool" =
	@{
		Name = "zpool"
		PoolFee = 2
		Authless = $true
		Regions = $false
		StratumProto = 0
		ApiUrl = "https://www.zpool.ca/api/status"
		Algos =
		@{
			"bitcore" = @{ Server = "bitcore.mine.zpool.ca"; Port = 3556; Modifier = 1000000 }
			"equihash" = @{ Server = "equihash.mine.zpool.ca"; Port = 2142; Modifier = 1000 }
			"hsr" = @{ Server = "hsr.mine.zpool.ca"; Port = 7433; Modifier = 1000000 }
			"keccakc" = @{ Server = "keccakc.mine.zpool.ca"; Port = 5134; Modifier = 1000000000 }
			"lyra2v2" = @{ Server = "lyra2v2.mine.zpool.ca"; Port = 4533; Modifier = 1000000 }
			"lyra2z" = @{ Server = "lyra2z.mine.zpool.ca"; Port = 4553; Modifier = 1000000 }
			"neoscrypt" = @{ Server = "neoscrypt.mine.zpool.ca"; Port = 4233; Modifier = 1000000 }
			"nist5" = @{ Server = "nist5.mine.zpool.ca"; Port = 3833; Modifier = 1000000 }
			"phi" = @{ Server = "phi.mine.zpool.ca"; Port = 8333; Modifier = 1000000 }
			"polytimos" = @{ Server = "polytimos.mine.zpool.ca"; Port = 8463; Modifier = 1000000 }
			"xevan" = @{ Server = "xevan.mine.zpool.ca"; Port = 3739; Modifier = 1000000 }
		}
	}
}

$Coins =
@{
	"bsd" = @{ Name = "BitSend"; WtmPage = "201-bsd-xevan"; Algo = "xevan" }
	"btcp" = @{ Name = "Bitcoin Private"; Algo = "equihash" }
	"btg" = @{ Name = "Bitcoin Gold"; WtmPage = "214-btg-equihash"; Algo = "equihash" }
	"btx" = @{ Name = "Bitcore"; WtmPage = "202-btx-timetravel10"; Algo = "bitcore" }
	"bwk" = @{ Name = "Bulwark"; WtmPage = "224-bwk-nist5"; Algo = "nist5" }
	"crea" = @{ Name = "Creativecoin"; WtmPage = "199-crea-keccak-c"; Algo = "keccakc" }
	"crs" = @{ Name = "Criptoreal"; Algo = "lyra2z" }
	"eth" = @{ Name = "Ethereum"; WtmPage = "151-eth-ethash"; Algo = "ethash" }
	"flm" = @{ Name = "Folm Coin"; Algo = "phi" }
	"ftc" = @{ Name = "Feathercoin"; WtmPage = "8-ftc-neoscrypt"; Algo = "neoscrypt" }
	"grlc" = @{ Name = "Garlicoin"; Algo = "allium" }
	"hsr" = @{ Name = "Hshare"; Algo = "hsr" }
	"ifx" = @{ Name = "Infinex"; Algo = "lyra2z" }
	"kreds" = @{ Name = "Kreds"; Algo = "lyra2v2" }
	"lux" = @{ Name = "LUXCoin"; WtmPage = "212-lux-phi1612"; Algo = "phi" }
	"mona" = @{ Name = "Monacoin"; WtmPage = "148-mona-lyra2rev2"; Algo = "lyra2v2" }
	"poly" = @{ Name = "Polytimos"; Algo = "polytimos" }
	"rvn" = @{ Name = "Ravencoin"; Algo = "x16r" }
	"tzc" = @{ Name = "Trezarcoin"; WtmPage = "215-tzc-neoscrypt"; Algo = "neoscrypt" }
	"vtc" = @{ Name = "Vertcoin"; WtmPage = "5-vtc-lyra2rev2"; Algo = "lyra2v2" }
	"xlr" = @{ Name = "Solaris"; WtmPage = "179-xlr-xevan"; Algo = "xevan" }
	"xzc" = @{ Name = "Zcoin"; WtmPage = "175-xzc-lyra2z"; Algo = "lyra2z" }
	"zcl" = @{ Name = "ZClassic"; WtmPage = "167-zcl-equihash"; Algo = "equihash" }
	"zec" = @{ Name = "Zcash"; WtmPage = "166-zec-equihash"; Algo = "equihash" }
	"zen" = @{ Name = "ZenCash"; WtmPage = "185-zen-equihash"; Algo = "equihash" }
}

$Miners =
@{
	"ccminer-allium" = @{ Url = "https://github.com/lenis0012/ccminer/releases/download/2.3.0-allium/ccminer-x64.exe"; ArchiveFile = "ccminer-allium.exe"; ExeFile = "ccminer-allium.exe"; FilesInRoot = $true; Algos = @("allium"); Api = $true; Version = "2.2.4" }
	"ccminer-klaust" = @{ Url = "https://github.com/KlausT/ccminer/releases/download/8.20/ccminer-820-cuda91-x64.zip"; ArchiveFile = "ccminer-klaust.zip"; ExeFile = "ccminer.exe"; FilesInRoot = $true; Algos = @("lyra2v2", "neoscrypt", "nist5"); Api = $true }
	"ccminer-palginmod" = @{ Url = "https://github.com/palginpav/ccminer/releases/download/2.0-bitcore.v3/ccminer_timetravel_v3.zip"; ArchiveFile = "ccminer-palginmod.zip"; ExeFile = "ccminer.exe"; FilesInRoot = $true; Algos = @("lyra2v2", "lyra2z", "neoscrypt", "nist5"); Api = $true; Version = "2.0" }
	"ccminer-phi" = @{ Url = "https://github.com/216k155/ccminer-phi-anxmod/releases/download/ccminer%2Fphi-1.0/ccminer-phi-1.0.zip"; ArchiveFile = "ccminer-phi.zip"; ExeFile = "ccminer.exe"; FilesInRoot = $false; Algos = @("phi"); Api = $true; Version = "1.0" }
	"ccminer-rvn" = @{ Url = "https://github.com/MSFTserver/ccminer/releases/download/2.2.5-rvn/ccminer-x64-2.2.5-rvn-cuda9.7z"; ArchiveFile = "ccminer-rvn.7z"; ExeFile = "ccminer-x64.exe"; FilesInRoot = $true; Algos = @("x16r"); Api = $true; Version = "2.2.5" }
	"ccminer-polytimos" = @{ Url = "https://github.com/punxsutawneyphil/ccminer/releases/download/polytimosv2/ccminer-polytimos_v2.zip"; ArchiveFile = "ccminer-polytimos.zip"; ExeFile = "ccminer.exe"; FilesInRoot = $true; Algos = @("polytimos"); Api = $true }
	"ccminer-tpruvot" = @{ Url = "https://github.com/tpruvot/ccminer/releases/download/2.2.4-tpruvot/ccminer-x64-2.2.4-cuda9.7z"; ArchiveFile = "ccminer-tpruvot.7z"; ExeFile = "ccminer-x64.exe"; FilesInRoot = $true; Algos = @("bitcore", "equihash", "hsr", "keccakc", "lyra2v2", "lyra2z", "neoscrypt", "nist5", "phi", "polytimos"); Api = $true; Version = "2.2.4" }
	"ccminer-xevan" = @{ Url = "https://github.com/krnlx/ccminer-xevan/releases/download/0.1/ccminer.exe"; ArchiveFile = "ccminer-xevan.exe"; ExeFile = "ccminer-xevan.exe"; FilesInRoot = $true; Algos = @("xevan"); Api = $true }
	"dstm" = @{ Url = "https://github.com/nemosminer/DSTM-equihash-miner/releases/download/DSTM-0.6/zm_0.6_win.zip"; ArchiveFile = "dstm.zip"; ExeFile = "zm.exe"; FilesInRoot = $false; Algos = @("equihash"); Api = $true; Version = "0.6" }
	"ethminer" = @{ Url = "https://github.com/ethereum-mining/ethminer/releases/download/v0.14.0.dev4/ethminer-0.14.0.dev4-Windows.zip"; ArchiveFile = "ethminer.zip"; ExeFile = "ethminer.exe"; FilesInRoot = $false; Algos = @("ethash"); Api = $true; Version = "0.14.0.dev4" }
	"excavator" = @{ Url = "https://github.com/nicehash/excavator/releases/download/v1.4.4a/excavator_v1.4.4a_NVIDIA_Win64.zip"; ArchiveFile = "excavator.zip"; ExeFile = "excavator.exe"; FilesInRoot = $false; Algos = @("ethash", "equihash", "lyra2v2", "neoscrypt", "nist5"); Api = $true; Version = "1.4.4a_nvidia" }
	"hsrminer-hsr" = @{ Url = "https://github.com/palginpav/hsrminer/raw/master/HSR%20algo/Windows/hsrminer_hsr.zip"; ArchiveFile = "hsrminer_hsr.zip"; ExeFile = "hsrminer_hsr.exe"; FilesInRoot = $true; Algos = @("hsr"); Api = $false; Version = "1.0" }
	"hsrminer-neoscrypt" = @{ Url = "https://github.com/palginpav/hsrminer/raw/master/Neoscrypt%20algo/Windows/hsrminer_neoscrypt.zip"; ArchiveFile = "hsrminer_neoscrypt.zip"; ExeFile = "hsrminer_neoscrypt.exe"; FilesInRoot = $true; Algos = @("neoscrypt"); Api = $false; Version = "1.0.1" }
	"vertminer" = @{ Url = "https://github.com/vertcoin-project/vertminer-nvidia/releases/download/v1.0-stable.2/vertminer-nvdia-v1.0.2_windows.zip"; ArchiveFile = "vertminer.zip"; ExeFile = "vertminer.exe"; FilesInRoot = $false; Algos = @("lyra2v2"); Api = $true; Version = "1.0.1" }
	"zecminer" = @{ Url = "https://github.com/nanopool/ewbf-miner/releases/download/v0.3.4b/Zec.miner.0.3.4b.zip"; ArchiveFile = "zecminer.zip"; ExeFile = "miner.exe"; FilesInRoot = $true; Algos = @("equihash"); Api = $true; Version = "0.3.4b" }
}

$ExcavatorAlgos =
@{
	"ethash" = "daggerhashimoto"
	"equihash" = "equihash"
	"lyra2v2" = "lyra2rev2"
	"neoscrypt" = "neoscrypt"
	"nist5" = "nist5"
}

$Tools =
@{
	"7zip" = @{ Url = "http://7-zip.org/a/7za920.zip"; ArchiveFile = "7zip.zip"; ExeFile = "7za.exe"; FilesInRoot = $true }
}

$Regions =
@{
	"miningpoolhub" = @("asia", "europe", "us-east")
	"nicehash" = @("br", "eu", "hk", "in", "jp", "usa")
	# zergpool uses "" for usa, we gotta fix this later
	"zergpool" = @("europe", "usa")
}

# MPH returns all hashrates in kH/s but WTM uses different magnitudes for different algos
$WtmModifiers =
@{
	"bitcore" = 1000000
	"ethash" = 1000000
	"equihash" = 1
	"keccakc" = 1000000
	"lyra2v2" = 1000
	"lyra2z" = 1000
	"neoscrypt" = 1000
	"nist5" = 1000000
	"phi" = 1000000
	"xevan" = 1000000
}

$AlgoNames =
@{
	"allium" = "Allium"
	"bitcore" = "TimeTravel10"
	"ethash" = "Ethash"
	"equihash" = "Equihash"
	"hsr" = "HSR"
	"keccakc" = "Keccak-C"
	"lyra2v2" = "Lyra2REv2"
	"lyra2z" = "Lyra2Z"
	"neoscrypt" = "NeoScrypt"
	"nist5" = "Nist5"
	"phi" = "PHI1612"
	"polytimos" = "Polytimos"
	"x16r" = "X16R"
	"xevan" = "Xevan"
}

$Remarks =
@{
	"Debug" = "If true, RudeHash will print diagnostic information along with the rest. Useful for troubleshooting."
	"Watchdog" = "If true, RudeHash will restart the miner if it reports 0 hashrate for 5 consecutive minutes."
	"MonitoringKey" = "Allows for monitoring your rigs at rudehash.org/monitor. A newly generated random key for you:`r`n$(New-Guid)"
	"MphApiKey" = "Allows for monitoring at miningpoolhubstats.com using your MPH API key."
	# Pool
	"Worker" = "Your rig's nickname."
	"Wallet" = "Your Bitcoin or Altcoin wallet. Ignored on pools that use a site balance."
	"WalletIsAltcoin" = "If true, your wallet's currency is the same as the coin you're mining, and you're paid directly to this wallet for mining a coin. If false, your wallet is Bitcoin, and the pool auto-exchanges the mined coins to BTC. Ignored on pools that use a site balance."
	"User" = "Pool user name. Ignored on pools that use a wallet address."
	# Region
	# Coin
	# Miner
	# Algo
	"Currency" = "Fiat currency used for calculating your earnings."
	"ElectricityCost" = "The price you pay for electricity, <your currency>/kWh, decimal separator is '.'"
	"ExtraArgs" = "Any additional command line arguments you want to pass to the miner."
}

# we build these dynamically
[System.Collections.Hashtable]$BtcRates = @{}
[System.Collections.Hashtable]$ZergpoolCoins = @{}

function Set-Property ($Name, $Value, $Permanent)
{
	$Config.$Name = $Value

	if ($Permanent)
	{
		try
		{
			$Config | ConvertTo-Json | Out-File -FilePath $ConfigFile -Encoding utf8NoBOM
		}
		catch
		{
			Write-PrettyError "Error writing '$ConfigFile'!"

			if ($Config.Debug)
			{
				Write-PrettyDebug $_.Exception
			}
		}
	}
}

function Get-CoinSupport ()
{
	$Table = New-Object System.Data.DataTable
	$Table.Columns.Add("Coin", "string") | Out-Null
	$Table.Columns.Add("Algo", "string") | Out-Null
	$Table.DefaultView.Sort = "Coin ASC"

	$Support = "Supported coins and their algos:"
	foreach ($Key in $Coins.Keys)
	{
		$Row = $Table.NewRow()
		$Row.Coin = $Key.ToUpper()
		$Algos = ""
		$Algos += $Coins[$Key].Algo
		$Row.Algo = $Algos
		$Table.Rows.Add($Row)
	}

	$Table = $Table.DefaultView.ToTable()
	# use Format-Table to force flushing to screen immediately
	$Support += Out-String -InputObject ($Table | Format-Table)
	$Table.Dispose()

	return $Support
}

function Get-MinerSupport ()
{
	$Table = New-Object System.Data.DataTable
	$Table.Columns.Add("Miner", "string") | Out-Null
	$Table.Columns.Add("Algo", "string") | Out-Null
	$Table.DefaultView.Sort = "Miner ASC"

	$Support += "Supported miners and algos:"
	foreach ($Key in $Miners.Keys)
	{
		$Row = $Table.NewRow()
		$Row.Miner = $Key
		$Algos = ""
		$Algos += foreach ($Algo in $Miners[$Key].Algos) { $Algo }
		$Row.Algo = $Algos
		$Table.Rows.Add($Row)
	}

	$Table = $Table.DefaultView.ToTable()
	# use Format-Table to force flushing to screen immediately
	$Support += Out-String -InputObject ($Table | Format-Table)
	$Table.Dispose()

	return $Support
}

function Get-AlgoSupport ()
{
	return Get-MinerSupport
}

function Get-PoolSupport ()
{
	$Table = New-Object System.Data.DataTable
	$Table.Columns.Add("Pool", "string") | Out-Null
	$Table.Columns.Add("Modes", "string") | Out-Null
	$Table.Columns.Add("Payout to", "string") | Out-Null
	$Table.Columns.Add("Wallet currencies", "string") | Out-Null
	$Table.DefaultView.Sort = "Pool ASC"

	$Support += "Supported pools, mining modes and payout methods:"
	foreach ($Key in $Pools.Keys)
	{
		$Row = $Table.NewRow()
		$Row.Pool = $Key
		$ModeStr = ""

		if ($Pools[$Key].Algos)
		{
			$ModeStr += "algo "
		}

		if ($Pools[$Key].Coins)
		{
			$ModeStr += "coin"
		}

		$Row.Modes = $ModeStr
		$WallettCurrStr = ""

		if ($Pools[$Key].Authless)
		{
			$Row."Payout to" = "Own wallet"

			if ($Pools[$Key].Algos)
			{
				$WallettCurrStr += "Bitcoin "
			}

			if ($Pools[$Key].Coins)
			{
				$WallettCurrStr += "Altcoin"
			}
		}
		else
		{
			$Row."Payout to" = "Site balance"
			$WallettCurrStr += "N/A"
		}

		$Row."Wallet currencies" = $WallettCurrStr

		$Table.Rows.Add($Row)
	}

	$Table = $Table.DefaultView.ToTable()
	# use Format-Table to force flushing to screen immediately
	$Support += Out-String -InputObject ($Table | Format-Table)
	$Support += "Bitcoin wallet: you use BTC wallet, the pool auto-exchanges the mined coins to BTC.`r`n"
	$Support += "Altcoin wallet: your wallet's currency is the same as the coin you're mining.`r`n`r`n"
	$Table.Dispose()

	$Table = New-Object System.Data.DataTable
	$Table.Columns.Add("Pool", "string") | Out-Null
	$Table.Columns.Add("Algo", "string") | Out-Null
	$Table.DefaultView.Sort = "Pool ASC"

	$Support += "Supported algos:"
	foreach ($Key in $Pools.Keys)
	{
		if ($Pools[$Key].Algos)
		{
			$Row = $Table.NewRow()
			$Row.Pool = $Key
			$Algos = ""
			$Algos += foreach ($Algo in $Pools[$Key].Algos.GetEnumerator() | Sort-Object -Property Name) { $Algo.Name }
			$Row.Algo = $Algos
			$Table.Rows.Add($Row)
		}
	}

	$Table = $Table.DefaultView.ToTable()
	# use Format-Table to force flushing to screen immediately
	$Support += Out-String -InputObject ($Table | Format-Table)
	$Table.Dispose()

	$Table = New-Object System.Data.DataTable
	$Table.Columns.Add("Pool", "string") | Out-Null
	$Table.Columns.Add("Coin", "string") | Out-Null
	$Table.DefaultView.Sort = "Pool ASC"

	$Support += "Supported coins:"
	foreach ($Key in $Pools.Keys)
	{
		if ($Pools[$Key].Coins)
		{
			$Row = $Table.NewRow()
			$Row.Pool = $Key
			$Coins = ""
			$Coins += foreach ($Coin in $Pools[$Key].Coins.GetEnumerator() | Sort-Object -Property Name) { $Coin.Name }
			$Row.Coin = $Coins
			$Table.Rows.Add($Row)
		}
	}

	$Table = $Table.DefaultView.ToTable()
	# use Format-Table to force flushing to screen immediately
	$Support += Out-String -InputObject ($Table | Format-Table)
	$Table.Dispose()

	return $Support
}

function Get-RegionSupport ()
{
	$Table = New-Object System.Data.DataTable
	$Table.Columns.Add("Pool", "string") | Out-Null
	$Table.Columns.Add("Regions", "string") | Out-Null
	$Table.DefaultView.Sort = "Pool ASC"

	$Support += "Pools with regions:"
	foreach ($Key in $Regions.Keys)
	{
		$Row = $Table.NewRow()
		$Row.Pool = $Key
		$Regs = ""
		$Regs += foreach ($Region in $Regions[$Key] | Sort-Object) { $Region }
		$Row.Regions = $Regs
		$Table.Rows.Add($Row)
	}

	$Table = $Table.DefaultView.ToTable()
	# use Format-Table to force flushing to screen immediately
	$Support += Out-String -InputObject ($Table | Format-Table)
	$Table.Dispose()

	return $Support
}

function Test-DebugProperty ()
{
	try
	{
		$Config.Debug = [System.Convert]::ToBoolean($Config.Debug)
		return $true
	}
	catch
	{
		Write-PrettyError ("'Debug' property is in incorrect format, it must be 'true' or 'false'!")
		return $false
	}
}

function Test-WatchdogProperty ()
{
	try
	{
		$Config.Watchdog = [System.Convert]::ToBoolean($Config.Watchdog)
		return $true
	}
	catch
	{
		Write-PrettyError ("'Watchdog' property is in incorrect format, it must be 'true' or 'false'!")

		if ($Config.Debug)
		{
			Write-PrettyDebug $_.Exception
		}

		return $false
	}
}

function Test-MonitoringKeyProperty ()
{
	# if the user presses enter, the key will be deleted altogether
	# we can't do much here without making the key mandatory
	if ($Config.MonitoringKey)
	{
		$Uuid = New-Guid
		$Res = [Guid]::TryParse($Config.MonitoringKey, [ref]$Uuid)

		if (-Not $Res)
		{
			Write-PrettyError ("Monitoring key is in incorrect format!")

			return $false
		}
		else
		{
			return $true
		}
	}
	else
	{
		return $true
	}
}

function Test-MphApiKeyProperty ()
{
	if ($Config.MphApiKey)
	{
		if ($Config.MphApiKey.length -ne 64)
		{
			Write-PrettyError ("MPH API key is in incorrect format, check it here: https://miningpoolhub.com/?page=account&action=edit")
			return $false
		}
		else
		{
			return $true
		}
	}
	else
	{
		return $true
	}
}

function Test-PoolProperty ()
{
	if (-Not ($Config.Pool))
	{
		Write-PrettyError ("Pool must be set!")
		return $false
	}
	elseif (-Not ($Pools.ContainsKey($Config.Pool)))
	{
		Write-PrettyError ("The """ + $Config.Pool + """ pool is not supported!")

		return $false
	}
	else
	{
		return $true
	}
}

function Test-WorkerProperty ()
{
	$Pattern = "^[a-zA-Z0-9]{1,15}$"

	if (-Not ($Config.Worker))
	{
		Write-PrettyError ("Worker must be set!")
		return $false
	}
	elseif (-Not ($Config.Worker -match $Pattern))
	{
			Write-PrettyError ("Worker name is in invalid format! Use a maximum of 15 letters and numbers!")
			return $false
	}
	else
	{
		return $true
	}
}

function Test-Wallet ($Address, $Symbol)
{
	switch ($Symbol)
	{
		"BTC"
		{
			if ((-Not ($Address.length -lt 26)) -And (-Not ($Address.length -gt 34)) -And ($Address.StartsWith("1") -Or $Address.StartsWith("3") -Or $Address.StartsWith("bc1")))
			{
				return $true
			}
			else
			{
				return $false
			}
		}
		Default
		{
			return $true
		}
	}
}

function Test-WalletProperty ()
{
	# we don't care about wallet format here, later when we know it's BTC, we'll check it
	return $true
}

function Test-WalletIsAltcoinProperty ()
{
	if ($Config.WalletIsAltcoin)
	{
		try
		{
			$Config.WalletIsAltcoin = [System.Convert]::ToBoolean($Config.WalletIsAltcoin)
			return $true
		}
		catch
		{
			Write-PrettyError ("'WalletIsAltcoin' property is in incorrect format, it must be 'true' or 'false'!")

			if ($Config.Debug)
			{
				Write-PrettyDebug $_.Exception
			}

			return $false
		}
	}
	else
	{
		return $true
	}
}

function Test-UserProperty ()
{
	if ($Config.User)
	{
		$Pattern = "^[a-zA-Z0-9]{1,20}$"

		if ($Config.User -match $Pattern)
		{
			return $true
		}
		else
		{
			Write-PrettyError ("User name is in invalid format! Use a maximum of 20 letters and numbers!")
			return $false
		}
	}
	else
	{
		return $true
	}
}

function Test-RegionProperty ()
{
	if ($Config.Region)
	{
		# make the array of dynamic size
		[System.Collections.ArrayList]$ValidRegions = @()

		# build a list of available regions
		foreach ($Pool in $Regions.Keys)
		{
			foreach ($Region in $Regions[$Pool])
			{
				if (-Not ($ValidRegions.Contains($Region)))
				{
					$ValidRegions.Add($Region) | Out-Null
				}
			}
		}

		if ($ValidRegions.Contains($Config.Region))
		{
			return $true
		}
		else
		{
			Write-PrettyError ("The """ + $Config.Region + """ region does not exist!")

			return $false
		}
	}
	else
	{
		return $true
	}
}

function Test-CoinProperty ()
{
	if ($Config.Coin)
	{
		$Config.Coin = $Config.Coin.ToLower()

		if (-Not ($Coins.ContainsKey($Config.Coin)))
		{
			Write-PrettyError ("The """ + $Config.Coin.ToUpper() + """ coin is not supported!")

			return $false
		}
		else
		{
			return $true
		}
	}
	else
	{
		return $true
	}
}

function Test-MinerProperty ()
{
	if (-Not ($Config.Miner))
	{
		Write-PrettyError ("Miner must be set!")
		return $false
	}
	elseif (-Not ($Miners.ContainsKey($Config.Miner)))
	{
		Write-PrettyError ("The """ + $Config.Miner + """ miner is not supported!")

		return $false
	}
	else
	{
		return $true
	}
}

function Test-AlgoProperty ()
{
	if ($Config.Algo)
	{
		# make the array of dynamic size
		[System.Collections.ArrayList]$Algos = @()
		#$Coll = {$Algos}.Invoke()

		# build a list of available algos
		foreach ($Miner in $Miners.Keys)
		{
			foreach ($Algo in $Miners[$Miner].Algos)
			{
				if (-Not ($Algos.Contains($Algo)))
				{
					$Algos.Add($Algo) | Out-Null
				}
			}
		}

		if (-Not ($Algos.Contains($Config.Algo)))
		{
			Write-PrettyError ("The """ + $Config.Algo + """ algo is not supported!")

			return $false
		}
		else
		{
			return $true
		}
	}
	else
	{
		return $true
	}
}

function Test-CoinExchangeSupport ()
{
	if ($Config.Pool -eq "zergpool")
	{
		if ($ZergpoolCoins.Count -eq 0)
		{
			if ($Config.Debug)
			{
				Write-PrettyDebug "Checking coin's exchange support..."
			}

			try
			{
				$Response = Invoke-RestMethod -Uri $ZergpoolCoinsUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue

				if ($Config.Debug)
				{
					Write-PrettyDebug ("Server response: $($Response.($Config.Coin))")
				}

				foreach ($Coin in $Pools["zergpool"].Coins.Keys)
				{
					$ZergpoolCoins.Add($Coin, $Response.$Coin.noautotrade)
				}
			}
			catch
			{
				Write-PrettyError "Error determining if the selected coin can be exchanged! RudeHash cannot continue."

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}

				Exit-RudeHash
			}
		}

		if ($ZergpoolCoins.($Config.Coin) -eq 0)
		{
			return $true
		}
		else
		{
			return $false
		}
	}
	else
	{
		return $true
	}
}

function Receive-Choice ($A, $B)
{
	$KeyPress = ""
	Write-PrettyInfo "Press '1' to change '$($A)' or '2' to change '$($B)')"

	while (-Not (($KeyPress.Character -eq "1") -Or ($KeyPress.Character -eq "2")))
	{
		$KeyPress = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
	}

	if ($KeyPress.Character -eq "1")
	{
		return $A
	}
	elseif ($KeyPress.Character -eq "2")
	{
		return $B
	}
}

function Receive-Property ($Name, $Mandatory)
{
	if ($Mandatory)
	{
		return Read-Host "Enter value for ""$($Name)"""
	}
	else
	{
		return Read-Host "Enter value for ""$($Name)"" (or press Return to delete)"
	}
}

function Write-Help ($Property)
{
	# print help text, if any
	try
	{
		Write-PrettyInfo( & (Get-ChildItem "Function:Get-$($Property)Support" -ErrorAction Ignore))
	}
	catch
	{
		if ($Remarks.ContainsKey($Property))
		{
			Write-PrettyInfo($Property + ": " + $Remarks[$Property])
		}
	}
}

function Initialize-Property ($Name, $Mandatory, $Force)
{
	if ($Config.Debug)
	{
		Write-PrettyDebug "Evaluating $Name property..."
	}

	if ($FirstRun)
	{
		Write-Help $Name
	}

	if ($Force)
	{
		$Ret = Receive-Property $Name $Mandatory
		Set-Property $Name $Ret $true
	}

	# awesome trick from https://wprogramming.wordpress.com/2011/07/18/dynamic-function-and-variable-access-in-powershell/
	while (-Not (& (Get-ChildItem "Function:Test-$($Name)Property")))
	{
		Write-Help $Name
		$Ret = Receive-Property $Name $Mandatory
		Set-Property $Name $Ret $true
	}
}

function Test-Compatibility ()
{
	if ($Pools[$Config.Pool].Authless)
	{
		if (-Not ($Config.Wallet))
		{
			Write-PrettyError ("""" + $Config.Pool + """ is anonymous, wallet address must be set!")
			$Choice = Receive-Choice "Wallet" "Pool"
			$Config.$Choice = ""
			Initialize-Property $Choice $true $true
			Test-Compatibility
		}
	}
	elseif (-Not ($Config.User))
	{
		Write-PrettyError ("""" + $Config.Pool + """ implements authentication, user name must be set!")
		$Choice = Receive-Choice "User" "Pool"
		$Config.$Choice = ""
		Initialize-Property $Choice $true $true
		Test-Compatibility
	}

	if ($Pools[$Config.Pool].Regions)
	{
		if (-Not ($Config.Region))
		{
			Write-PrettyError ("Region must be set for the """ + $Config.Pool + """ pool!")
			$Choice = Receive-Choice "Region" "Pool"
			$Config.$Choice = ""
			Initialize-Property $Choice $true $true
			Test-Compatibility
		}
		if (-Not ($Regions[$Config.Pool].Contains($Config.Region)))
		{
			Write-PrettyError ("The """ + $Config.Region + """ region is not supported on the """ + $Config.Pool + """ pool!")
			$Choice = Receive-Choice "Region" "Pool"
			$Config.$Choice = ""
			Initialize-Property $Choice $true $true
			Test-Compatibility
		}
	}

	$SessionConfig.CoinMode = $false

	if ($Config.Coin)
	{
		if (-Not ($Pools[$Config.Pool].Coins))
		{
			Write-PrettyError ("Coin mining is not supported on """ + $Config.Pool + """!")
			$Choice = Receive-Choice "Coin" "Pool"
			$Config.$Choice = ""
			Initialize-Property $Choice $true $true
			Test-Compatibility
		}
		elseif (-Not ($Pools[$Config.Pool].Coins.ContainsKey($Config.Coin)))
		{
			Write-PrettyError ("The """ + $Config.Coin + """ coin is not supported on """ + $Config.Pool + """!")
			$Choice = Receive-Choice "Coin" "Pool"
			$Config.$Choice = ""
			Initialize-Property $Choice $true $true
			Test-Compatibility
		}
		elseif (-Not (Test-CoinExchangeSupport))
		{
			Write-PrettyError ("The """ + $Config.Coin + """ coin cannot be exchanged on """ + $Config.Pool + """!")
			$Choice = Receive-Choice "Coin" "Pool"
			$Config.$Choice = ""
			Initialize-Property $Choice $true $true
			Test-Compatibility
		}
		else
		{
			# use coin algo if coin is specified
			$Config.Algo = $Coins[$Config.Coin].Algo
			$SessionConfig.CoinMode = $true
		}
	}
	elseif (-Not $Config.Algo)
	{
		Write-PrettyError ("You specified neither a coin nor an algo!")
		$Choice = Receive-Choice "Coin" "Algo"
		$Config.$Choice = ""
		Initialize-Property $Choice $true $true
		Test-Compatibility
	}
	elseif (-Not ($Pools[$Config.Pool].Algos))
	{
		Write-PrettyError ("Algo mining is not supported on """ + $Config.Pool + """!")
		$Choice = Receive-Choice "Coin" "Pool"
		$Config.$Choice = ""
		Initialize-Property $Choice $true $true
		Test-Compatibility
	}
	# reason for elseif: if the coin is supported on the pool, its algo doesn't need to be checked
	elseif (-Not ($Pools[$Config.Pool].Algos.ContainsKey($Config.Algo)))
	{
		Write-PrettyError ("Incompatible configuration! """ + $Config.Algo + """ cannot be mined on """ + $Config.Pool + """.")
		$Choice = Receive-Choice "Algo" "Pool"
		$Config.$Choice = ""
		Initialize-Property $Choice $true $true
		Test-Compatibility
	}

	if (-Not ($Miners[$Config.Miner].Algos.Contains($Config.Algo)))
	{
		if ($Config.Coin)
		{
			Write-PrettyError ("Incompatible configuration! The """ + $Config.Coin.ToUpper() + """ coin cannot be mined with """ + $Config.Miner + """.")
			$Choice = Receive-Choice "Coin" "Miner"
			$Config.$Choice = ""
			Initialize-Property $Choice $true $true
			Test-Compatibility
		}
		else
		{
			Write-PrettyError ("Incompatible configuration! The """ + $Config.Algo + """ algo cannot be mined with """ + $Config.Miner + """.")
			$Choice = Receive-Choice "Algo" "Miner"
			$Config.$Choice = ""
			Initialize-Property $Choice $true $true
			Test-Compatibility
		}
	}

	# wallet checks, only relevant on wallet pools
	if ($Pools[$Config.Pool].Authless)
	{
		# altcoin payouts are only possible if the pool has coins
		if ($Config.WalletIsAltcoin -And (-Not ($Pools[$Config.Pool].Coins)))
		{
			Write-PrettyError ("""" + $Config.Pool + """ doesn't support Altcoin payouts!")
			$Choice = Receive-Choice "WalletIsAltcoin" "Pool"
			$Config.$Choice = ""
			Initialize-Property $Choice $true $true
			Test-Compatibility
		}

		# bitcoin payouts are only possible if the pool has algos (at least ATM)
		if ((-Not ($Config.WalletIsAltcoin)) -And (-Not ($Pools[$Config.Pool].Algos)))
		{
			Write-PrettyError ("""" + $Config.Pool + """ doesn't support Bitcoin payouts!")
			$Choice = Receive-Choice "WalletIsAltcoin" "Pool"
			$Config.$Choice = ""
			Initialize-Property $Choice $true $true
			Test-Compatibility
		}

		# altcoin payouts are only possible if mining a coin
		if ($Config.WalletIsAltcoin -And (-Not ($SessionConfig.CoinMode)))
		{
			Write-PrettyError ("Altcoin payouts are only possible if mining a coin!")
			$Choice = Receive-Choice "WalletIsAltcoin" "Coin"
			$Config.$Choice = ""
			Initialize-Property $Choice $true $true
			Test-Compatibility
		}

		# if getting paid in BTC, check its format, let's accept altcoin wallets as-is
		if ((-Not ($Config.WalletIsAltcoin)) -And (-Not (Test-Wallet $Config.Wallet "BTC")))
		{
			Write-PrettyError ("Wallet is not a valid BTC address!")
			$Choice = Receive-Choice "WalletIsAltcoin" "Wallet"
			$Config.$Choice = ""
			Initialize-Property $Choice $true $true
			Test-Compatibility
		}
	}

	# configuration is good, let's set up globals
	if ($SessionConfig.CoinMode)
	{
		$SessionConfig.Server = $Pools[$Config.Pool].Coins[$Config.Coin].Server
		$SessionConfig.Port = $Pools[$Config.Pool].Coins[$Config.Coin].Port
	}
	else
	{
		$SessionConfig.Server = $Pools[$Config.Pool].Algos[$Config.Algo].Server
		$SessionConfig.Port = $Pools[$Config.Pool].Algos[$Config.Algo].Port
	}

	if ($Pools[$Config.Pool].Regions)
	{
		# zergpool uses no prefix for usa region, wonderful
		if (($Config.Pool -eq "zergpool") -And ($Config.Region -eq "usa"))
		{
			$RegionStr = ""
		}
		else
		{
			$RegionStr = $Config.Region + "."
		}

		$SessionConfig.Server = $SessionConfig.Server -Replace "%REGION%",$RegionStr
	}

	if ($Miners[$Config.Miner].Api)
	{
		$SessionConfig.Api = $true
	}
}

function Get-CurrencySupport ()
{
	if (-Not ($SessionConfig.Rates))
	{
		try
		{
			$ResponseRaw = Invoke-WebRequest -Uri $BlockchainUrl -UseBasicParsing
			$Response = $ResponseRaw | ConvertFrom-Json -AsHashtable

			foreach ($Currency in $Response.Keys)
			{
				$BtcRates.Add($Currency, $Response[$Currency].buy)
			}

			$SessionConfig.Rates = $true
		}
		catch
		{
			Write-PrettyError "Error obtaining BTC exchange rates! BTC to Fiat conversion is disabled."

			if ($Config.Debug)
			{
				Write-PrettyDebug $_.Exception
			}

			$SessionConfig.Rates = $false
		}
	}

	if ($SessionConfig.Rates)
	{
		$CurrencyStr = "Supported currencies:`r`n"
		$CurrencyStr += foreach ($Currency in $BtcRates.GetEnumerator() | Sort-Object -Property Name) { $Currency.Name }
		return $CurrencyStr
	}
}

function Test-CurrencyProperty ()
{
	if (-Not $SessionConfig.Rates)
	{
		# Out-Null this, coz it's printed by Receive-Property
		# also, if this would return, the currency wouldn't be asked for
		Get-CurrencySupport | Out-Null
	}

	if ($SessionConfig.Api -And $SessionConfig.Rates)
	{
		if (-Not ($Config.Currency))
		{
			Write-PrettyError ("Currency must be set!")
			return $false
		}

		$Config.Currency = $Config.Currency.ToUpper()

		if (-Not ($BtcRates.Contains($Config.Currency)))
		{
			Write-PrettyError ("The """ + $Config.Currency + """ currency is not supported!")

			return $false
		}
		else
		{
			return $true
		}
	}
	else
	{
		return $true
	}
}

function Test-ElectricityCostProperty ()
{
	if ($SessionConfig.Api -And $SessionConfig.Rates)
	{
		if (-Not ($Config.ElectricityCost))
		{
			Write-PrettyError ("Electricity cost must be set!")
			return $false
		}

		# make sure we don't miscalculate profits, e.g. don't convert 0,18 to 18
		if ($Config.ElectricityCost.Contains(","))
		{
			Write-PrettyError ("Invalid electricity cost, make sure to use '.' as decimal separator!")
			return $false
		}

		try
		{
			$Config.ElectricityCost = [System.Convert]::ToDouble($Config.ElectricityCost)
			return $true
		}
		catch
		{
			Write-PrettyError ("Invalid electricity cost, """ + $Config.ElectricityCost + """ is not a number!")
			return $false
		}
	}
	else
	{
		return $true
	}
}

function Test-ExtraArgsProperty ()
{
	# we don't care what the user enters, impossible to check
	return $true
}

function Initialize-Properties ()
{
	if ($FirstRun)
	{
		Write-PrettyInfo ("Welcome to RudeHash! Let's set up your configuration.")
		Write-PrettyInfo ("We'll ask your input for all config options. Some are optional, you can skip")
		Write-PrettyInfo ("those by pressing 'Enter'. Don't worry, if you try to specify an incompatible")
		Write-PrettyInfo ("setup, we will tell you and ask you to modify it. Not all options are used in")
		Write-PrettyInfo ("all scenarios, e.g. wallet address is unused on pools with their own balances.")
		Write-PrettyDots
	}

	Initialize-Property "Debug" $true $FirstRun
	Initialize-Property "Watchdog" $true $FirstRun
	Initialize-Property "MonitoringKey" $false $FirstRun
	Initialize-Property "MphApiKey" $false $FirstRun
	Initialize-Property "Pool" $true $FirstRun
	Initialize-Property "Worker" $true $FirstRun
	Initialize-Property "Wallet" $false $FirstRun
	Initialize-Property "WalletIsAltcoin" $false $FirstRun
	Initialize-Property "User" $false $FirstRun
	Initialize-Property "Region" $false $FirstRun
	Initialize-Property "Coin" $false $FirstRun
	Initialize-Property "Miner" $true $FirstRun
	Initialize-Property "Algo" $false $FirstRun

	Test-Compatibility

	Initialize-Property "Currency" $true $FirstRun
	Initialize-Property "ElectricityCost" $true $FirstRun
	Initialize-Property "ExtraArgs" $false $FirstRun
}

$RigStats =
@{
	GpuCount = 0;
	HashRate = 0;
	Difficulty = 0;
	PowerUsage = 0;
	EarningsBtc = 0;
	EarningsFiat = 0;
	Profit = 0;
	ExchangeRate = 0;
	FailedChecks = 0;
	DevMinutes = 0;
	Pid = 0;
	Uptime = New-TimeSpan;
}

function Initialize-Temp ()
{
	try
	{
		if (Test-Path $TempDir -ErrorAction Stop)
		{
			Remove-Item -Recurse -Force -Path $TempDir -ErrorAction Stop
		}

		New-Item -ItemType Directory -Path $TempDir -Force -ErrorAction Stop | Out-Null
	}
	catch
	{
		Write-PrettyError "Error setting up temporary directory! Do we have write access?"

		if ($Config.Debug)
		{
			Write-PrettyDebug $_.Exception
		}

		Exit-RudeHash
	}
}

function Read-MinerApi ($Request, $Critical)
{
	$Timeout = 10

	try
	{
		$Client = New-Object System.Net.Sockets.TcpClient "127.0.0.1", $MinerPort
		$Stream = $Client.GetStream()
		$Writer = New-Object System.IO.StreamWriter $Stream
		$Reader = New-Object System.IO.StreamReader $Stream
		$Client.SendTimeout = $Timeout * 1000
		$Client.ReceiveTimeout = $Timeout * 1000
		$Writer.AutoFlush = $true

		$Writer.WriteLine($Request)
		$Response = $Reader.ReadLine()
	}
	catch
	{
		Write-PrettyError "Error connecting to miner API!"

		if ($Config.Debug)
		{
			Write-PrettyDebug $_.Exception
		}

		if ($Critical -eq "true")
		{
			Write-PrettyError "Critical error, RudeHash cannot continue."
			Exit-RudeHash
		}
	}
	finally
	{
		if ($Reader) { $Reader.Close() }
		if ($Writer) { $Writer.Close() }
		if ($Stream) { $Stream.Close() }
		if ($Client) { $Client.Close() }
	}

	return $Response
}

function Resolve-PoolIp ()
{
	try
	{
		# make sure to flush the DNS cache first
		Start-Process "ipconfig" -ArgumentList "/flushdns" -Wait -NoNewWindow -RedirectStandardOutput nul -ErrorAction SilentlyContinue

		# wonderful workaround for PowerShell *and* .Net both lacking proper built-in DNS resolution
		#$Ip = ([System.Net.DNS]::GetHostEntry($SessionConfig.Server).AddressList[0].IPAddressToString)
		$Res = (Get-ProcessOutput "nslookup" "-type=A -retry=3 $($SessionConfig.Server) 9.9.9.9").Split("`r`n")
		$Ip = ($Res.Split("`r`n") | Select-String -Pattern "^Address")[1].ToString().Split(":")[1].Trim()

		# validate the IP address by casting it to IPAddress
		$Ip -match [ipaddress]$Ip | Out-Null

		if ($Config.Debug)
		{
			Write-PrettyDebug ("Stratum server $($SessionConfig.Server) resolves to: $($Ip)")
		}
	}
	catch
	{
		Write-PrettyError "Error resolving pool IP addess, falling back to URL! Is your network connection working?"

		if ($Config.Debug)
		{
			Write-PrettyDebug $_.Exception
		}

		# it's better than nothing, it might start working during stratum connection
		$Ip = $SessionConfig.Server
	}

	return $Ip
}

function Get-GpuCount ()
{
	switch ($Config.Miner)
	{
		{$_ -in "ccminer-allium", "ccminer-klaust", "ccminer-palginmod", "ccminer-phi", "ccminer-polytimos", "ccminer-rvn", "ccminer-tpruvot", "ccminer-xevan", "vertminer"}
		{
			$Response = Read-MinerApi 'summary' $false

			try
			{
				$Count = $Response.Split("|")[0].Split(";")[4].Split("=")[1]
			}
			catch
			{
				Write-PrettyError $MinerApiErrorStr

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}

		"dstm"
		{
			# dstm accepts any string as request, let's use the same as ccminer
			$ResponseRaw = Read-MinerApi 'summary' $false

			try
			{
				$Response = $ResponseRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
				$Count = $Response.result.length
			}
			catch
			{
				Write-PrettyError $MinerApiErrorStr

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}

		# api: https://github.com/ethereum-mining/ethminer/issues/295#issuecomment-353755310
		"ethminer"
		{
			$ResponseRaw = Read-MinerApi '{"id":0,"jsonrpc":"2.0","method":"miner_getstat1"}' $false

			try
			{
				$Response = $ResponseRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
				$Count = $Response.result[3].Split(";").length
			}
			catch
			{
				Write-PrettyError $MinerApiErrorStr

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}

		"excavator"
		{
			$ResponseRaw = Read-MinerApi '{"id":1,"method":"device.list","params":[]}' $true
			$Response = $ResponseRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
			$Count = $Response.devices.length
		}

		"zecminer"
		{
			$ResponseRaw = Read-MinerApi '{"id":"0", "method":"getstat"}' $false

			try
			{
				$Response = $ResponseRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
				$Count = $Response.result.length
			}
			catch
			{
				Write-PrettyError $MinerApiErrorStr

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}
	}

	$RigStats.GpuCount = $Count
}

function Start-Excavator ()
{
	$Excavator = [io.path]::combine($MinersDir, "excavator", "excavator.exe")
	$Args = "-p $MinerPort"

	if ($Config.Debug)
	{
		Write-PrettyDebug ("$Excavator $Args")
	}

	$Proc = Start-Process -FilePath $Excavator -ArgumentList $Args -PassThru -NoNewWindow -RedirectStandardOutput nul
	Write-PrettyInfo "Determining the number of GPUs..."
	Start-Sleep -Seconds 5
	return $Proc
}

function Initialize-Json ($User, $Pass)
{
	$Count = $RigStats.GpuCount
	$ExcavatorJson = @"
[
	{"time":0,"commands":[
		{"id":1,"method":"algorithm.add","params":["$($ExcavatorAlgos[$Config.Algo])","$(Resolve-PoolIp):$($SessionConfig.Port)","$($User):$($Pass)"]}
	]},
	{"time":3,"commands":[
		$(for ($i = 0; $i -lt $Count; $i++)
		{
			$Line = "{""id"":1,""method"":""worker.add"",""params"":[""0"",""$i""]}"
			if (($Count - $i) -gt 1)
			{
				$Line += ",`r`n"
			}
			Write-Output $Line
		})
	]},
	{"time":10,"loop":20,"commands":[
		$(for ($i = 0; $i -lt $Count; $i++)
		{
			$Line = "{""id"":1,""method"":""worker.print.speed"",""params"":[""$i""]}"
			if (($Count - $i) -gt 1)
			{
				$Line += ",`r`n"
			}
			Write-Output $Line
		})
	]}
]
"@
	#{"id":1,"method":"algorithm.print.speeds","params":[]}
	return $ExcavatorJson
}

function Initialize-Excavator ($User, $Pass)
{
	$Proc = Start-Excavator
	Get-GpuCount
	Stop-Process $Proc

	if ($RigStats.GpuCount -gt 1)
	{
		$Suffix = "s"
	}

	Write-PrettyInfo ($RigStats.GpuCount.ToString() + " GPU" + $Suffix + " detected.")

	$Json = Initialize-Json $User $Pass
	$JsonFile = [io.path]::combine($TempDir, "excavator.json")

	try
	{
		Set-Content -LiteralPath $JsonFile -Value $Json -ErrorAction Stop
	}
	catch
	{
		Write-PrettyError "Error writing Excavator JSON file! Make sure the file is not locked by another process!"

		if ($Config.Debug)
		{
			Write-PrettyDebug $_.Exception
		}

		Exit-RudeHash
	}
}

function Initialize-MinerArgs ()
{
	switch ($Config.Pool)
	{
		{$_ -in "miningpoolhub", "suprnova" }
		{
			$PoolUser = $Config.User + "." + $Config.Worker
			$PoolPass = "x"
		}
		"nicehash"
		{
			# https://www.nicehash.com/help/how-to-create-a-worker
			$PoolUser = $Config.Wallet + "." + $Config.Worker
			$PoolPass = "x"
		}
		"poolr"
		{
			$PoolUser = $Config.Wallet
			$PoolPass = "c=" + $Config.Coin.ToUpper() + ",ID=" + $Config.Worker
		}
		"zergpool"
		{
			$PoolUser = $Config.Wallet

			if ($SessionConfig.CoinMode)
			{
				# zergpool only accepts the coin in uppercase
				if ($Config.WalletIsAltcoin)
				{
					$PoolPass = "c=" + $Config.Coin.ToUpper() + ",mc="+ $Config.Coin.ToUpper() + ",ID=" + $Config.Worker
				}
				else
				{
					$PoolPass = "c=BTC,mc="+ $Config.Coin.ToUpper() + ",ID=" + $Config.Worker
				}
			}
			else
			{
				$PoolPass = "c=BTC,ID=" + $Config.Worker
			}
		}
		"zpool"
		{
			$PoolUser = $Config.Wallet
			# zpool only guarantees BTC payouts, so we enforce it, potentially suboptimal coin is better than completely lost mining
			$PoolPass = "c=BTC,ID=" + $Config.Worker
		}
	}

	# always update the IP, the miner could've crashed because of an IP change to begin with
	$PoolIp = Resolve-PoolIp

	switch ($Config.Miner)
	{
		{$_ -in "ccminer-allium", "ccminer-klaust", "ccminer-palginmod", "ccminer-phi", "ccminer-rvn", "ccminer-tpruvot", "ccminer-xevan" } { $Args = "--algo=" + $Config.Algo + " --url=stratum+tcp://" + $PoolIp + ":" + $SessionConfig.Port + " --user=" + $PoolUser + " --pass " + $PoolPass + " --api-bind 127.0.0.1:" + $MinerPort }
		"ccminer-polytimos" { $Args = "--algo=poly --url=stratum+tcp://" + $PoolIp + ":" + $SessionConfig.Port + " --user=" + $PoolUser + " --pass " + $PoolPass + " --api-bind 127.0.0.1:" + $MinerPort }
		"dstm" { $Args = "--server " + $PoolIp + " --user " + $PoolUser + " --pass " + $PoolPass + " --port " + $SessionConfig.Port + " --telemetry=127.0.0.1:" + $MinerPort + " --noreconnect" }
		"ethminer" { $Args = "--cuda --stratum " + $PoolIp + ":" + $SessionConfig.Port + " --userpass " + $PoolUser + ":" + $PoolPass + " --api-port " + $MinerPort + " --stratum-protocol " + $Pools[$Config.Pool].StratumProto }
		"excavator"
		{
			Initialize-Excavator $PoolUser $PoolPass
			$Args = "-c " + [io.path]::combine($TempDir, "excavator.json") + " -p " + $MinerPort
		}
		{$_ -in "hsrminer-hsr", "hsrminer-neoscrypt" } { $Args = "--url=stratum+tcp://" + $PoolIp + ":" + $SessionConfig.Port + " --userpass=" + $PoolUser + ":" + $PoolPass }
		"vertminer" { $Args = "-o stratum+tcp://" + $PoolIp + ":" + $SessionConfig.Port + " -u " + $PoolUser + " -p " + $PoolPass + " --api-bind 127.0.0.1:" + $MinerPort }
		"zecminer" { $Args = "--server " + $PoolIp + " --user " + $PoolUser + " --pass " + $PoolPass + " --port " + $SessionConfig.Port + " --api 127.0.0.1:" + $MinerPort }
	}

	if ($Config.ExtraArgs)
	{
		$Args += " " + $Config.ExtraArgs
	}

	return $Args
}

function Get-HashRate ()
{
	$HashRate = 0

	switch ($Config.Miner)
	{
		{$_ -in "ccminer-allium", "ccminer-klaust", "ccminer-palginmod", "ccminer-phi", "ccminer-polytimos", "ccminer-rvn", "ccminer-tpruvot", "ccminer-xevan", "vertminer"}
		{
			$Response = Read-MinerApi 'threads' $false

			try
			{
				for ($i = 0; $i -lt $RigStats.GpuCount; $i++)
				{
					$GpuStr = $Response.Split("|")[$i]
					[System.Collections.Hashtable]$GpuStats = @{}

					foreach ($Item in $GpuStr.Split(";"))
					{
						$GpuStats.Add($Item.Split("=")[0], $Item.Split("=")[1])
					}

					$HashRate += $GpuStats["KHS"]
					$GpuStats.Clear()
				}

				# ccminer returns KH/s
				$HashRate *= 1000
			}
			catch
			{
				Write-PrettyError $MinerApiErrorStr

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}

		"dstm"
		{
			# dstm accepts any string as request, let's use the same as ccminer
			$ResponseRaw = Read-MinerApi 'summary' $false

			try
			{
				$Response = $ResponseRaw | ConvertFrom-Json -ErrorAction SilentlyContinue

				for ($i = 0; $i -lt $RigStats.GpuCount; $i++)
				{
					$HashRate += $Response.result[$i].sol_ps
				}
			}
			catch
			{
				Write-PrettyError $MinerApiErrorStr

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}

		"ethminer"
		{
			$ResponseRaw = Read-MinerApi '{"id":0,"jsonrpc":"2.0","method":"miner_getstathr"}' $false

			try
			{
				$Response = $ResponseRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
				$HashRate = $Response.result.ethhashrate
			}
			catch
			{
				Write-PrettyError $MinerApiErrorStr

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}

		"excavator"
		{
			$ResponseRaw = Read-MinerApi '{"id":1,"method":"algorithm.list","params":[]}' $false

			try
			{
				$Response = $ResponseRaw | ConvertFrom-Json -ErrorAction SilentlyContinue

				for ($i = 0; $i -lt $RigStats.GpuCount; $i++)
				{
					$HashRate += $Response.algorithms.workers[$i].speed[0]
				}
			}
			catch
			{
				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}

		"zecminer"
		{
			$ResponseRaw = Read-MinerApi '{"id":"0", "method":"getstat"}' $false

			try
			{
				$Response = $ResponseRaw | ConvertFrom-Json -ErrorAction SilentlyContinue

				for ($i = 0; $i -lt $RigStats.GpuCount; $i++)
				{
					$HashRate += $Response.result[$i].speed_sps
				}
			}
			catch
			{
				Write-PrettyError $MinerApiErrorStr

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}
	}

	$RigStats.HashRate = ([math]::Round($HashRate, 0))
}

function Get-PrettyHashRate ($HashRate)
{
	if ($HashRate -ge 1000000)
	{
		return (([math]::Round(($HashRate / 1000000), 2)).ToString() + " MH/s")
	}
	elseif ($HashRate -ge 1000)
	{
		return (([math]::Round(($HashRate / 1000), 2)).ToString() + " kH/s")
	}
	else
	{
		return ([math]::Round($HashRate, 2).ToString() + " H/s")
	}
}

function Get-PowerUsage ()
{
	$PowerUsage = 0

	switch ($Config.Miner)
	{
		{$_ -in "ccminer-allium", "ccminer-klaust", "ccminer-palginmod", "ccminer-phi", "ccminer-polytimos", "ccminer-rvn", "ccminer-tpruvot", "ccminer-xevan", "vertminer"}
		{
			$Response = Read-MinerApi 'threads' $false

			try
			{
				for ($i = 0; $i -lt $RigStats.GpuCount; $i++)
				{
					$GpuStr = $Response.Split("|")[$i]
					[System.Collections.Hashtable]$GpuStats = @{}

					foreach ($Item in $GpuStr.Split(";"))
					{
						$GpuStats.Add($Item.Split("=")[0], $Item.Split("=")[1])
					}

					$PowerUsage += $GpuStats["POWER"]
					$GpuStats.Clear()
				}

				# these return mW instead of W, because reasons
				# most likely ccminer-phi also returns mW, but I really don't know coz it always returns 0 lol
				if ($Config.Miner.StartsWith("ccminer"))
				{
					$PowerUsage /= 1000
				}
			}
			catch
			{
				Write-PrettyError $MinerApiErrorStr

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}

		"dstm"
		{
			# dstm accepts any string as request, let's use the same as ccminer
			$ResponseRaw = Read-MinerApi 'summary' $false

			try
			{
				$Response = $ResponseRaw | ConvertFrom-Json -ErrorAction SilentlyContinue

				for ($i = 0; $i -lt $RigStats.GpuCount; $i++)
				{
					$PowerUsage += $Response.result[$i].power_usage
				}
			}
			catch
			{
				Write-PrettyError $MinerApiErrorStr

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}

		"ethminer"
		{
			$ResponseRaw = Read-MinerApi '{"id":0,"jsonrpc":"2.0","method":"miner_getstathr"}' $false

			try
			{
				$Response = $ResponseRaw | ConvertFrom-Json -ErrorAction SilentlyContinue

				for ($i = 0; $i -lt $RigStats.GpuCount; $i++)
				{
					$PowerUsage += [math]::Round($Response.result.powerusages[$i], 0)
				}
			}
			catch
			{
				Write-PrettyError $MinerApiErrorStr

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}

		"excavator"
		{
			for ($i = 0; $i -lt $RigStats.GpuCount; $i++)
			{
				$ResponseRaw = Read-MinerApi '{"id":1,"method":"device.get","params":["0"]}' $false

				try
				{
					$Response = $ResponseRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
					$PowerUsage += ([math]::Round($Response.gpu_power_usage, 0))
				}
				catch
				{
					if ($Config.Debug)
					{
						Write-PrettyDebug $_.Exception
					}
				}
			}
		}

		"zecminer"
		{
			$ResponseRaw = Read-MinerApi '{"id":"0", "method":"getstat"}' $false

			try
			{
				$Response = $ResponseRaw | ConvertFrom-Json -ErrorAction SilentlyContinue

				for ($i = 0; $i -lt $RigStats.GpuCount; $i++)
				{
					$PowerUsage += $Response.result[$i].gpu_power_usage
				}
			}
			catch
			{
				Write-PrettyError $MinerApiErrorStr

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}
	}

	$RigStats.PowerUsage = $PowerUsage
}

function Measure-Earnings ()
{
	if ($SessionConfig.CoinMode)
	{
		$HashRate = $RigStats.HashRate / $WtmModifiers[$Config.Algo]
		$WtmUrl = "https://whattomine.com/coins/" + $Coins[$Config.Coin].WtmPage + "?hr=" + $HashRate + "&p=0&cost=0&fee=" + $Pools[$Config.Pool].PoolFee + "&commit=Calculate"

		try
		{
			$WtmHtml = Invoke-WebRequest -Uri $WtmUrl -UseBasicParsing -ErrorAction SilentlyContinue
		}
		catch
		{
			Write-PrettyError "WhatToMine request failed! Is your network connection working?"

			if ($Config.Debug)
			{
				Write-PrettyDebug $_.Exception
			}
		}

		$WtmObj = $WtmHtml.Content -split "[`r`n]"
		$LineNo = $WtmObj | Select-String -Pattern "Estimated Rewards" | Select-Object -ExpandProperty 'LineNumber'

		try
		{
			$BtcEarnings = [System.Convert]::ToDouble(($WtmObj | Select-Object -Index ($LineNo + 46)).Trim())
			$RigStats.EarningsBtc = [math]::Round($BtcEarnings, 8)

			if ($SessionConfig.Rates)
			{
				$RigStats.EarningsFiat = [math]::Round(($RigStats.EarningsBtc * $BtcRates[$Config.Currency]), 2)
			}
		}
		catch
		{
			Write-PrettyError "Malformed WhatToMine response."

			if ($Config.Debug)
			{
				Write-PrettyDebug $_.Exception
			}
		}
	}
	else
	{
		if ($Pools[$Config.Pool].ApiUrl)
		{
			try
			{
				[double]$HashRate = $RigStats.HashRate / $Pools[$Config.Pool].Algos[$Config.Algo].Modifier
				[double]$Multiplier = 1 - ($Pools[$Config.Pool].PoolFee / 100)
				$Response = Invoke-RestMethod -Uri $Pools[$Config.Pool].ApiUrl -UseBasicParsing -ErrorAction SilentlyContinue

				switch ($Config.Pool)
				{
					"nicehash" { [double]$Price = $Response.result.stats[$Pools[$Config.Pool].Algos[$Config.Algo].Id].price }
					{$_ -in "zergpool", "zpool"} { [double]$Price = $Response.($Config.Algo).estimate_current }
				}

				$RigStats.EarningsBtc = [math]::Round(($HashRate * $Price * $Multiplier), 8)

				if ($SessionConfig.Rates)
				{
					$RigStats.EarningsFiat = [math]::Round(($RigStats.EarningsBtc * $BtcRates[$Config.Currency]), 2)
				}
			}
			catch
			{
				Write-PrettyError "$($Pools[$Config.Pool].Name) API request failed! Earnings estimations will not work."

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}
	}
}

function Update-ExchangeRates ()
{
	try
	{
		$ResponseRaw = Invoke-WebRequest -Uri $BlockchainUrl -UseBasicParsing
		$Response = $ResponseRaw | ConvertFrom-Json -AsHashtable

		foreach ($Currency in $Response.Keys)
		{
			$BtcRates[$Currency] = $Response[$Currency].buy
		}
	}
	catch
	{
		Write-PrettyError "Error updating BTC exchange rates! Is your network connection working?"

		if ($Config.Debug)
		{
			Write-PrettyDebug $_.Exception
		}
	}
}

function Measure-Profit ()
{
	Update-ExchangeRates
	$RigStats.Profit = [math]::Round($RigStats.EarningsFiat - ($Config.ElectricityCost * $RigStats.PowerUsage * 24 / 1000), 2)
}

function Get-Archive ($Url, $FileName)
{
	$DestFile = [io.path]::combine($TempDir, $FileName)
	$Client = New-Object System.Net.WebClient

	try
	{
		$Client.DownloadFile($Url, $DestFile)
	}
	catch
	{
		Write-PrettyError "Error downloading package! Is your network connection working?"

		if ($Config.Debug)
		{
			Write-PrettyDebug $_.Exception
		}

		Exit-RudeHash
	}

	return $TempDir
}

function Expand-Stuff ($File, $DestDir)
{
	if ($File.EndsWith(".7z"))
	{
		Start-Process -FilePath ([io.path]::combine($ToolsDir, "7zip", $Tools["7zip"].ExeFile)) -ArgumentList ("x -o$DestDir $File") -NoNewWindow -Wait
	}
	elseif ($File.EndsWith(".exe"))
	{
		New-Item -ItemType Directory -Path $DestDir | Out-Null
		Move-Item -Path $File -Destination $DestDir
	}
	else
	{
		Expand-Archive -LiteralPath $File -DestinationPath $DestDir
	}
}

function Test-Tool ($Name)
{
	$ToolDir = [io.path]::combine($ToolsDir, $Name)
	$ToolExe = [io.path]::combine($ToolDir, $Tools[$Name].ExeFile)

	if (-Not (Test-Path -LiteralPath $ToolsDir))
	{
		New-Item -ItemType Directory -Path $ToolsDir | Out-Null
	}

	if (-Not (Test-Path -LiteralPath $ToolExe))
	{
		if (Test-Path -LiteralPath $ToolDir)
		{
			Remove-Item -Recurse -Force -Path $ToolDir
		}

		Write-PrettyInfo ("Downloading " + $Name + "...")
		$ArchiveDir = (Get-Archive ($Tools[$Name].Url) ($Tools[$Name].ArchiveFile))

		if ($Tools[$Name].FilesInRoot)
		{
			$DestPath = ([io.path]::combine($ArchiveDir, $Name))
		}
		else
		{
			$DestPath = $ArchiveDir
		}

		Expand-Stuff ([io.path]::combine($ArchiveDir, $Tools[$Name].ArchiveFile)) $DestPath

		if (-Not ($Tools[$Name].FilesInRoot))
		{
			# don't try to rename tool dir to itself
			if (((Get-ChildItem -Directory $ArchiveDir | Select-Object -First 1).FullName).Split('\')[-1] -eq $Name)
			{
				$DestPath = [io.path]::combine($ArchiveDir, $Name)
			}
			else
			{
				$DestPath = (Rename-Item -Path (Get-ChildItem -Directory $ArchiveDir | Select-Object -First 1).FullName -NewName $Name -PassThru).FullName
			}
		}

		Move-Item -Force $DestPath $ToolsDir
	}
}

function Test-Tools ()
{
	foreach ($Tool in $Tools.Keys)
	{
		Test-Tool $Tool
	}
}

function Get-ProcessOutput ($Exe, $Argus)
{
	$ProcInfo = New-Object System.Diagnostics.ProcessStartInfo
	$ProcInfo.FileName = $Exe
	# stupid PowerShell, $Args is a reserved word
	$ProcInfo.Arguments = $Argus
	$ProcInfo.RedirectStandardOutput = $true
	# nslookup prints "non-authoritative answer" line to stderr because reasons
	$ProcInfo.RedirectStandardError = $true
	$ProcInfo.UseShellExecute = $false

	$Proc = New-Object System.Diagnostics.Process
	$Proc.StartInfo = $ProcInfo
	$Proc.Start() | Out-Null
	$Proc.WaitForExit()
	$Str = $Proc.StandardOutput.ReadToEnd()
	#$Str += $Proc.StandardError.ReadToEnd()

	return $Str
}

function Get-MinerVersion ($Name)
{
	$MinerDir = [io.path]::combine($MinersDir, $Name)
	$MinerExe = [io.path]::combine($MinerDir, $Miners[$Name].ExeFile)

	try {
		switch ($Name)
		{
			# klaust messes up stdio, can't determine version reliably
			#"ccminer-klaust" { $VersionStr = (Get-ProcessOutput $MinerExe "-V").Split("`r`n")[0].Split(" ")[1].Split("-")[0] }
			"ccminer-phi" { $VersionStr = (Get-ProcessOutput $MinerExe "-V").Split("`r`n")[0].Split("-")[1] }
			{$_ -in "ccminer-allium", "ccminer-palginmod", "ccminer-rvn", "ccminer-tpruvot"} { $VersionStr = (Get-ProcessOutput $MinerExe "-V").Split("`r`n")[0].Split(" ")[2] }
			"dstm" { $VersionStr = (Get-ProcessOutput $MinerExe "").Split("`r`n")[0].Split(" ")[1].Split(",")[0] }
			"ethminer" { $VersionStr = (Get-ProcessOutput $MinerExe "-V").Split("`r`n")[0].Split(" ")[2].Split("+")[0] }
			"excavator" { $VersionStr = (Get-ProcessOutput $MinerExe "-h").Split("`r`n")[2].Trim().Split(" ")[1].Substring(1) }
			{$_ -in "hsrminer-hsr", "hsrminer-neoscrypt" } { $VersionStr = (Get-ProcessOutput $MinerExe "-v").Split("`r`n")[17].Trim().Split(" ")[3] }
			"vertminer" { $VersionStr = (Get-ProcessOutput $MinerExe "-V").Split("`r`n")[0].Split(" ")[2] }
			"zecminer" { $VersionStr = (Get-ProcessOutput $MinerExe "-V").Split("`r`n")[1].Split("|")[1].Trim().Split(" ")[4] }
		}
	}
	catch
	{
		$VersionStr = "UNKNOWN"
	}

	return $VersionStr
}

function Test-Miner ($Name)
{
	$MinerDir = [io.path]::combine($MinersDir, $Name)
	$MinerExe = [io.path]::combine($MinerDir, $Miners[$Name].ExeFile)

	# create main miners dir if missing
	if (-Not (Test-Path -LiteralPath $MinersDir))
	{
		New-Item -ItemType Directory -Path $MinersDir | Out-Null
	}

	$MinerExists = Test-Path -LiteralPath $MinerExe

	# update check
	if ($Miners[$Name].Version)
	{
		$LatestVer = $Miners[$Name].Version
		$VersionStr = " v" + $LatestVer

		if ($MinerExists)
		{
			$CurrentVer = Get-MinerVersion $Name

			if (-Not ($LatestVer -eq $CurrentVer))
			{
				if ($CurrentVer -eq "UNKNOWN")
				{
					Write-PrettyInfo ("Unknown " + $Name + " version found, it will be replaced with v" + $LatestVer + ".")
				}
				else
				{
					Write-PrettyInfo ($Name + " v" + $CurrentVer + " found, it will be updated to v" + $LatestVer + ".")
				}

				try
				{
					Remove-Item -Recurse -Force -Path $MinerDir
				}
				catch
				{
					Write-PrettyError ("Error removing " + $Name + " v" + $CurrentVer + "!")
					Exit-RudeHash
				}

				$MinerExists = $false
			}
			elseif ($Config.Debug)
			{
				Write-PrettyDebug ($Name + " v" + $CurrentVer + " found, it is the latest version.")
			}
		}
	}

	if (-Not $MinerExists)
	{
		if (Test-Path -LiteralPath $MinerDir)
		{
			Remove-Item -Recurse -Force -Path $MinerDir
		}

		Write-PrettyInfo ("Downloading " + $Name + $VersionStr + "...")
		$ArchiveDir = (Get-Archive ($Miners[$Name].Url) ($Miners[$Name].ArchiveFile))

		if ($Miners[$Name].FilesInRoot)
		{
			$DestPath = ([io.path]::combine($ArchiveDir, $Name))
		}
		else
		{
			$DestPath = $ArchiveDir
		}

		Expand-Stuff ([io.path]::combine($ArchiveDir, $Miners[$Name].ArchiveFile)) $DestPath

		if (-Not ($Miners[$Name].FilesInRoot))
		{
			# don't try to rename miner dir to itself
			if (((Get-ChildItem -Directory $ArchiveDir | Select-Object -First 1).FullName).Split('\')[-1] -eq $Name)
			{
				$DestPath = [io.path]::combine($ArchiveDir, $Name)
			}
			else
			{
				$DestPath = (Rename-Item -Path (Get-ChildItem -Directory $ArchiveDir | Select-Object -First 1).FullName -NewName $Name -PassThru).FullName
			}
		}

		Move-Item -Force $DestPath $MinersDir
	}
}

function Set-WindowTitle ()
{
	# $Sep = " `u{25a0 | 25bc} "
	$Sep = " `u{2219} "

	if ($SessionConfig.CoinMode)
	{
		$CoinStr = ("Coin: " + $Coins[$Config.Coin].Name + $Sep)
	}
	else
	{
		$CoinStr = ""
	}

	if ($Pools[$Config.Pool].Authless)
	{
		$WalletStr = $Sep + "Wallet: " + $Config.Wallet
		$WorkerStr = "Worker: " + $Config.Worker + $Sep
	}
	else
	{
		$WalletStr = ""
		$WorkerStr = "Worker: " + $Config.User + "." + $Config.Worker + $Sep
	}

	$Host.UI.RawUI.WindowTitle = "RudeHash" + $Sep + "Pool: " + $Pools[$Config.Pool].Name + $Sep + $WorkerStr + $CoinStr + "Algo: " + $AlgoNames[$Config.Algo] + $Sep + "Miner: " + $Config.Miner + $WalletStr
}

function Update-MinerUptime ()
{
	try
	{
		$Proc = Get-Process -Id $RigStats.Pid -ErrorVariable Err -ErrorAction SilentlyContinue
		$RigStats.Uptime = New-TimeSpan -Start $Proc.StartTime -End (Get-Date)
	}
	catch
	{
		Write-PrettyError "Error while checking the miner's uptime!"

		if ($Config.Debug)
		{
			Write-PrettyDebug $Err
		}
	}
}

function Get-PrettyUptime ()
{
	return "$($RigStats.Uptime.Days)d $($RigStats.Uptime.Hours)h $($RigStats.Uptime.Minutes)m"
}

function Read-Stats ()
{
	Update-MinerUptime

	if ($SessionConfig.DevMining)
	{
		$RigStats.HashRate = 0;
		$RigStats.PowerUsage = 0;
		$RigStats.EarningsBtc = 0;
	}
	elseif ($SessionConfig.Api)
	{
		if ($RigStats.GpuCount -eq 0)
		{
			Get-GpuCount
		}
		else
		{
			Get-HashRate
			Get-PowerUsage

			if (($SessionConfig.CoinMode -And $Coins[$Config.Coin].WtmPage) -Or (-Not ($SessionConfig.CoinMode) -And $Pools[$Config.Pool].ApiUrl))
			{
				Measure-Earnings

				if ($SessionConfig.Rates)
				{
					if ($RigStats.PowerUsage -gt 0)
					{
						Measure-Profit
					}
				}
			}
		}
	}
}

function Write-Stats ()
{
	if ($SessionConfig.DevMining)
	{
		Write-PrettyInfo ("Dev mining minutes " + $RigStats.DevMinutes  + "/10")
	}
	elseif ($SessionConfig.Api)
	{
		if (-Not ($RigStats.GpuCount -eq 0))
		{
			$Sep = " `u{2219} "

			# ccminer-phi seems to always report 0 watts
			if ($RigStats.PowerUsage -gt 0)
			{
				$PowerUsageStr = $Sep + "Power Usage: " + $RigStats.PowerUsage + " W"
			}

			Write-PrettyInfo ("Uptime: " + (Get-PrettyUptime) + $Sep + "Number of GPUs: " + $RigStats.GpuCount + $Sep + "Hash Rate: " + (Get-PrettyHashRate $RigStats.HashRate) + $PowerUsageStr)

			# use WTM for coins, NH for algos
			if (($SessionConfig.CoinMode -And $Coins[$Config.Coin].WtmPage) -Or (-Not ($SessionConfig.CoinMode) -And $Pools[$Config.Pool].ApiUrl))
			{
				# we could keep trying to obtain exchange rates, but if it would eventually succeed and the
				# list didn't contain the currency specified in the config, it'd result in indexing errors
				# or we could re-check the property, but then it'd cause mining to stop; neither is desirable
				if ($SessionConfig.Rates)
				{
					$FiatStr = " / " + $RigStats.EarningsFiat + " " + $Config.Currency

					if ($RigStats.PowerUsage -gt 0)
					{
						$ProfitStr = $Sep + "Daily profit: " + $RigStats.Profit + " " + $Config.Currency
					}
				}

				Write-PrettyEarnings ("Daily earnings: " + $RigStats.EarningsBtc + " BTC" + $FiatStr + $ProfitStr)
			}
		}
	}
}

function Start-Miner ()
{
	# in the extremely rare case of AV deleting the miner, or even 7-Zip, try to re-download
	Test-Tools
	Test-Miner $Config.Miner

	$Exe = [io.path]::combine($MinersDir, $Config.Miner, $Miners[$Config.Miner].ExeFile)
	$Args = Initialize-MinerArgs

	if ($Config.Debug)
	{
		Write-PrettyDebug ("Stratum address: " + $SessionConfig.Server + ":" + $SessionConfig.Port)
		Write-PrettyDebug ("Miner command line: $Exe $Args")
	}

	$Proc = Start-Process -FilePath $Exe -ArgumentList $Args -PassThru -NoNewWindow
	$RigStats.Pid = $Proc.Id
	return $Proc
}

function Enable-DevMining ()
{
	# we could just re-read the config file but that might cause a file access error in the middle of the day
	# let's just make sure we don't do anything risky
	$FileConfig.Pool = $Config.Pool
	$Config.Pool = "zpool"

	$FileConfig.Algo = $Config.Algo
	$Config.Algo = "equihash"

	$FileConfig.Miner = $Config.Miner
	$Config.Miner = "dstm"

	$FileConfig.Coin = $Config.Coin
	$Config.Coin = ""

	$FileConfig.Wallet = $Config.Wallet
	$Config.Wallet = "1HFapEBFTyaJ74SULTJ5oN5BK3C5AYHWzk"

	$FileConfig.ExtraArgs = $Config.ExtraArgs
	$Config.ExtraArgs = ""

	# update server, port, etc
	Test-Compatibility
}

function Disable-DevMining ()
{
	$Config.Pool = $FileConfig.Pool
	$Config.Algo = $FileConfig.Algo
	$Config.Miner = $FileConfig.Miner
	$Config.Coin = $FileConfig.Coin
	$Config.Wallet = $FileConfig.Wallet
	$Config.ExtraArgs = $FileConfig.ExtraArgs

	# update server, port, etc
	Test-Compatibility
}

function Test-DevMining ($Proc)
{
	if ($SessionConfig.DevMining)
	{
		$RigStats.DevMinutes += 1
	}
	# only start devfee processing if user's miner has been running for 24 hours straight
	elseif ($RigStats.Uptime.Hours -ge 24)
	{
		Write-PrettyInfo ("Starting dev mining...")
		Enable-DevMining
		Stop-Process $Proc
		Start-Sleep 5
		$Proc = Start-Miner
		$SessionConfig.DevMining = $true
	}

	if ($RigStats.DevMinutes -ge 10)
	{
		Write-PrettyInfo ("Stopping dev mining...")
		Disable-DevMining
		Stop-Process $Proc
		Start-Sleep 5
		$Proc = Start-Miner
		$RigStats.DevMinutes = 0
		$SessionConfig.DevMining = $false
	}

	return $Proc
}

function Ping-Miner ($Proc)
{
	if ($SessionConfig.Api -And $Config.Watchdog -And (-Not ($SessionConfig.DevMining)))
	{
		if ($RigStats.HashRate -eq 0)
		{
			$RigStats.FailedChecks += 1

			if ($RigStats.FailedChecks -ge 2)
			{
				$Suffix = "s"
			}

			if ($Config.Debug)
			{
				Write-PrettyDebug ("Watchdog detected zero hash rate " + $RigStats.FailedChecks + " time" + $Suffix + ".")
			}
		}

		if ($RigStats.FailedChecks -ge 5)
		{
			Write-PrettyError "Watchdog detected zero hash rate, restarting miner..."
			Stop-Process $Proc
			# let the dust settle
			Start-Sleep 5
			$Proc = Start-Miner
			$RigStats.FailedChecks = 0
		}
	}

	return $Proc
}

function Ping-Monitoring ()
{
	if ($Config.MonitoringKey -Or $Config.MphApiKey)
	{
		if ($SessionConfig.DevMining)
		{
			$Name = "dev fee"
			$Active = ($RigStats.DevMinutes * 10).ToString() + " %"
		}
		else
		{
			$Name = $Config.Miner
			$Active = Get-PrettyUptime
		}

		$MinerStats= @{
			Name = $Name
			Path = $Miners[$Config.Miner].ExeFile
			Type = @()
			PID = $RigStats.Pid
			Active = $Active
			Algorithm = @($AlgoNames[$Config.Algo])
			Pool = @($Pools[$Config.Pool].Name)
			'BTC/day' = $RigStats.EarningsBtc
		}

		# if sent as array, MPM Monitoring displays it as H/s regardless of suffix
		# if not sent as array, MPH Stats errors out completely
		# because reasons.
		$HashRate = Get-PrettyHashRate $RigStats.HashRate

		if ($Config.MonitoringKey)
		{
			try
			{
				$MinerStats.Add("CurrentSpeed", $HashRate)
				$MinerStats.Add("EstimatedSpeed", $HashRate)
				$MinerJson = ConvertTo-Json @($MinerStats)
				$MinerStats.Remove("CurrentSpeed")
				$MinerStats.Remove("EstimatedSpeed")

				$Response = Invoke-RestMethod -Uri $MonitoringUrl -Method Post -Body @{ address = $Config.MonitoringKey; workername = $Config.Worker; miners = $MinerJson; profit = $RigStats.EarningsBtc } -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue

				if ($Config.Debug)
				{
					#Write-PrettyDebug $MinerJson
					Write-PrettyDebug ("Monitoring server response: $Response")
				}
			}
			catch
			{
				Write-PrettyError "Error while pinging the monitoring server!"

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}

		if ($Config.MphApiKey)
		{
			try
			{
				$MinerStats.Add("CurrentSpeed", @($HashRate))
				$MinerStats.Add("EstimatedSpeed", @($HashRate))
				$MinerJson = ConvertTo-Json @($MinerStats)

				$Response = Invoke-RestMethod -Uri ($MphStatsUrl + $Config.MphApiKey) -Method Post -Body @{ workername = $Config.Worker; miners = $MinerJson; profit = $RigStats.EarningsBtc } -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
			}
			catch
			{
				Write-PrettyError "Error while pinging the MiningPoolHubStats server!"

				if ($Config.Debug)
				{
					Write-PrettyDebug $_.Exception
				}
			}
		}
	}
}

function Start-RudeHash ()
{
	# restart automatically if the miner crashes
	while (1)
	{
		# get GPU count quickly, but not on excavator, it knows the GPU count already
		if ($FirstLoop -And $SessionConfig.Api -And (-Not($Config.Miner -eq "excavator")))
		{
			$Delay = 15
		}
		else
		{
			$Delay = 60
		}

		if ($FirstLoop -or $Proc.HasExited)
		{
			if ($Proc.HasExited)
			{
				Write-PrettyError ("Miner has crashed, restarting...")
			}

			$Proc = Start-Miner
		}
		else
		{
			Read-Stats
			$Proc = Ping-Miner $Proc
			$Proc = Test-DevMining $Proc
			Write-Stats
			Ping-Monitoring
		}

		Start-Sleep -Seconds $Delay

		$FirstLoop = $false
	}
}

Write-PrettyHeader
Initialize-Temp
Initialize-Properties
Set-WindowTitle
Test-Miner "dstm"
Start-RudeHash
