function New-KTalk-Role {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AuthToken,
        
        [Parameter(Mandatory=$true)]
        [string]$Title,
        
        [Parameter(Mandatory=$true)]
        [string]$Description,
        
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        $Permissions,
        
        [string]$Url = "https://7n1uf25w.ktalk.ru/api/roles"
    )
    
    # Проверка параметров (оставить без изменений)
    if ([string]::IsNullOrEmpty($AuthToken)) {
        Write-Error "Auth token is not specified"
        return $null
    }
    
    if ([string]::IsNullOrEmpty($Title) -or [string]::IsNullOrEmpty($Description)) {
        Write-Error "Role title and description are required"
        return $null
    }
    
    if ($null -eq $Permissions) {
        Write-Error "Permissions list cannot be null"
        return $null
    }
    
    # Подготовка заголовков
    $headers = @{
        "X-Auth-Token" = $AuthToken
        "Content-Type" = "application/json; charset=utf-8"  # Явно указываем кодировку
    }
    
    # Подготовка тела запроса
    $requestBody = @{
        title = $Title
        description = $Description
        permissions = @()
    }
    
    # Преобразование permissions в правильный формат
    if ($Permissions -is [array] -or $Permissions -is [System.Collections.IList]) {
        foreach ($perm in $Permissions) {
            $permissionObj = @{
                productId = $perm.productId
                permissionId = $perm.permissionId
            }
            
            if ($null -ne $perm.PSObject.Properties['disabled']) {
                $permissionObj.disabled = $perm.disabled
            }
            
            $requestBody.permissions += $permissionObj
        }
    }
    
    # КРИТИЧЕСКИЙ МОМЕНТ: Правильное преобразование в JSON с UTF-8
    try {
        # Преобразуем в JSON
        $jsonBody = $requestBody | ConvertTo-Json -Depth 5 -Compress
        
        # Для отладки: показываем что отправляем
        Write-Host "Отправляемые данные (JSON):" -ForegroundColor Cyan
        Write-Host $jsonBody -ForegroundColor Gray
        
        Write-Host "Создаю роль: $Title" -ForegroundColor Cyan
        Write-Host "Описание: $Description" -ForegroundColor Cyan
        Write-Host "Разрешений: $($requestBody.permissions.Count)" -ForegroundColor Cyan
        
        # Выполнение POST запроса
        $response = Invoke-RestMethod -Uri $Url `
            -Method Post `
            -Headers $headers `
            -Body $jsonBody `
            -ErrorAction Stop
        
        Write-Host "Роль успешно создана!" -ForegroundColor Green
        
        $result = New-Object PSObject -Property @{
            Success = $true
            RoleTitle = $Title
            RoleDescription = $Description
            PermissionsCount = $requestBody.permissions.Count
            ApiResponse = $response
        }
        
        return $result
        
    } catch {
        Write-Error "Ошибка при создании роли: $($_.Exception.Message)"
        
        # Детали ошибки
        if ($_.Exception.Response) {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $errorBody = $reader.ReadToEnd()
            Write-Host "Детали ошибки API: $errorBody" -ForegroundColor Red
        }
        
        return $null
    }
}
