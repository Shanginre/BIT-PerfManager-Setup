Param (
    [Parameter (Mandatory=$false)]
    [string]$server_type,

    [Parameter (Mandatory=$false)]
    [string]$1C_version,

    [Parameter (Mandatory=$false)]
    [string]$1C_cluster_port,

    [Parameter (Mandatory=$false)]
    [string]$1C_RAS_port,
	
    [Parameter (Mandatory=$false)]
    [string]$1C_ClusterFolder,
	
    [Parameter (Mandatory=$false)]
    [string]$share_user
)


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

if ($server_type -like "*1С*") {
    # Заменяем русский символ "С" на аналогичный латинский
    $server_type="1C"
}

if ($server_type -like "*1C*" -and [string]::IsNullOrEmpty($1C_version)) {
    Write-Host "Не задана версия платформы кластера 1С, к которому будет подключен RAS. Укажите в параметрах запуска скрипта: -1C_version 8.x.xx.xxxx"
    
    pause
    Exit
}

if ($server_type -like "*1C*" -and [string]::IsNullOrEmpty($1C_cluster_port)) {
    $1C_cluster_port="1540"
    Write-Host "Задан стандартный порт 1540 кластера кластера 1С, к которому будет подключен RAS. Если требуется указать другой порт, укажите в параметрах запуска скрипта: -1C_cluster_port хххх"
}

if ($server_type -like "*1C*" -and $1C_cluster_port -ne "1540" -and [string]::IsNullOrEmpty($1C_RAS_port)) {
    Write-Host "Для кластера 1С, к которому будет подключен RAS, задан нестандартный порт. Укажите порт агента RAS, к которому будет обращаться система мониторинга."
    Write-Host "Порт агента RAS по умолчанию 1545"
    
    pause
    Exit
}

if ($server_type -like "*1C*" -and $1C_cluster_port -eq "1540" -and [string]::IsNullOrEmpty($1C_RAS_port)) {
    Write-Host "Задан стандартный порт 1545 агента RAS, к которому будет обращаться система мониторинга. Если требуется указать другой порт, укажите в параметрах запуска скрипта: -1C_RAS_port хххх"
    
    $1C_RAS_port="1545"
}

if ($server_type -like "*1C*" -and [string]::IsNullOrEmpty($1C_ClusterFolder)) {
    $1C_ClusterFolder="C:\Program Files\1cv8\srvinfo"
    Write-Host "Задан стандартный путь директории кластера. Если требуется указать другой путь, укажите в параметрах запуска скрипта: -1C_ClusterFolder хххх"
}

if ([string]::IsNullOrEmpty($share_user)) {
    Write-Host "Не задано имя пользователя, для которого будут открыты сетевые папки с логами"
    
    pause
    Exit
}


Write-Host "-------------------------------------------------------------------------------------------------"
Write-Host "Создаем сборщики счетчиков Perfmon"

logman import BIT_monitoring_server -xml "BIT_monitoring_server.xml"
if ($server_type -like "*1C*" -or $server_type -like "*Postgree*") {
    logman import BIT_monitoring_prosesses -xml "BIT_monitoring_prosesses.xml"
}
if ($server_type -like "*MSSQL*") {
    logman import BIT_monitoring_MSSQL -xml "BIT_monitoring_MSSQL.xml"
}


if ($server_type -like "*1C*" -or $server_type -like "*Postgree*") {
    Write-Host "-------------------------------------------------------------------------------------------------"
    Write-Host "Создаем задание по перезапуску сборщика счетчиков процессов раз в 10 минут"

    schtasks.exe /Create /XML "Restart_counter_BIT_monitoring_prosesses.xml" /tn Restart_counter_BIT_monitoring_prosesses
}


if ($server_type -like "*1C*" -or $server_type -like "*Postgree*") {
    Write-Host "-------------------------------------------------------------------------------------------------"
    Write-Host "Включаем вывод PID в сборщике счетчиков процессов"
    
    reg add HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\PerfProc\Performance /v ProcessNameFormat /t REG_DWORD /d 2
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

    COPY logcfg.xml "C:\Program Files\1cv8\conf"
}


if ($server_type -like "*1C*") {
    Write-Host "-------------------------------------------------------------------------------------------------"
    
	Write-Host "Регистрируем службу RAS"   
    New-Service -Name "1C:Enterprise 8.3 Remote Server ($($1C_cluster_port))" -BinaryPathName "`"C:\Program Files\1cv8\$($1C_version)\bin\ras.exe`" cluster --service --port=$($1C_RAS_port) $(hostname):$($1C_cluster_port)" -DisplayName "1C:Enterprise 8.3 Remote Server ($($1C_cluster_port))" -StartupType Automatic
    
    Write-Host "Запускаем службу RAS"
    Start-Service -Name "1C:Enterprise 8.3 Remote Server ($($1C_cluster_port))"
}

if ($server_type -like "*1C*") {
    #Write-Host "-------------------------------------------------------------------------------------------------"
    
	#Write-Host "Создаем папку C:\BIT_ClusterFoldersSizeLogs для логов размеров директорий кластера"   
	#New-Item -Path "C:\BIT_ClusterFoldersSizeLogs" -ItemType Directory
	#New-Item -Path "C:\BIT_ClusterFoldersSizeLogs\logs" -ItemType Directory

	#Write-Host "Распаковываем архив PortableGit.zip в папку C:\BIT_ClusterFoldersSizeLogs с утилитой Git Bash для выполнения скриптов *.sh"	
	#Expand-Archive -LiteralPath 'PortableGit.zip' -DestinationPath C:\BIT_ClusterFoldersSizeLogs
	
	#Write-Host "Формируем текст файла скрипта SaveClusterFoldersSize.sh для логирования размеров вложенных директорий кластера $($1C_ClusterFolder) в папку C:\BIT_ClusterFoldersSizeLogs"	
	#$currentDate = Get-Date;
	#$fileNameDate = $currentDate.ToString("yyyy-MM-dd_HHmmss");
	#New-Item -Path "C:\BIT_ClusterFoldersSizeLogs\SaveClusterFoldersSize.sh" -ItemType file
	#Clear-Content -Path "C:\BIT_ClusterFoldersSizeLogs\SaveClusterFoldersSize.sh"
	#Add-Content -Path "C:\BIT_ClusterFoldersSizeLogs\SaveClusterFoldersSize.sh" -Value "#!/bin/bash"
	#Add-Content -Path "C:\BIT_ClusterFoldersSizeLogs\SaveClusterFoldersSize.sh" -Value ""
	#Add-Content -Path "C:\BIT_ClusterFoldersSizeLogs\SaveClusterFoldersSize.sh" -Value 'archiving_date=$(date +''%y%m%d%H'')'
	#Add-Content -Path "C:\BIT_ClusterFoldersSizeLogs\SaveClusterFoldersSize.sh" -Value "du --apparent-size --max-depth=3 `"$($1C_ClusterFolder)`" > C:/BIT_ClusterFoldersSizeLogs/logs/SizeLogs_`${archiving_date}.txt"
	
    #Write-Host "Создаем задание для логирования размеров директорий кластера"
    #schtasks.exe /Create /XML "BIT_Collecting_sizes_1C_cluster_folders.xml" /tn BIT_Collecting_sizes_1C_cluster_folders
}

Write-Host "-------------------------------------------------------------------------------------------------"
Write-Host "Расшариваем папки с логами"

Start-Sleep -Seconds 1
if ($server_type -like "*1C*") {
    Write-Host "Ждем 60 секунд, чтобы начался сбор счетчиков тех. журнала 1С и создалась папка с логами"
    Start-Sleep -Seconds 60
}

net share BIT_monitoring_server="C:\PerfLogs\Admin\BIT_monitoring_server" "/grant:$($share_user),FULL"
if ($server_type -like "*1C*" -or $server_type -like "*Postgree*") {
    net share BIT_monitoring_prosesses="C:\PerfLogs\Admin\BIT_monitoring_prosesses" "/grant:$($share_user),FULL"
}
if ($server_type -like "*MSSQL*") {
    net share BIT_monitoring_MSSQL="C:\PerfLogs\Admin\BIT_monitoring_MSSQL" "/grant:$($share_user),FULL"
}
if ($server_type -like "*1C*") {
    net share 1c_logs_BIT_monitoring="C:\1c_logs_BIT_monitoring" "/grant:$($share_user),FULL"
	#net share BIT_ClusterFoldersSizeLogs="C:\BIT_ClusterFoldersSizeLogs\logs" "/grant:$($share_user),FULL"
}