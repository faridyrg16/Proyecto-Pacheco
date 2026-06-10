param($Patches, $Events, $Config)

try {
    Write-Host "Iniciando generacion de reporte HTML..."

    # Determinar color del semaforo e indicador
    $cantPatches = if ($null -ne $Patches) { $Patches.Count } else { 0 }
    $cantEvents = if ($null -ne $Events) { $Events.Count } else { 0 }

    $colorSemaforo = ""
    $estadoTexto = ""
    $estadoBadgeClass = ""

    if ($cantPatches -eq 0) {
        $colorSemaforo = "#10B981" # Esmeralda / Verde
        $estadoTexto = "SEGURO"
        $estadoBadgeClass = "background-color: rgba(16, 185, 129, 0.15); color: #10B981; border: 1px solid rgba(16, 185, 129, 0.3);"
    }
    elseif ($cantPatches -le 5) {
        $colorSemaforo = "#F59E0B" # Ambar / Amarillo
        $estadoTexto = "ADVERTENCIA"
        $estadoBadgeClass = "background-color: rgba(245, 158, 11, 0.15); color: #F59E0B; border: 1px solid rgba(245, 158, 11, 0.3);"
    }
    else {
        $colorSemaforo = "#ff0000ff" # Rojo / Critico
        $estadoTexto = "VULNERABLE"
        $estadoBadgeClass = "background-color: rgba(239, 68, 68, 0.15); color: #EF4444; border: 1px solid rgba(239, 68, 68, 0.3);"
    }

    $fechaHoy = Get-Date -Format "yyyy-MM-dd"
    $horaHoy = Get-Date -Format "HH:mm:ss"
    $hostname = [System.Net.Dns]::GetHostName()

    # Generar filas de tabla para parches
    $filasParches = ""
    if ($cantPatches -gt 0) {
        foreach ($p in $Patches) {
            $kb = if ($p.KBArticleIDs) { $p.KBArticleIDs -join ", " } else { "N/A" }
            $sizeMB = if ($p.Size) { [Math]::Round($p.Size / 1MB, 2) } else { 0 }
            $sizeText = if ($sizeMB -gt 0) { "${sizeMB} MB" } else { "Desconocido" }
            
            $sevClass = if ($p.MsrcSeverity -eq "Critical") { "color: #EF4444; font-weight: bold;" } else { "color: #F59E0B; font-weight: bold;" }

            $filasParches += @"
            <tr>
                <td style="font-weight: 500; color: #1E293B;">$($p.Title)</td>
                <td style="font-family: monospace; font-size: 13px;">KB$kb</td>
                <td style="$sevClass">$($p.MsrcSeverity)</td>
                <td>$sizeText</td>
            </tr>
"@
        }
    }
    else {
        $filasParches = @"
        <tr>
            <td colspan="4" style="text-align: center; color: #64748B; padding: 30px; font-style: italic;">
                Excelente! No hay actualizaciones criticas ni importantes pendientes en este servidor.
            </td>
        </tr>
"@
    }

    # Generar filas de tabla para eventos
    $filasEventos = ""
    if ($cantEvents -gt 0) {
        foreach ($e in $Events) {
            $filasEventos += @"
            <tr>
                <td style="font-family: monospace; font-size: 13px; font-weight: bold; color: #0F172A; text-align: center;">$($e.EventId)</td>
                <td style="text-align: center; font-weight: bold; color: #EF4444;">$($e.Ocurrencias)</td>
                <td style="color: #475569; font-size: 13px; max-width: 400px; word-wrap: break-word;">$($e.Mensaje)</td>
            </tr>
"@
        }
    }
    else {
        $filasEventos = @"
        <tr>
            <td colspan="3" style="text-align: center; color: #64748B; padding: 30px; font-style: italic;">
                Sin incidentes graves. No se detectaron eventos criticos ni de error en las ultimas 24 horas.
            </td>
        </tr>
"@
    }

    # Generar HTML completo con diseño
    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reporte de Auditoria de Seguridad - $hostname</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --primary: #3B82F6;
            --success: #10b932ff;
            --warning: #F59E0B;
            --danger: #e72a2aff;
            --bg-body: #F8FAFC;
            --card-bg: #FFFFFF;
            --text-main: #0F172A;
            --text-muted: #64748B;
            --border-color: #E2E8F0;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background-color: var(--bg-body);
            color: var(--text-main);
            line-height: 1.5;
            padding: 40px 20px;
        }

        .container {
            max-width: 1000px;
            margin: 0 auto;
        }

        /* Cabecera */
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 2px solid var(--border-color);
            padding-bottom: 24px;
            margin-bottom: 32px;
        }

        .header-title h1 {
            font-size: 26px;
            font-weight: 700;
            color: #1E293B;
            letter-spacing: -0.5px;
        }

        .header-title p {
            font-size: 14px;
            color: var(--text-muted);
            margin-top: 4px;
        }

        .badge-status {
            padding: 8px 16px;
            border-radius: 9999px;
            font-size: 13px;
            font-weight: 700;
            letter-spacing: 0.5px;
            text-transform: uppercase;
        }

        /* Resumen en Tarjetas */
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 20px;
            margin-bottom: 32px;
        }

        .card {
            background-color: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 12px;
            padding: 20px;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05), 0 2px 4px -2px rgba(0, 0, 0, 0.05);
            transition: transform 0.2s, box-shadow 0.2s;
        }

        .card:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.05), 0 4px 6px -4px rgba(0, 0, 0, 0.05);
        }

        .card-label {
            font-size: 12px;
            font-weight: 600;
            color: var(--text-muted);
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 8px;
        }

        .card-value {
            font-size: 28px;
            font-weight: 700;
            color: #1E293B;
        }

        .card-desc {
            font-size: 12px;
            color: var(--text-muted);
            margin-top: 4px;
        }

        /* Secciones y Tablas */
        .section-title {
            font-size: 18px;
            font-weight: 600;
            color: #1E293B;
            margin-bottom: 16px;
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .table-container {
            background-color: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);
            margin-bottom: 32px;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            text-align: left;
        }

        th {
            background-color: #F8FAFC;
            color: #475569;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            padding: 14px 20px;
            border-bottom: 1px solid var(--border-color);
        }

        td {
            padding: 14px 20px;
            border-bottom: 1px solid #F1F5F9;
            font-size: 14px;
            color: #334155;
            vertical-align: middle;
        }

        tr:last-child td {
            border-bottom: none;
        }

        tr:hover td {
            background-color: #F8FAFC;
        }

        /* Footer */
        .footer {
            text-align: center;
            font-size: 12px;
            color: var(--text-muted);
            margin-top: 48px;
            border-top: 1px solid var(--border-color);
            padding-top: 24px;
        }

        .indicator-pill {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 6px;
        }
    </style>
</head>
<body>

<div class="container">
    <!-- Header -->
    <header class="header">
        <div class="header-title">
            <h1>Auditoria de Seguridad Automatizada</h1>
            <p>Servidor: <strong>$hostname</strong> &bull; Generado el $fechaHoy a las $horaHoy</p>
        </div>
        <div class="badge-status" style="$estadoBadgeClass">
            <span class="indicator-pill" style="background-color: $colorSemaforo;"></span>$estadoTexto
        </div>
    </header>

    <!-- Resumen -->
    <div class="summary-grid">
        <div class="card" style="border-left: 4px solid var(--primary);">
            <div class="card-label">Identificador Servidor</div>
            <div class="card-value" style="font-size: 20px; padding: 5px 0;">$hostname</div>
            <div class="card-desc">Nombre de maquina de auditoria</div>
        </div>
        <div class="card" style="border-left: 4px solid $colorSemaforo;">
            <div class="card-label">Parches Criticos/Imp.</div>
            <div class="card-value">$cantPatches</div>
            <div class="card-desc">Actualizaciones pendientes detectadas</div>
        </div>
        <div class="card" style="border-left: 4px solid #e45d5dff;">
            <div class="card-label">Tipos de Error (Logs)</div>
            <div class="card-value">$cantEvents</div>
            <div class="card-desc">Eventos Criticos/Error (ultimas 24h)</div>
        </div>
    </div>

    <!-- Parches Pendientes -->
    <h2 class="section-title">Parches de Seguridad Pendientes (Critical / Important)</h2>
    <div class="table-container">
        <table>
            <thead>
                <tr>
                    <th style="width: 50%;">Titulo de Actualizacion</th>
                    <th style="width: 15%;">Articulos KB</th>
                    <th style="width: 20%;">Severidad MSRC</th>
                    <th style="width: 15%;">Tamano</th>
                </tr>
            </thead>
            <tbody>
                $filasParches
            </tbody>
        </table>
    </div>

    <!-- Logs Criticos -->
    <h2 class="section-title">Resumen de Eventos Criticos y Errores (Ultimas 24 Horas)</h2>
    <div class="table-container">
        <table>
            <thead>
                <tr>
                    <th style="width: 15%; text-align: center;">ID Evento</th>
                    <th style="width: 15%; text-align: center;">Ocurrencias</th>
                    <th style="width: 70%;">Mensaje de la Primera Ocurrencia</th>
                </tr>
            </thead>
            <tbody>
                $filasEventos
            </tbody>
        </table>
    </div>

    <!-- Footer -->
    <footer class="footer">
        <p>Sistema de Gestion de Parches y Auditoria de Seguridad Automatizada en Windows &bull; DevOps - Sesion 30</p>
        <p style="margin-top: 4px;">Ejecutado de forma autonoma mediante el Programador de Tareas de Windows</p>
    </footer>
</div>

</body>
</html>
"@

    # Generar ruta de salida
    $rutaReportes = if ($null -ne $Config.rutaReportes) { $Config.rutaReportes } else { ".\reportes" }
    
    # Crear carpeta si no existe
    if (-not (Test-Path $rutaReportes)) {
        New-Item -ItemType Directory -Path $rutaReportes -Force | Out-Null
    }

    $rutaSalida = Join-Path $rutaReportes "${fechaHoy}_reporte.html"
    $html | Out-File -FilePath $rutaSalida -Encoding UTF8 -Force

    Write-Host "Reporte HTML generado exitosamente en: $rutaSalida"
    return $rutaSalida
}
catch {
    Write-Warning "Error al generar el reporte HTML: $($_.Exception.Message)"
    throw $_
}
