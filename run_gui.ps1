# Servidor HTTP Local para la Interfaz Grafica de Auditoria
# Ejecutar este script desde PowerShell para levantar el panel de administracion web local.

param(
    [int]$Port = 8080
)

$ScriptDir = $PSScriptRoot
$ConfigPath = Join-Path $ScriptDir "config\config.json"
$GuiHtmlPath = Join-Path $ScriptDir "gui\index.html"
$ReportesDir = Join-Path $ScriptDir "reportes"

# Asegurar que existe el archivo de configuracion base
if (-not (Test-Path $ConfigPath)) {
    # Si no existe, crear un config provisional
    $defaultConfig = @{
        webhookUrl = "https://discord.com/api/webhooks/TU_WEBHOOK_AQUI"
        umbralParchesCriticos = 5
        horasAtras = 24
        rutaReportes = $ReportesDir
        rutaLogs = Join-Path $ScriptDir "logs"
    }
    New-Item -ItemType Directory -Path (Split-Path $ConfigPath) -Force | Out-Null
    $defaultConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force
}

# Auto-corregir rutas si el directorio del proyecto cambio
$configObj = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$actualReportes = Join-Path $ScriptDir "reportes"
$actualLogs = Join-Path $ScriptDir "logs"

if ($configObj.rutaReportes -ne $actualReportes -or $configObj.rutaLogs -ne $actualLogs) {
    Write-Host "Detectado cambio de directorio del proyecto. Actualizando rutas en config.json..."
    $configObj.rutaReportes = $actualReportes
    $configObj.rutaLogs = $actualLogs
    $configObj | ConvertTo-Json -Depth 5 | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force
}

$maxTries = 10
$started = $false
$listener = $null
$url = ""

for ($i = 0; $i -lt $maxTries; $i++) {
    $currentPort = $Port + $i
    $url = "http://localhost:$currentPort/"
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add($url)
    
    try {
        $listener.Start()
        $Port = $currentPort
        $started = $true
        break
    }
    catch {
        Write-Host "El puerto $currentPort está ocupado o no está disponible. Intentando con el siguiente..." -ForegroundColor Yellow
        $listener.Close()
        $listener = $null
    }
}

if (-not $started) {
    Write-Error "No se pudo iniciar el servidor HTTP en ningún puerto del rango $Port a $($Port + $maxTries - 1)."
    Exit 1
}

try {
    Write-Host "========================================================="
    Write-Host "  Servidor Web de la GUI iniciado en $url"
    Write-Host "  Abriendo el navegador web..."
    Write-Host "  Presione Ctrl+C en esta consola para detener el servidor."
    Write-Host "========================================================="

    # Abrir el navegador automaticamente
    Start-Process $url

    while ($listener.IsListening) {
        $context = $listener.GetContext()
        
        try {
            $request = $context.Request
            $response = $context.Response

            $path = $request.RawUrl
            $method = $request.HttpMethod

            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $method $path"

            # --- Endpoint: Servir interfaz HTML principal ---
            if ($path -eq "/" -and $method -eq "GET") {
                if (Test-Path $GuiHtmlPath) {
                    $html = Get-Content $GuiHtmlPath -Raw -Encoding UTF8
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                    $response.ContentType = "text/html; charset=utf-8"
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                } else {
                    $response.StatusCode = 404
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes("Error: No se encontro gui/index.html")
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
            }
            # --- Endpoint API: Consultar Estado / Configuracion ---
            elseif ($path -eq "/api/status" -and $method -eq "GET") {
                $configObj = Get-Content $ConfigPath -Raw | ConvertFrom-Json
                $hostname = [System.Net.Dns]::GetHostName()
                $statusData = @{
                    hostname = $hostname
                    config = $configObj
                } | ConvertTo-Json -Depth 5
                
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($statusData)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            # --- Endpoint API: Listar Reportes ---
            elseif ($path -eq "/api/reports" -and $method -eq "GET") {
                $reportsList = @()
                if (Test-Path $ReportesDir) {
                    $files = Get-ChildItem -Path $ReportesDir -Filter "*.html" | Sort-Object LastWriteTime -Descending
                    foreach ($file in $files) {
                        $reportsList += @{
                            name = $file.Name
                            date = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                        }
                    }
                }
                $json = ConvertTo-Json -InputObject $reportsList -Depth 5
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            # --- Endpoint API: Ver un reporte HTML especifico ---
            elseif ($path -like "/api/view-report*" -and $method -eq "GET") {
                $query = $request.Url.Query
                $fileParam = ""
                if ($query -like "*file=*") {
                    $fileParam = ($query -split "file=")[1]
                    $fileParam = [System.Web.HttpUtility]::UrlDecode($fileParam)
                    $fileParam = Split-Path -Leaf $fileParam
                }

                $reportFilePath = Join-Path $ReportesDir $fileParam
                if ($fileParam -ne "" -and (Test-Path $reportFilePath)) {
                    $reportHtml = Get-Content $reportFilePath -Raw -Encoding UTF8
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($reportHtml)
                    $response.ContentType = "text/html; charset=utf-8"
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                } else {
                    $response.StatusCode = 404
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes("Reporte no encontrado o parametro invalido.")
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
            }
            # --- Endpoint API: Guardar Configuracion ---
            elseif ($path -eq "/api/save-config" -and $method -eq "POST") {
                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                $body = $reader.ReadToEnd()
                $newConfig = $body | ConvertFrom-Json

                # Leer config actual para no borrar las rutas
                $currentConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json
                $currentConfig.webhookUrl = $newConfig.webhookUrl
                $currentConfig.umbralParchesCriticos = $newConfig.umbralParchesCriticos
                $currentConfig.horasAtras = $newConfig.horasAtras

                $currentConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force

                $resJson = @{ status = "ok"; message = "Configuracion guardada correctamente." } | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($resJson)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            # --- Endpoint API: Ejecutar Auditoria ---
            elseif ($path -eq "/api/run-audit" -and $method -eq "POST") {
                Write-Host "Ejecutando scripts/main.ps1 desde la GUI..."
                $scriptPath = Join-Path $ScriptDir "scripts\main.ps1"
                
                # Ejecutar y capturar todas las corrientes (output + warnings + errors)
                $outStr = powershell.exe -NonInteractive -ExecutionPolicy Bypass -File "$scriptPath" *>&1 | Out-String

                $status = if ($LASTEXITCODE -eq 0) { "ok" } else { "error" }
                $resJson = @{
                    status = $status
                    output = $outStr
                } | ConvertTo-Json

                $buffer = [System.Text.Encoding]::UTF8.GetBytes($resJson)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            # --- Endpoint API: Ejecutar Instalador (Setup) ---
            elseif ($path -eq "/api/run-setup" -and $method -eq "POST") {
                Write-Host "Ejecutando setup.ps1 desde la GUI con solicitud de Administrador (UAC)..."
                $setupPath = Join-Path $ScriptDir "setup.ps1"
                $tempLog = Join-Path $ScriptDir "logs\setup_temp.log"
                
                if (Test-Path $tempLog) { Remove-Item $tempLog -Force }

                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "powershell.exe"
                $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""Start-Transcript -Path '$tempLog' -Force; Set-Location '$ScriptDir'; & '$setupPath'; Stop-Transcript"""
                $psi.Verb = "RunAs"
                $psi.UseShellExecute = $true

                try {
                    $proc = [System.Diagnostics.Process]::Start($psi)
                    $proc.WaitForExit()
                    
                    $outStr = "Solicitando permisos de Administrador a traves del control de cuentas de usuario (UAC)...`r`n"
                    if (Test-Path $tempLog) {
                        $outStr += Get-Content $tempLog -Raw -Encoding UTF8
                        Remove-Item $tempLog -Force
                    } else {
                        $outStr += "El proceso de instalacion finalizo sin generar registros. Verifica si aprobaste el prompt de UAC."
                    }
                    $status = "ok"
                }
                catch {
                    $outStr = "Error al solicitar permisos de Administrador (UAC denegado): $($_.Exception.Message)"
                    $status = "error"
                }

                $resJson = @{
                    status = $status
                    output = $outStr
                } | ConvertTo-Json

                $buffer = [System.Text.Encoding]::UTF8.GetBytes($resJson)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            # --- Endpoint API: Abrir Carpeta de Reportes en el Explorador ---
            elseif ($path -eq "/api/open-reports-folder" -and $method -eq "POST") {
                Write-Host "Abriendo carpeta de reportes ($ReportesDir) en el Explorador de Windows..."
                try {
                    if (-not (Test-Path $ReportesDir)) {
                        New-Item -ItemType Directory -Path $ReportesDir -Force | Out-Null
                    }
                    Start-Process explorer.exe -ArgumentList "`"$ReportesDir`""
                    $resJson = @{ status = "ok" } | ConvertTo-Json
                }
                catch {
                    $resJson = @{ status = "error"; message = $_.Exception.Message } | ConvertTo-Json
                }
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($resJson)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            # --- Ruta Desconocida ---
            else {
                $response.StatusCode = 404
                $buffer = [System.Text.Encoding]::UTF8.GetBytes("Endpoint no encontrado.")
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }

            $response.Close()
        }
        catch {
            Write-Host "Error al procesar peticion: $($_.Exception.Message)" -ForegroundColor Red
            try { $context.Response.Close() } catch {}
        }
    }
}
catch {
    Write-Host "Error en el servidor HTTP: $($_.Exception.Message)"
}
finally {
    if ($null -ne $listener) {
        try {
            $listener.Stop()
            $listener.Close()
        }
        catch {
            # Ignorar excepciones al cerrar o detener
        }
    }
    Write-Host "Servidor HTTP detenido."
}
