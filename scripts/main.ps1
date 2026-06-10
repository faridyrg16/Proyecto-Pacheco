# Orquestador Principal del Sistema de Auditoria de Windows
$ScriptDir = $PSScriptRoot
$ProjectRoot = Split-Path -Path $ScriptDir -Parent

$ConfigPath = Join-Path $ProjectRoot "config\config.json"

if (-not (Test-Path $ConfigPath)) {
    Write-Error "No se encontro el archivo de configuracion en $ConfigPath"
    Exit 1
}

# Cargar configuracion
$config = Get-Content $ConfigPath | ConvertFrom-Json

# Iniciar log de ejecucion con nombre indexado secuencialmente por dia
$fechaHoy = Get-Date -Format 'yyyy-MM-dd'
$logFolder = $config.rutaLogs
if (-not (Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
}

$index = 1
while (Test-Path (Join-Path $logFolder "ejecucion_${fechaHoy}_${index}.log")) {
    $index++
}
$logPath = Join-Path $logFolder "ejecucion_${fechaHoy}_${index}.log"

Start-Transcript -Path $logPath -Append

try {
    Write-Host "========================================================="
    Write-Host "INICIANDO PROCESO DE AUDITORIA AUTOMATIZADA: $(Get-Date)"
    Write-Host "========================================================="

    # Rutas absolutas a los modulos
    $scriptPatches  = Join-Path $ScriptDir "01_auditoria_parches.ps1"
    $scriptLogs     = Join-Path $ScriptDir "02_recolectar_logs.ps1"
    $scriptReport   = Join-Path $ScriptDir "03_generar_reporte.ps1"
    $scriptAlerta   = Join-Path $ScriptDir "04_enviar_alerta.ps1"

    # Llamar modulos en orden y pasar datos entre ellos
    $patches  = & $scriptPatches -Config $config
    $events   = & $scriptLogs    -Config $config
    $rutaHTML = & $scriptReport  -Patches $patches -Events $events -Config $config
    
    # Enviar alerta Webhook
    & $scriptAlerta -Patches $patches -Events $events -Config $config -Estado "OK"

    Write-Host "Proceso de auditoria finalizado exitosamente."
}
catch {
    Write-Host "FALLO CRITICO EN LA EJECUCION: $($_.Exception.Message)"
    
    # Intentar notificar el error via webhook
    $scriptAlerta = Join-Path $ScriptDir "04_enviar_alerta.ps1"
    try {
        & $scriptAlerta -Config $config -Estado "ERROR" -Detalle $_.Exception.Message
    }
    catch {
        Write-Warning "No se pudo enviar la alerta del fallo critico: $($_.Exception.Message)"
    }
    
    # Escribir el error detallado en error.log
    $errorLogPath = Join-Path $config.rutaLogs "error.log"
    Add-Content -Path $errorLogPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - FALLO CRITICO EN ORQUESTADOR: $($_.Exception.ToString())"
    
    Stop-Transcript
    Exit 1
}

Stop-Transcript
