# speedtest 0.1.1
# carsten.giese@nexthink.com
 
# reference-code in python:
# https://github.com/sivel/speedtest-cli/blob/master/speedtest.py
 
cls
Remove-Variable * -ea 0
 
# input-paramters:
# how often do you want to download the test-file?:
$repetition = 3
 
# define settings for http-client:
Add-Type -AssemblyName System.Net.Http
$ignoreCerts = [System.Net.Http.HttpClientHandler]::DangerousAcceptAnyServerCertificateValidator
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.ServerCertificateCustomValidationCallback = $ignoreCerts
#$handler.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
#$handler.Proxy = [System.Net.WebProxy]::GetDefaultProxy()
$web = [System.Net.Http.HttpClient]::new($handler)
$web.Timeout = [System.TimeSpan]::FromSeconds(60)
$web.DefaultRequestHeaders.Add("User-Agent", '.')
 
$result =$web.GetAsync("https://www.speedtest.net/speedtest-config.php").Result
[xml]$content = $result.Content.ReadAsStringAsync().Result
if (!$content) {
    "no connection to speedtest."
    break
}
 
# a lot of optional parameters here for later full implementation.
$server_config = $content.settings.'server-config'
$download     = $content.settings.download
$upload       = $content.settings.upload
$client       = $content.settings.client
$pcLat = [float]$client.lat
$pcLon = [float]$client.lon
 
$ignore_servers = $content.settings.'server-config'.ignoreids.Split(",")
$ratio = [int]$upload.ratio
$upload_max = [int]$upload.maxchunkcount
$up_sizes   = @(32768, 65536, 131072, 262144, 524288, 1048576, 7340032)
$down_sizes = @(350, 500, 750, 1000, 1500, 2000, 2500, 3000, 3500, 4000) # 5000,600,7000 not in use.
$sizes = [psObject]::new(@{upload = $up_sizes[($ratio-1)..($up_sizes.Count-1)]; download = $down_sizes})
$size_count = $sizes.upload.Count
$upload_count = [math]::Ceiling($upload_max / $size_count)
$counts  = [psObject]::new(@{upload = $upload_count; download = [int]$download.threadsperurl})
$threads = [psObject]::new(@{upload = [int]$upload.threads; download = [int]$server_config.threadcount * 2})
$length  = [psObject]::new(@{upload = [int]$upload.testlength; download = [int]$download.testlength})
$config  = [psObject]::new(@{client = $client; ignore_servers = $ignore_servers; sizes = $sizes; counts = $counts; threads = $threads; length = $length; upload_max = $upload_count*$size_count})
 
$result =$web.GetAsync("https://www.speedtest.net/speedtest-servers.php").Result
[xml]$servers = $result.Content.ReadAsStringAsync().Result
$srvInfo = [System.Collections.ArrayList]::new()
$earthRadiusKm = 6371.0
$toRadiant1 = [math]::PI/180
$toRadiant2 = [math]::PI/360
foreach($srv in $servers.settings.servers.server) {
    if ($true) {
        if ($ignore_servers -notcontains $srv.id) {
            $dLat = $toRadiant2 * ($pcLat - [float]$srv.lat)
            $dLon = $toRadiant2 * ($pcLon - [float]$srv.lon)
            $sinDLat2 = [math]::Pow([math]::Sin($dLat), 2)
            $sinDLon2 = [math]::Pow([math]::Sin($dLon), 2)
            $a = $sinDLat2 + [math]::Cos($toRadiant1 * $pcLat) * [math]::Cos($toRadiant1 * $srv.lat) * $sinDLon2
            $c = 2 * [math]::Atan2([math]::Sqrt($a), [math]::Sqrt(1.0 - $a))
            $null = $srvInfo.Add([tuple]::Create($earthRadiusKm * $c, $srv.name, $srv.country, $srv.host, $srv.url))
        }
    }
}
$srvInfo.Sort()
 
# ping the closest 9 servers:
$pingTask = foreach ($id in 0..8) {
    [System.Net.NetworkInformation.Ping]::new().SendPingAsync($srvInfo[$id].Item4.split(':')[0], 500)
}
$null = [Threading.Tasks.Task]::WaitAll($pingTask)
 
# get the server with fastest ping-response:
$min = [int]::MaxValue
foreach ($i in 0..($pingTask.Count-1)) {
    $p = $pingTask[$i].result
    if ($p.roundtriptime -lt $min) {
        if ($p.status.value__ -eq 0) {
            $min = $p.roundtriptime
            $id = $i
        }
    }
}
$server = $srvInfo[$id]
 
# show server details:
$enc   = [System.Text.Encoding]
write-host "Server-Details:"
write-host "Country :" $server.Item3
write-host "City    :" $enc::UTF8.GetString($enc::Default.GetBytes($server.item2))
write-host "Hostname:" $server.item4.split(':')[0]
write-host "IP      :" $pingTask[$id].Result.address
write-host "Ping(ms):" $pingTask[$id].Result.RoundtripTime
write-host
 
$sum = 0
$url = $server.Item5
$size = 1000
$jpg = $url.replace("upload.php", "random$($size)x$($size).jpg")
foreach ($i in 1..$repetition) {
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $result =$web.GetAsync($jpg).Result
    $webData = $result.Content.ReadAsStringAsync().Result
    $timer.Stop()
    $sizeMb = $webData.length/1MB
    $speed = 8 * $sizeMb / $timer.Elapsed.TotalSeconds
    $sum += $speed
}
$web.Dispose()
$avg = [math]::Round($sum/$repetition,2)
write-host "Size of Test-File is $($webData.length.ToString('N0')) bytes."
write-host "Number of downloads: $repetition"
Write-Host "Single-thread Internet Download Speed is $avg Mbit/Sec"
