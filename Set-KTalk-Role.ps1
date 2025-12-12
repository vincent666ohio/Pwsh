function Set-KTalk-Role {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AuthToken,
        
        [Parameter(Mandatory=$true)]
        [string]$RoleId,
        
        [Parameter(Mandatory=$true)]
        [string]$TemplatePath,
        
        [string]$NewTitle,
        
        [string]$NewDescription,
        
        [switch]$KeepExistingPermissions,
        
        [string]$BaseUrl = "https://7n1uf25w.ktalk.ru"
    )
    
    Write-Host "Обновляю роль с ID: $RoleId" -ForegroundColor Cyan
    Write-Host "Использую шаблон: $TemplatePath" -ForegroundColor Gray
    
    # 1. Загружаем шаблон
    $template = Import-KTalk-RoleTemplate -Path $TemplatePath
    if ($null -eq $template) {
        Write-Error "Не удалось загрузить шаблон из $TemplatePath"
        return $null
    }
    
    # 2. Получаем текущую роль для проверки существования
    try {
        Write-Host "Проверяю существование роли..." -ForegroundColor Yellow
        $currentRoles = Get-KTalk-Roles -AuthToken $AuthToken -ErrorAction Stop
        $existingRole = $currentRoles | Where-Object { $_.RoleId -eq $RoleId }
        
        if ($null -eq $existingRole) {
            Write-Error "Роль с ID '$RoleId' не найдена"
            Write-Host "Доступные роли:" -ForegroundColor Yellow
            $currentRoles | Select-Object RoleId, Title | Format-Table -AutoSize
            return $null
        }
        
        Write-Host "Найдена роль: $($existingRole.Title) (Изменяемая: $($existingRole.Editable))" -ForegroundColor Green
        
    } catch {
        Write-Warning "Не удалось проверить существование роли: $_"
        Write-Host "Продолжаю в любом случае..." -ForegroundColor Yellow
    }
    
    # 3. Определяем новые значения названия и описания
    $roleTitle = if (-not [string]::IsNullOrEmpty($NewTitle)) {
        $NewTitle
    } elseif ($template.Title -ne "ROLE_TITLE" -and $template.Title -ne "НАЗВАНИЕ_РОЛИ") {
        $template.Title
    } else {
        # Если в шаблоне дефолтное название, оставляем текущее
        if ($existingRole) {
            $existingRole.Title
        } else {
            Read-Host "Введите новое название роли"
        }
    }
    
    $roleDescription = if (-not [string]::IsNullOrEmpty($NewDescription)) {
        $NewDescription
    } elseif ($template.Description -ne "ROLE_DESCRIPTION" -and $template.Description -ne "ОПИСАНИЕ_РОЛИ") {
        $template.Description
    } else {
        # Если в шаблоне дефолтное описание, оставляем текущее
        if ($existingRole) {
            $existingRole.Description
        } else {
            Read-Host "Введите новое описание роли"
        }
    }
    
    # 4. Определяем разрешения для обновления
    $permissionsToSet = if ($KeepExistingPermissions -and $existingRole) {
        Write-Host "Сохраняю существующие разрешения роли" -ForegroundColor Yellow
        
        # Здесь нужно получить текущие разрешения роли
        # Для этого может потребоваться дополнительный API запрос
        # Временно используем разрешения из шаблона
        Write-Warning "Не удается автоматически получить текущие разрешения. Использую разрешения из шаблона."
        $template.Permissions
    } else {
        $template.Permissions
    }
    
    # 5. Подготавливаем тело запроса с правильной кодировкой
    $requestBody = @{
        title = $roleTitle
        description = $roleDescription
        permissions = @()
    }
    
    foreach ($perm in $permissionsToSet) {
        $permissionObj = @{
            productId = $perm.productId
            permissionId = $perm.permissionId
        }
        
        # Добавляем disabled если есть
        if ($null -ne $perm.PSObject.Properties['disabled']) {
            $permissionObj.disabled = $perm.disabled
        }
        
        $requestBody.permissions += $permissionObj
    }
    
    # 6. Определяем URL для обновления
    $url = "$BaseUrl/api/roles/$RoleId"
    
    Write-Host "`nСводка обновления:" -ForegroundColor Cyan
    Write-Host "ID роли: $RoleId" -ForegroundColor Yellow
    Write-Host "Новое название: $roleTitle" -ForegroundColor Yellow
    Write-Host "Новое описание: $roleDescription" -ForegroundColor Yellow
    Write-Host "Разрешений: $($requestBody.permissions.Count)" -ForegroundColor Green
    Write-Host "API Endpoint: $url" -ForegroundColor Gray
    
    # 7. КОНВЕРТАЦИЯ В JSON С ПРАВИЛЬНОЙ КОДИРОВКОЙ
    try {
        $jsonBody = $requestBody | ConvertTo-Json -Depth 5 -Compress
        
        # Для отладки выводим JSON
        Write-Host "`nJSON для отправки:" -ForegroundColor DarkGray
        Write-Host $jsonBody -ForegroundColor Gray
        
        # Подготавливаем заголовки
        $headers = @{
            "X-Auth-Token" = $AuthToken
            "Content-Type" = "application/json; charset=utf-8"
        }
        
        # 8. Пытаемся отправить запрос разными методами
        $result = $null
        
        # Сначала пробуем PUT (стандарт для обновления)
        try {
            Write-Host "`nПробую PUT запрос..." -ForegroundColor Cyan
            $response = Invoke-RestMethod -Uri $url `
                -Method Put `
                -Headers $headers `
                -Body $jsonBody `
                -ErrorAction Stop
            
            Write-Host "✓ Роль успешно обновлена через PUT!" -ForegroundColor Green
            $result = [PSCustomObject]@{
                Success = $true
                Method = "PUT"
                RoleId = $RoleId
                RoleTitle = $roleTitle
                ApiResponse = $response
            }
            
        } catch {
            Write-Host "PUT не сработал: $($_.Exception.Message)" -ForegroundColor Yellow
            
            # Пробуем POST (если API использует POST для обновления)
            try {
                Write-Host "`nПробую POST запрос..." -ForegroundColor Cyan
                $response = Invoke-RestMethod -Uri $url `
                    -Method Post `
                    -Headers $headers `
                    -Body $jsonBody `
                    -ErrorAction Stop
                
                Write-Host "✓ Роль успешно обновлена через POST!" -ForegroundColor Green
                $result = [PSCustomObject]@{
                    Success = $true
                    Method = "POST"
                    RoleId = $RoleId
                    RoleTitle = $roleTitle
                    ApiResponse = $response
                }
                
            } catch {
                Write-Host "POST также не сработал: $($_.Exception.Message)" -ForegroundColor Red
                
                # Пробуем PATCH (для частичного обновления)
                try {
                    Write-Host "`nПробую PATCH запрос..." -ForegroundColor Cyan
                    $response = Invoke-RestMethod -Uri $url `
                        -Method Patch `
                        -Headers $headers `
                        -Body $jsonBody `
                        -ErrorAction Stop
                    
                    Write-Host "✓ Роль успешно обновлена через PATCH!" -ForegroundColor Green
                    $result = [PSCustomObject]@{
                        Success = $true
                        Method = "PATCH"
                        RoleId = $RoleId
                        RoleTitle = $roleTitle
                        ApiResponse = $response
                    }
                    
                } catch {
                    Write-Error "Все методы обновления не сработали. Последняя ошибка: $($_.Exception.Message)"
                    
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
        }
        
        return $result
        
    } catch {
        Write-Error "Не удалось обновить роль: $_"
        return $null
    }
}
