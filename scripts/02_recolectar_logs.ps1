param($Config)

try {
    Write-Host "Iniciando recoleccion de logs del Event Viewer (System/Security)..."
    $horas = if ($null -ne $Config.horasAtras) { $Config.horasAtras } else { 24 }
    $desde = (Get-Date).AddHours(-$horas)

    # Filtro para canales System y Security
    $filtro = @{
        LogName   = @('System', 'Security')
        Level     = @(1, 2)          # 1=Critical, 2=Error
        StartTime = $desde
    }

    # Get-WinEvent lanza excepcion si no encuentra eventos que coincidan.
    $eventos = @()
    try {
        $eventos = Get-WinEvent -FilterHashtable $filtro -MaxEvents 500 -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Message -like "*No events were found*" -or $_.Exception.Message -like "*No se encontraron eventos*") {
            Write-Host "No se encontraron eventos de Error o Criticos en las ultimas $horas horas."
            return @()
        }
        else {
            throw $_
        }
    }

    if ($null -eq $eventos -or $eventos.Count -eq 0) {
        Write-Host "No se encontraron eventos criticos/error."
        return @()
    }

    # Agrupar por EventId para evitar duplicados masivos y resumir
    $agrupados = $eventos | Group-Object Id | Sort-Object Count -Descending |
        Select-Object @{N='EventId';E={$_.Name}},
                      @{N='Ocurrencias';E={$_.Count}},
                      @{N='Mensaje';E={
                          $msg = $_.Group[0].Message
                          if ($null -eq $msg -or $msg.Trim() -eq "") {
                              "Sin detalle de mensaje disponible."
                          } else {
                              $cleanMsg = $msg -replace "[\r\n]+", " "
                              $cleanMsg.Substring(0, [Math]::Min(120, $cleanMsg.Length))
                          }
                      }}

    Write-Host "Recoleccion completada. Se encontraron $($eventos.Count) eventos totales agrupados en $($agrupados.Count) tipos."
    return $agrupados
}
catch {
    Write-Warning "Error al recolectar logs: $($_.Exception.Message)"
    return @()
}
