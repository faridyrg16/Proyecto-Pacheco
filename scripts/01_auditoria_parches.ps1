param($Config)

try {
    Write-Host "Iniciando auditoria de parches con PSWindowsUpdate..."
    Import-Module PSWindowsUpdate -ErrorAction Stop

    # Buscar actualizaciones pendientes (sin instalar)
    $todasLasActualizaciones = Get-WUList -MicrosoftUpdate -ErrorAction Stop

    if ($null -eq $todasLasActualizaciones) {
        Write-Host "No se encontraron actualizaciones pendientes en el sistema."
        return @()
    }

    # Filtrar solo Critical e Important
    $criticas = $todasLasActualizaciones | Where-Object {
        $_.MsrcSeverity -in @("Critical", "Important")
    }

    Write-Host "Auditoria completada. Se encontraron $($criticas.Count) parches criticos/importantes."
    return $criticas | Select-Object Title, KBArticleIDs, MsrcSeverity, Size
}
catch {
    $serviceStatus = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $statusText = if ($null -ne $serviceStatus) { $serviceStatus.Status } else { "No encontrado" }
    $startType = if ($null -ne $serviceStatus) { $serviceStatus.StartType } else { "N/A" }
    
    Write-Warning "Error al auditar parches: $($_.Exception.Message) (Servicio wuauserv: Estado=$statusText, TipoInicio=$startType)"
    return @()   # Retorna array vacio para no romper el flujo
}
