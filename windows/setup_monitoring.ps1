Param (
    [Parameter (Mandatory=$false)]
    [string]$server_type,

    [Parameter (Mandatory=$false)]
    [string]$version_1C,

    [Parameter (Mandatory=$false)]
    [string]$cluster_port_1C,

    [Parameter (Mandatory=$false)]
    [string]$RAS_port_1C,
	
    [Parameter (Mandatory=$false)]
    [string]$ClusterFolder_1C,
	
    [Parameter (Mandatory=$false)]
    [string]$share_user,
	
    [Parameter (Mandatory=$false)]
    [string]$logs_folder
)

# ---------- Вспомогательные функции ----------

# Создать новый файл настроек с нужным именем общей папки сбора логов
function New-SettingsFileFromTemplate {
    param(
        [string]$file_old,
        [string]$file_new,
        [string]$logs_folder_old,
        [string]$logs_folder_new,
        [string]$encoding = "UTF8"
    )

    $content_sample = Get-Content -Path $file_old -Raw -Encoding UTF8
    $newContent = $content_sample -replace [regex]::Escape($logs_folder_old), $logs_folder_new
    $file_new_Path = Join-Path $PSScriptRoot $file_new

    if ($encoding -eq "UTF8") {
        New-Item -Path $file_new -ItemType File -Force | Out-Null
        [System.IO.File]::WriteAllText(
            $file_new_Path,
            $newContent,
            (New-Object System.Text.UTF8Encoding($false))
        )
    }else{

        [System.IO.File]::WriteAllText(
            $file_new_Path,
            $newContent,
            (New-Object System.Text.UnicodeEncoding($false, $true))
        )
    }
}

# Полностью остановить и удалить службу (по объекту CimInstance)
function Remove-RasService {
    param([Parameter(Mandatory)][object]$Service)

    $name = $Service.Name

    if ($Service.State -ne 'Stopped') {
        Write-Host "  Останавливаем службу '$name'"
        Stop-Service -Name $name -Force -ErrorAction SilentlyContinue

        # Ждём фактической остановки
        $timeout = 15
        while ($timeout -gt 0) {
            $s = Get-Service -Name $name -ErrorAction SilentlyContinue
            if (-not $s -or $s.Status -eq 'Stopped') { break }
            Start-Sleep -Seconds 1
            $timeout--
        }
    }

    Write-Host "  Удаляем службу '$name'"
    $null = & sc.exe delete "$name" 2>&1

    # Ждём, пока SCM действительно уберёт запись о службе
    $timeout = 15
    while ($timeout -gt 0) {
        if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Seconds 1
        $timeout--
    }
}

# Извлечь версию платформы из PathName вида "...\1cv8\<версия>\bin\ras.exe" (...)
function Get-PlatformVersionFromPath {
    param([string]$Path)
    if ($Path -and $Path -match '\\1cv8\\([^\\]+)\\bin\\ras\.exe') {
        return $Matches[1]
    }
    return $null
}

Write-Host "-------------------------------------------------------------------------------------------------"
Write-Host "Проверяем коррентность заполнения входных параметров скрипта"

if ([string]::IsNullOrEmpty($server_type)) {
    Write-Host "Не задан тип сервера. Укажите в параметрах запуска скрипта: -server_type xxxx"
    Write-Host "Значения типов сервера могут быть следующие (можно указывать несколько через символ _):"
    Write-Host "    1C - на сервере работает только служба сервера 1С."
    Write-Host "    MSSQL - на сервере работает только служба MSSQL"
    Write-Host "    Postgree - на сервере работает только служба Postgree"
    Write-Host "    1C_MSSQL - на сервере работает служба 1C и служба MSSQL"
    Write-Host "    1C_Postgree - на сервере работает служба 1C и служба Postgree"
    Write-Host "    other - на сервере не работают служба 1С и службы СУБД"

    pause
    Exit
}

# ---------- Основной скрипт ----------

if ($server_type -like "*1С*") {
    # Заменяем русский символ "С" на аналогичный латинский
    $server_type="1C"
}

if ($server_type -like "*1C*" -and [string]::IsNullOrEmpty($version_1C)) {
    Write-Host "Не задана версия платформы кластера 1С, к которому будет подключен RAS. Укажите в параметрах запуска скрипта: -version_1C 8.x.xx.xxxx"
    
    pause
    Exit
}

if ($server_type -like "*1C*" -and [string]::IsNullOrEmpty($cluster_port_1C)) {
    $cluster_port_1C="1540"
    Write-Host "Задан стандартный порт 1540 кластера кластера 1С, к которому будет подключен RAS. Если требуется указать другой порт, укажите в параметрах запуска скрипта: -cluster_port_1C хххх"
}

if ($server_type -like "*1C*" -and $cluster_port_1C -ne "1540" -and [string]::IsNullOrEmpty($RAS_port_1C)) {
    Write-Host "Для кластера 1С, к которому будет подключен RAS, задан нестандартный порт. Укажите порт агента RAS, к которому будет обращаться система мониторинга."
    Write-Host "Порт агента RAS по умолчанию 1545"
    
    pause
    Exit
}

if ($server_type -like "*1C*" -and $cluster_port_1C -eq "1540" -and [string]::IsNullOrEmpty($RAS_port_1C)) {
    Write-Host "Задан стандартный порт 1545 агента RAS, к которому будет обращаться система мониторинга. Если требуется указать другой порт, укажите в параметрах запуска скрипта: -RAS_port_1C хххх"
    
    $RAS_port_1C="1545"
}

if ($server_type -like "*1C*" -and [string]::IsNullOrEmpty($ClusterFolder_1C)) {
    $ClusterFolder_1C="C:\Program Files\1cv8\srvinfo"
    Write-Host "Задан стандартный путь директории кластера. Если требуется указать другой путь, укажите в параметрах запуска скрипта: -ClusterFolder_1C хххх"
}

if ([string]::IsNullOrEmpty($share_user)) {
    Write-Host "Не задано имя пользователя, для которого будут открыты сетевые папки с логами"
    
    pause
    Exit
}

New-Item -Path $logs_folder -ItemType Directory -Force | Out-Null

Write-Host "-------------------------------------------------------------------------------------------------"
Write-Host "Создаем сборщики счетчиков Perfmon"

New-SettingsFileFromTemplate -file_old "BIT_monitoring_server_шаблон.xml" -file_new "BIT_monitoring_server.xml" -logs_folder_old "C:\PerfLogs" -logs_folder_new $logs_folder -encoding "Unicode"
logman import BIT_monitoring_server -xml "BIT_monitoring_server.xml"
if ($server_type -like "*1C*" -or $server_type -like "*Postgree*") {
    New-SettingsFileFromTemplate -file_old "BIT_monitoring_prosesses_шаблон.xml" -file_new "BIT_monitoring_prosesses.xml" -logs_folder_old "C:\PerfLogs" -logs_folder_new $logs_folder -encoding "Unicode"
    logman import BIT_monitoring_prosesses -xml "BIT_monitoring_prosesses.xml"
}
if ($server_type -like "*MSSQL*") {
    New-SettingsFileFromTemplate -file_old "BIT_monitoring_MSSQL_шаблон.xml" -file_new "BIT_monitoring_MSSQL.xml" -logs_folder_old "C:\PerfLogs" -logs_folder_new $logs_folder -encoding "Unicode"
    logman import BIT_monitoring_MSSQL -xml "BIT_monitoring_MSSQL.xml"
}


if ($server_type -like "*1C*" -or $server_type -like "*Postgree*") {
    Write-Host "-------------------------------------------------------------------------------------------------"
    Write-Host "Создаем задание по перезапуску сборщика счетчиков процессов раз в 10 минут"

    schtasks.exe /Create /XML "Restart_counter_BIT_monitoring_prosesses.xml" /tn Restart_counter_BIT_monitoring_prosesses /F
}


if ($server_type -like "*1C*" -or $server_type -like "*Postgree*") {
    Write-Host "-------------------------------------------------------------------------------------------------"
    Write-Host "Включаем вывод PID в сборщике счетчиков процессов"
    
    reg add HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\PerfProc\Performance /v ProcessNameFormat /t REG_DWORD /d 2 /f
}


Write-Host "-------------------------------------------------------------------------------------------------"
Write-Host "Добавляем триггер запуска сборщиков счетчиков Perfmon и исправляем действие по запуску счетчиков"

$ScheduledTaskTrigger = New-ScheduledTaskTrigger -AtStartup

$ScheduledTaskAction = New-ScheduledTaskAction -Execute "C:\Windows\system32\rundll32.exe" -Argument "C:\Windows\system32\pla.dll,PlaHost `"BIT_monitoring_server`" `"`$(Arg0)`""
Set-ScheduledTask -TaskName "\Microsoft\Windows\PLA\BIT_monitoring_server" -Action $ScheduledTaskAction -Trigger $ScheduledTaskTrigger

if ($server_type -like "*1C*" -or $server_type -like "*Postgree*") {
    $ScheduledTaskAction = New-ScheduledTaskAction -Execute "C:\Windows\system32\rundll32.exe" -Argument "C:\Windows\system32\pla.dll,PlaHost `"BIT_monitoring_prosesses`" `"`$(Arg0)`""
    Set-ScheduledTask -TaskName "\Microsoft\Windows\PLA\BIT_monitoring_prosesses" -Action $ScheduledTaskAction -Trigger $ScheduledTaskTrigger
}
if ($server_type -like "*MSSQL*") {
    $ScheduledTaskAction = New-ScheduledTaskAction -Execute "C:\Windows\system32\rundll32.exe" -Argument "C:\Windows\system32\pla.dll,PlaHost `"BIT_monitoring_MSSQL`" `"`$(Arg0)`""
    Set-ScheduledTask -TaskName "\Microsoft\Windows\PLA\BIT_monitoring_MSSQL" -Action $ScheduledTaskAction -Trigger $ScheduledTaskTrigger
}


Write-Host "-------------------------------------------------------------------------------------------------"
Write-Host "Запускем сборщики счетчиков Perfmon"

logman.exe start "BIT_monitoring_server"
if ($server_type -like "*1C*" -or $server_type -like "*Postgree*") {
    logman.exe start "BIT_monitoring_prosesses"
}
if ($server_type -like "*MSSQL*") {
    logman.exe start "BIT_monitoring_MSSQL"
}


if ($server_type -like "*1C*") {
    Write-Host "-------------------------------------------------------------------------------------------------"
    Write-Host "Включаем сбор логов тех. журнала 1С"

    New-SettingsFileFromTemplate -file_old "logcfg_шаблон.xml" -file_new "logcfg.xml" -logs_folder_old "C:\BIT_1C_tech_logs" -logs_folder_new "$($logs_folder)\BIT_1C_tech_logs"

    COPY logcfg.xml "C:\Program Files\1cv8\conf"
    COPY logcfg.xml "C:\Program Files\1cv8\$($version_1C)\bin\conf"
}


if ($server_type -like "*1C*") {
    Write-Host "-------------------------------------------------------------------------------------------------"
    
    # ---------- Входные параметры ----------
    $serviceName = "1C:Enterprise 8.3 Remote Server ($($cluster_port_1C))"
    $rasExe      = "C:\Program Files\1cv8\$($version_1C)\bin\ras.exe"
    $binPath     = "`"$rasExe`" cluster --service --port=$($RAS_port_1C) $(hostname):$($cluster_port_1C)"
    $displayName = "1C:Enterprise 8.3 Remote Server ($($cluster_port_1C))"

    if (-not $RAS_port_1C) {
        throw "Не задан параметр RAS_port_1C — невозможно корректно определить/создать службу RAS."
    }


    # Ищем существующие службы
    $portToken   = [regex]::Escape("--port=$RAS_port_1C") + '(\s|$)'
    $serviceByPort = Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue |
        Where-Object {
            $_.PathName -and
            $_.PathName -match 'ras\.exe' -and
            $_.PathName -match $portToken
        } | Select-Object -First 1

    # Логика поиска
    if ($serviceByPort) {
        $currentVersion = Get-PlatformVersionFromPath -Path $serviceByPort.PathName

        if ($currentVersion -eq $version_1C) {
            Write-Host "Служба RAS на порту $RAS_port_1C уже существует: '$($serviceByPort.Name)', версия $currentVersion."

            if ($serviceByPort.State -eq 'Running') {
                Write-Host "  Служба уже запущена."
            }
            else {
                Write-Host "  Запускаем службу"
                Start-Service -Name $serviceByPort.Name
            }
        }
        else {
            Write-Host "Служба RAS на порту $RAS_port_1C найдена ('$($serviceByPort.Name)'), но версия отличается (текущая: $currentVersion, требуется: $version_1C). Пересоздаём..."

            Remove-RasService -Service $serviceByPort

            Write-Host "Регистрируем службу RAS"
            New-Service -Name $serviceName -BinaryPathName $binPath -DisplayName $displayName -StartupType Automatic | Out-Null

            Write-Host "Запускаем службу RAS"
            Start-Service -Name $serviceName
        }
    }
    else {
        Write-Host "Служба RAS на порту $RAS_port_1C не найдена. Регистрируем службу RAS"

        New-Service -Name $serviceName -BinaryPathName $binPath -DisplayName $displayName -StartupType Automatic | Out-Null

        Write-Host "Запускаем службу RAS"
        Start-Service -Name $serviceName
    }
}


if ($server_type -like "*1C*") {
    Write-Host "-------------------------------------------------------------------------------------------------"
    
	Write-Host "Создаем папку $($logs_folder)\BIT_ClusterFoldersSizeLogs для логов размеров директорий кластера"

    New-Item -Path (Join-Path $logs_folder "BIT_ClusterFoldersSizeLogs") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $logs_folder "BIT_ClusterFoldersSizeLogs\logs") -ItemType Directory -Force | Out-Null

	Write-Host "Установите утилиту Git Bash для выполнения скриптов *.sh, в частности, для мониторинга размеров директорий кластере 1С"
    Write-Host "Утилита должна быть установлена в папку C:\Program Files\Git\bin (по умолчанию)"
    pause
    Start-Process "https://git-scm.com/install/windows"
    pause	
	
	Write-Host "Формируем текст файла скрипта SaveClusterFoldersSize.sh для логирования размеров вложенных директорий кластера $($ClusterFolder_1C) в папку $($logs_folder)\BIT_ClusterFoldersSizeLogs"	
	$currentDate = Get-Date;
	$fileNameDate = $currentDate.ToString("yyyy-MM-dd_HHmmss");
	New-Item -Path (Join-Path $logs_folder "\BIT_ClusterFoldersSizeLogs\SaveClusterFoldersSize.sh") -ItemType file -Force
	Clear-Content -Path (Join-Path $logs_folder "\BIT_ClusterFoldersSizeLogs\SaveClusterFoldersSize.sh")
	Add-Content -Path (Join-Path $logs_folder "\BIT_ClusterFoldersSizeLogs\SaveClusterFoldersSize.sh") -Value "#!/bin/bash"
	Add-Content -Path (Join-Path $logs_folder "\BIT_ClusterFoldersSizeLogs\SaveClusterFoldersSize.sh") -Value ""
	Add-Content -Path (Join-Path $logs_folder "\BIT_ClusterFoldersSizeLogs\SaveClusterFoldersSize.sh") -Value 'archiving_date=$(date +''%y%m%d%H'')'
	Add-Content -Path (Join-Path $logs_folder "\BIT_ClusterFoldersSizeLogs\SaveClusterFoldersSize.sh") -Value "du --apparent-size --max-depth=3 `"$($ClusterFolder_1C)`" > $($logs_folder)/BIT_ClusterFoldersSizeLogs/logs/SizeLogs_`${archiving_date}.txt"
	
    Write-Host "Создаем задание для логирования размеров директорий кластера"


    schtasks.exe /Create /XML "BIT_Collecting_sizes_1C_cluster_folders.xml" /tn BIT_Collecting_sizes_1C_cluster_folders /F
}

Write-Host "-------------------------------------------------------------------------------------------------"
Write-Host "Расшариваем папки с логами"

Start-Sleep -Seconds 1
if ($server_type -like "*1C*") {
    Write-Host "Ждем 60 секунд, чтобы начался сбор счетчиков тех. журнала 1С и создалась папка с логами"
    Start-Sleep -Seconds 60
}

net share BIT_monitoring /delete /y 2>$null
net share BIT_monitoring="$($logs_folder)" "/grant:$($share_user),FULL"

Write-Host "Убедитесь, что сетевая папка $($logs_folder) доступна пользователю $($share_user). При необходимости, укажите пользователя в сетевой папке ВРУЧНУЮ"
pause