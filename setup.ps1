# Script de Instalacion y Configuracion del Sistema de Auditoria de Windows
# Debe ejecutarse en una consola de PowerShell como Administrador.

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Este script requiere permisos de Administrador local. Por favor, ejecuta PowerShell como Administrador."
    Exit 1
}

$basePath = $PSScriptRoot
Write-Host "Base de proyecto detectada en: $basePath"

# 1. Configurar directivas de ejecucion
$currentPolicy = Get-ExecutionPolicy
if ($currentPolicy -eq 'RemoteSigned' -or $currentPolicy -eq 'Unrestricted' -or $currentPolicy -eq 'Bypass') {
    Write-Host "La directiva de ejecucion actual ya es compatible ($currentPolicy). No se requieren cambios."
} else {
    Write-Host "Configurando ExecutionPolicy a RemoteSigned..."
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
    }
    catch {
        Write-Warning "No se pudo establecer la directiva de ejecucion en LocalMachine: $($_.Exception.Message)"
        Write-Host "Intentando establecer la directiva de ejecucion para el usuario actual..."
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        }
        catch {
            Write-Warning "Tampoco se pudo establecer para el usuario actual: $($_.Exception.Message)"
            Write-Host "El instalador continuara usando '-ExecutionPolicy Bypass' para sus ejecuciones."
        }
    }
}

# 2. Configurar protocolos TLS y gestor de paquetes para instalacion silenciosa
Write-Host "Configurando TLS 1.2 para descargar modulos de PowerShell..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Instalar y confiar en el proveedor NuGet si no esta disponible
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "Instalando proveedor NuGet requerido..."
    Install-PackageProvider -Name NuGet -Force | Out-Null
}

# Confiar en PSGallery
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue

# 3. Validar e instalar PSWindowsUpdate
Write-Host "Verificando el modulo PSWindowsUpdate..."
$module = Get-Module -ListAvailable -Name PSWindowsUpdate
if ($null -eq $module) {
    Write-Host "El modulo PSWindowsUpdate no esta instalado. Iniciando instalacion..."
    try {
        Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -ErrorAction Stop
        Write-Host "Modulo PSWindowsUpdate instalado exitosamente."
    }
    catch {
        Write-Error "No se pudo instalar PSWindowsUpdate de manera automatica: $($_.Exception.Message)"
        Write-Warning "Por favor instalelo manualmente usando: Install-Module PSWindowsUpdate -Force"
    }
} else {
    Write-Host "El modulo PSWindowsUpdate ya se encuentra instalado."
}

# 4. Crear estructura de carpetas si no existe
Write-Host "Creando estructura de directorios del proyecto..."
$carpetas = @("config", "scripts", "reportes", "logs", "tasks")
foreach ($folder in $carpetas) {
    $folderPath = Join-Path $basePath $folder
    if (-not (Test-Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
        Write-Host "Directorio creado: \$folder"
    }
}

# 5. Generar config/config.json dinamico o actualizar rutas si ya existe
Write-Host "Configurando archivo config.json..."
$configTemplatePath = Join-Path $basePath "config\config.json.template"
$configJsonPath = Join-Path $basePath "config\config.json"

if (Test-Path $configJsonPath) {
    $configObj = Get-Content $configJsonPath -Raw | ConvertFrom-Json
    $configObj.rutaReportes = (Join-Path $basePath "reportes")
    $configObj.rutaLogs = (Join-Path $basePath "logs")
    $configObj | ConvertTo-Json -Depth 5 | Out-File -FilePath $configJsonPath -Encoding UTF8 -Force
    Write-Host "Rutas actualizadas en el archivo config.json existente sin alterar los parametros personalizados."
}
elseif (Test-Path $configTemplatePath) {
    $template = Get-Content $configTemplatePath -Raw | ConvertFrom-Json
    $template.rutaReportes = (Join-Path $basePath "reportes")
    $template.rutaLogs = (Join-Path $basePath "logs")
    $template | ConvertTo-Json -Depth 5 | Out-File -FilePath $configJsonPath -Encoding UTF8 -Force
    Write-Host "config.json configurado dinamicamente con las rutas de este equipo a partir de la plantilla."
} else {
    $defaultConfig = @{
        webhookUrl = "https://discord.com/api/webhooks/TU_WEBHOOK_AQUI"
        umbralParchesCriticos = 5
        horasAtras = 24
        rutaReportes = (Join-Path $basePath "reportes")
        rutaLogs = (Join-Path $basePath "logs")
    }
    $defaultConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $configJsonPath -Encoding UTF8 -Force
    Write-Host "config.json por defecto generado."
}

# 6. Registrar la tarea en el Programador de Tareas de Windows
Write-Host "Registrando la Tarea Programada 'AuditoriaWindows'..."
$mainScriptPath = Join-Path $basePath "scripts\main.ps1"

# Accion: Ejecutar PowerShell pasandole la ruta absoluta del orquestador
$accion = New-ScheduledTaskAction -Execute "powershell.exe" `
          -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$mainScriptPath`""

# Disparador: Diario a las 08:00 AM
$trigger = New-ScheduledTaskTrigger -Daily -At "08:00AM"

# Configuraciones del sistema
$settings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable -WakeToRun

try {
    # Registrar la tarea para ejecutarse como SYSTEM con maximos privilegios
    Register-ScheduledTask -TaskName "AuditoriaWindows" `
                           -Action $accion -Trigger $trigger -Settings $settings `
                           -User "SYSTEM" -RunLevel Highest -Force | Out-Null
    Write-Host "Tarea programada 'AuditoriaWindows' registrada exitosamente para ejecutarse como SYSTEM."

    # 7. Exportar la tarea registrada a XML y sanitizarla para Git
    $xmlPath = Join-Path $basePath "tasks\AuditoriaWindows.xml"
    $xmlContent = Export-ScheduledTask -TaskName "AuditoriaWindows"
    
    # Reemplazar la ruta absoluta local por una ruta genérica en el XML exportado
    $escapedPath = [RegEx]::Escape($mainScriptPath)
    $sanitizedXml = $xmlContent -replace $escapedPath, 'C:\Ruta\De\Instalacion\scripts\main.ps1'
    
    # Escribir el XML sanitizado
    $sanitizedXml | Out-File -FilePath $xmlPath -Encoding UTF8 -Force
    Write-Host "Estructura XML de la tarea exportada y sanitizada (sin rutas locales) en: tasks\AuditoriaWindows.xml"
}
catch {
    Write-Error "Error al registrar la tarea programada: $($_.Exception.Message)"
}

# 8. Crear acceso directo en el Escritorio para la GUI
Write-Host "Creando acceso directo en el Escritorio para el Panel de Auditoria..."
try {
    $desktopPath = [System.Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktopPath "Panel de Auditoria.lnk"
    $runGuiPath = Join-Path $basePath "run_gui.ps1"
    
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($shortcutPath)
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$runGuiPath`""
    $Shortcut.WorkingDirectory = $basePath
    $Shortcut.Description = "Iniciar el Panel de Administracion Web de Auditoria de Windows"
    $Shortcut.IconLocation = "shell32.dll,14"
    $Shortcut.Save()
    
    Write-Host "Acceso directo creado exitosamente en el Escritorio: $shortcutPath"
}
catch {
    Write-Warning "No se pudo crear el acceso directo en el Escritorio: $($_.Exception.Message)"
}

Write-Host "Instalacion completada correctamente."
