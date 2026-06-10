param($Config, $Patches, $Events, $Estado, $Detalle = "")

try {
    Write-Host "Iniciando envio de alerta webhook ($Estado)..."

    # Verificar si la URL del webhook esta configurada y no es un placeholder
    if ($null -eq $Config.webhookUrl -or $Config.webhookUrl -eq "" -or $Config.webhookUrl -like "*TU_WEBHOOK_AQUI*") {
        Write-Warning "Webhook URL no configurada o contiene el placeholder de ejemplo. Saltando envio de webhook."
        
        # Guardar en log de todas formas
        $rutaLogs = if ($null -ne $Config.rutaLogs) { $Config.rutaLogs } else { ".\logs" }
        if (-not (Test-Path $rutaLogs)) { New-Item -ItemType Directory -Path $rutaLogs -Force | Out-Null }
        $logFallo = Join-Path $rutaLogs "webhook_warning.log"
        Add-Content -Path $logFallo -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Advertencia: Webhook no configurado. Estado: $Estado. Patches: $(if ($Patches) { $Patches.Count } else { 0 }), Errores: $(if ($Events) { $Events.Count } else { 0 })"
        return
    }

    $hostname = [System.Net.Dns]::GetHostName()
    $cantPatches = if ($null -ne $Patches) { $Patches.Count } else { 0 }
    $cantEvents = if ($null -ne $Events) { $Events.Count } else { 0 }

    # Colores decimales de Discord (Verde: 3066993, Rojo: 15158332)
    $color = if ($Estado -eq "OK") { 3066993 } else { 15158332 }
    $emoji = if ($Estado -eq "OK") { "[OK]" } else { "[ERROR]" }

    # Construir campos dinamicos
    $fields = @(
        @{ name = "Servidor"; value = $hostname; inline = $true },
        @{ name = "Estado General"; value = if ($Estado -eq "OK") { "Exitoso" } else { "Fallo en Auditoria" }; inline = $true }
    )

    if ($Estado -eq "OK") {
        $fields += @{ name = "Parches Pendientes"; value = "$cantPatches criticos/importantes"; inline = $true }
        $fields += @{ name = "Eventos de Error"; value = "$cantEvents tipos detectados"; inline = $true }
    } else {
        $fields += @{ name = "Detalles del Error"; value = if ($Detalle) { $Detalle } else { "Ocurrio una excepcion inesperada durante la ejecucion del script." }; inline = $false }
    }

    # Estructura del Payload para Discord
    $payloadObj = @{
        embeds = @(@{
            title       = "$emoji Auditoria de Seguridad de Windows"
            color       = $color
            description = if ($Estado -eq "OK") { "El reporte diario de parches y eventos de logs se ha generado correctamente." } else { "Se ha detectado una falla critica al ejecutar el proceso de auditoria." }
            fields      = $fields
            footer      = @{ text = "Fecha ejecucion: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" }
        })
    }

    $payload = $payloadObj | ConvertTo-Json -Depth 5

    # Intentos de envio con espera exponencial
    $intentos = 0
    $exito = $false
    $maxIntentos = 3

    while (-not $exito -and $intentos -lt $maxIntentos) {
        try {
            Write-Host "Enviando POST a webhook (intento $($intentos + 1))..."
            $response = Invoke-RestMethod -Uri $Config.webhookUrl -Method POST -Body $payload -ContentType "application/json" -ErrorAction Stop
            $exito = $true
            Write-Host "Webhook enviado exitosamente."
        }
        catch {
            $intentos++
            $delay = [Math]::Pow(2, $intentos) # 2s, 4s, 8s
            Write-Warning "Error al enviar webhook (intento $intentos de $maxIntentos): $($_.Exception.Message)"
            if ($intentos -lt $maxIntentos) {
                Write-Host "Reintentando en $delay segundos..."
                Start-Sleep -Seconds $delay
            }
        }
    }

    if (-not $exito) {
        $rutaLogs = if ($null -ne $Config.rutaLogs) { $Config.rutaLogs } else { ".\logs" }
        if (-not (Test-Path $rutaLogs)) { New-Item -ItemType Directory -Path $rutaLogs -Force | Out-Null }
        $errorLogPath = Join-Path $rutaLogs "error.log"
        Add-Content -Path $errorLogPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR: Fallo al enviar alerta despues de $maxIntentos intentos. Error original: $Detalle"
        throw "No se pudo establecer comunicacion con el Webhook despues de $maxIntentos reintentos."
    }
}
catch {
    Write-Warning "Excepcion critica en 04_enviar_alerta: $($_.Exception.Message)"
    throw $_
}
