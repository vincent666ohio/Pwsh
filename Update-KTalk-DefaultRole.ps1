function Update-KTalk-DefaultRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AuthToken,
        
        [ValidateSet("default", "defaultAnonymousUser", "both")]
        [string]$RoleType = "default",
        
        [string]$TemplatePath,
        
        [array]$AddPermissions,
        
        [array]$RemovePermissions,
        
        [array]$EnablePermissions,    # Новый параметр: включить разрешения (disabled=false)
        
        [array]$DisablePermissions,   # Новый параметр: отключить разрешения (disabled=true)
        
        [switch]$UseCurrentAsBase,
        
        [switch]$KeepCommonPermissions,
        
        [switch]$DryRun
    )
    
    # Внутренняя функция для получения текущих разрешений роли
    function Get-CurrentRolePermissions {
        param([string]$roleId)
        
        $url = "https://7n1uf25w.ktalk.ru/api/roles/defaults"
        $headers = @{"X-Auth-Token" = $AuthToken}
        
        try {
            $currentRoles = Invoke-RestMethod -Uri $url -Headers $headers
            $role = $currentRoles | Where-Object { $_.roleId -eq $roleId }
            
            if ($null -eq $role) {
                Write-Warning "Роль с ID '$roleId' не найдена"
                return @()
            }
            
            $permissions = @()
            foreach ($perm in $role.permissions) {
                $permissionObj = New-Object PSObject -Property @{
                    productId = $perm.productId
                    permissionId = $perm.permissionId
                    permissionTitle = $perm.title
                    disabled = $perm.disabled
                }
                $permissions += $permissionObj
            }
            
            return $permissions
            
        } catch {
            Write-Error "Ошибка при получении роли '$roleId': $_"
            return @()
        }
    }
    
    # Внутренняя функция для обработки изменений роли
    function Invoke-RoleChangesProcessing {
        param(
            [string]$RoleId,
            [string]$RoleName,
            [switch]$DryRunMode
        )
        
        Write-Host "`nОбработка роли: $RoleName (ID: $RoleId)" -ForegroundColor Cyan
        
        if ($DryRunMode) {
            Write-Host "ТЕСТОВЫЙ РЕЖИМ (DryRun) - изменения не будут применены" -ForegroundColor Magenta
        }
        
        # Создаем базовый список разрешений
        $basePermissions = @()
        
        if ($UseCurrentAsBase) {
            # Используем текущие разрешения как базовые
            $currentPerms = Get-CurrentRolePermissions -roleId $RoleId
            foreach ($perm in $currentPerms) {
                $permissionObj = New-Object PSObject -Property @{
                    productId = $perm.productId
                    permissionId = $perm.permissionId
                    disabled = $perm.disabled
                }
                $basePermissions += $permissionObj
            }
            Write-Host "Текущих разрешений: $($basePermissions.Count)" -ForegroundColor Gray
            
            # Показываем текущие разрешения если их немного
            if ($currentPerms.Count -le 15) {
                Write-Host "Текущие разрешения (disabled в скобках):" -ForegroundColor DarkGray
                foreach ($perm in $currentPerms) {
                    $status = if ($perm.disabled) { "Отключено" } else { "Включено" }
                    $color = if ($perm.disabled) { "Red" } else { "Green" }
                    Write-Host "  - $($perm.productId)/$($perm.permissionId): $status" -ForegroundColor $color
                }
            }
        }
        elseif (-not [string]::IsNullOrEmpty($TemplatePath)) {
            # Загружаем из шаблона
            $template = Import-KTalk-RoleTemplate -Path $TemplatePath
            if ($null -ne $template) {
                foreach ($perm in $template.Permissions) {
                    $basePermissions += $perm
                }
                Write-Host "Загружено из шаблона: $($basePermissions.Count)" -ForegroundColor Gray
            }
        }
        else {
            Write-Error "Не указан источник разрешений. Используйте -UseCurrentAsBase или -TemplatePath"
            return $null
        }
        
        # Добавляем разрешения
        if ($null -ne $AddPermissions -and $AddPermissions.Count -gt 0) {
            Write-Host "Разрешения для добавления ($($AddPermissions.Count)):" -ForegroundColor Green
            foreach ($perm in $AddPermissions) {
                $permissionObj = @{
                    productId = $perm.productId
                    permissionId = $perm.permissionId
                    disabled = $false
                }
                Write-Host "  + $($perm.productId)/$($perm.permissionId) (будет включено)" -ForegroundColor Green
                $basePermissions += $permissionObj
            }
        }
        
        # Удаляем разрешения
        $removedCount = 0
        if ($null -ne $RemovePermissions -and $RemovePermissions.Count -gt 0) {
            Write-Host "Разрешения для удаления ($($RemovePermissions.Count)):" -ForegroundColor Yellow
            $filteredPermissions = @()
            foreach ($perm in $basePermissions) {
                $shouldRemove = $false
                foreach ($removePerm in $RemovePermissions) {
                    if ($perm.productId -eq $removePerm.productId -and 
                        $perm.permissionId -eq $removePerm.permissionId) {
                        $shouldRemove = $true
                        Write-Host "  - $($perm.productId)/$($perm.permissionId) (будет удалено)" -ForegroundColor Yellow
                        $removedCount++
                        break
                    }
                }
                if (-not $shouldRemove) {
                    $filteredPermissions += $perm
                }
            }
            $basePermissions = $filteredPermissions
        }
        
        # Включаем разрешения (устанавливаем disabled=false)
        $enabledCount = 0
        if ($null -ne $EnablePermissions -and $EnablePermissions.Count -gt 0) {
            Write-Host "Разрешения для включения ($($EnablePermissions.Count)):" -ForegroundColor Green
            foreach ($permToEnable in $EnablePermissions) {
                $found = $false
                for ($i = 0; $i -lt $basePermissions.Count; $i++) {
                    if ($basePermissions[$i].productId -eq $permToEnable.productId -and 
                        $basePermissions[$i].permissionId -eq $permToEnable.permissionId) {
                        # Обновляем существующее разрешение
                        $basePermissions[$i].disabled = $false
                        Write-Host "  ✓ $($permToEnable.productId)/$($permToEnable.permissionId) (будет включено)" -ForegroundColor Green
                        $enabledCount++
                        $found = $true
                        break
                    }
                }
                if (-not $found) {
                    # Добавляем новое разрешение с disabled=false
                    $permissionObj = @{
                        productId = $permToEnable.productId
                        permissionId = $permToEnable.permissionId
                        disabled = $false
                    }
                    $basePermissions += $permissionObj
                    Write-Host "  + $($permToEnable.productId)/$($permToEnable.permissionId) (будет добавлено и включено)" -ForegroundColor Green
                }
            }
        }
        
        # Отключаем разрешения (устанавливаем disabled=true)
        $disabledCount = 0
        if ($null -ne $DisablePermissions -and $DisablePermissions.Count -gt 0) {
            Write-Host "Разрешения для отключения ($($DisablePermissions.Count)):" -ForegroundColor Yellow
            foreach ($permToDisable in $DisablePermissions) {
                $found = $false
                for ($i = 0; $i -lt $basePermissions.Count; $i++) {
                    if ($basePermissions[$i].productId -eq $permToDisable.productId -and 
                        $basePermissions[$i].permissionId -eq $permToDisable.permissionId) {
                        # Обновляем существующее разрешение
                        $basePermissions[$i].disabled = $true
                        Write-Host "  ⚠ $($permToDisable.productId)/$($permToDisable.permissionId) (будет отключено)" -ForegroundColor Yellow
                        $disabledCount++
                        $found = $true
                        break
                    }
                }
                if (-not $found) {
                    # Добавляем новое разрешение с disabled=true
                    $permissionObj = @{
                        productId = $permToDisable.productId
                        permissionId = $permToDisable.permissionId
                        disabled = $true
                    }
                    $basePermissions += $permissionObj
                    Write-Host "  + $($permToDisable.productId)/$($permToDisable.permissionId) (будет добавлено и отключено)" -ForegroundColor Yellow
                }
            }
        }
        
        # Показываем итоговый список разрешений с их статусом
        Write-Host "`nИтоговые разрешения ($($basePermissions.Count)):" -ForegroundColor Cyan
        
        if ($basePermissions.Count -eq 0) {
            Write-Warning "Список разрешений пуст. Все разрешения будут отозваны у роли." -ForegroundColor Red
        } else {
            # Сортируем по статусу для лучшей читаемости
            $enabledPerms = $basePermissions | Where-Object { $_.disabled -eq $false } | Sort-Object productId, permissionId
            $disabledPerms = $basePermissions | Where-Object { $_.disabled -eq $true } | Sort-Object productId, permissionId
            
            if ($enabledPerms.Count -gt 0) {
                Write-Host "Включенные разрешения ($($enabledPerms.Count)):" -ForegroundColor Green
                foreach ($perm in $enabledPerms) {
                    Write-Host "  ✓ $($perm.productId)/$($perm.permissionId)" -ForegroundColor Green
                }
            }
            
            if ($disabledPerms.Count -gt 0) {
                Write-Host "Отключенные разрешения ($($disabledPerms.Count)):" -ForegroundColor Gray
                foreach ($perm in $disabledPerms) {
                    Write-Host "  ⚠ $($perm.productId)/$($perm.permissionId) (disabled=true)" -ForegroundColor Gray
                }
            }
            
            # Статистика изменений
            $changesSummary = @()
            if ($AddPermissions -and $AddPermissions.Count -gt 0) {
                $changesSummary += "Добавлено: $($AddPermissions.Count)"
            }
            if ($removedCount -gt 0) {
                $changesSummary += "Удалено: $removedCount"
            }
            if ($enabledCount -gt 0) {
                $changesSummary += "Включено: $enabledCount"
            }
            if ($disabledCount -gt 0) {
                $changesSummary += "Отключено: $disabledCount"
            }
            
            if ($changesSummary.Count -gt 0) {
                Write-Host "`nСводка изменений: $($changesSummary -join ', ')" -ForegroundColor Cyan
            }
        }
        
        if ($DryRunMode) {
            Write-Host "`nТЕСТОВЫЙ РЕЖИМ: Запрос НЕ отправляется в API" -ForegroundColor Magenta
            
            $result = [PSCustomObject]@{
                Success = $true
                RoleName = $RoleName
                RoleId = $RoleId
                Message = "DryRun - изменения не применены"
                PermissionsCount = $basePermissions.Count
                EnabledCount = ($basePermissions | Where-Object { $_.disabled -eq $false }).Count
                DisabledCount = ($basePermissions | Where-Object { $_.disabled -eq $true }).Count
                Permissions = $basePermissions
                Status = "DryRun"
                AddedCount = if ($AddPermissions) { $AddPermissions.Count } else { 0 }
                RemovedCount = $removedCount
                EnabledPermissionsCount = $enabledCount
                DisabledPermissionsCount = $disabledCount
            }
            
            return $result
        } else {
            # Преобразуем разрешения в формат для API (убираем поле disabled если false)
            $apiPermissions = @()
            foreach ($perm in $basePermissions) {
                $apiPerm = @{
                    productId = $perm.productId
                    permissionId = $perm.permissionId
                }
                
                # Добавляем disabled только если true
                if ($perm.disabled -eq $true) {
                    $apiPerm.disabled = $true
                }
                
                $apiPermissions += $apiPerm
            }
            
            # Применяем изменения
            return Set-KTalk-DefaultRole -AuthToken $AuthToken -Permissions $apiPermissions -RoleId $RoleId
        }
    }
    
    # Проверяем конфликты параметров
    $actionCount = 0
    if ($AddPermissions -and $AddPermissions.Count -gt 0) { $actionCount++ }
    if ($RemovePermissions -and $RemovePermissions.Count -gt 0) { $actionCount++ }
    if ($EnablePermissions -and $EnablePermissions.Count -gt 0) { $actionCount++ }
    if ($DisablePermissions -and $DisablePermissions.Count -gt 0) { $actionCount++ }
    if ($TemplatePath) { $actionCount++ }
    if ($UseCurrentAsBase) { $actionCount++ }
    
    if ($actionCount -eq 0) {
        Write-Error "Не указано ни одного действия. Используйте хотя бы один из параметров: -AddPermissions, -RemovePermissions, -EnablePermissions, -DisablePermissions, -TemplatePath, -UseCurrentAsBase"
        return $null
    }
    
    # Основная логика в зависимости от типа роли
    $results = @()
    
    if ($DryRun) {
        Write-Host "=============================================" -ForegroundColor Magenta
        Write-Host "ТЕСТОВЫЙ РЕЖИМ (DRY RUN) ДЛЯ Update-KTalk-DefaultRole" -ForegroundColor Magenta
        Write-Host "Показываю планируемые изменения без их применения" -ForegroundColor Magenta
        Write-Host "=============================================" -ForegroundColor Magenta
    }
    
    switch ($RoleType) {
        "default" {
            $result = Invoke-RoleChangesProcessing -RoleId "default" -RoleName "Пользователь" -DryRunMode:$DryRun
            if ($null -ne $result) { 
                $results += $result 
            }
        }
        
        "defaultAnonymousUser" {
            $result = Invoke-RoleChangesProcessing -RoleId "defaultAnonymousUser" -RoleName "Анонимный пользователь" -DryRunMode:$DryRun
            if ($null -ne $result) { 
                $results += $result 
            }
        }
        
        "both" {
            Write-Host "Одновременное обновление обеих ролей по умолчанию" -ForegroundColor Cyan
            
            if ($KeepCommonPermissions) {
                Write-Host "Режим синхронизации: сохраняем общие разрешения" -ForegroundColor Cyan
                
                # Получаем текущие разрешения обеих ролей
                $defaultPerms = Get-CurrentRolePermissions -roleId "default"
                $anonymousPerms = Get-CurrentRolePermissions -roleId "defaultAnonymousUser"
                
                # Находим общие разрешения
                $commonPermissions = @()
                foreach ($defaultPerm in $defaultPerms) {
                    foreach ($anonymousPerm in $anonymousPerms) {
                        if ($defaultPerm.productId -eq $anonymousPerm.productId -and 
                            $defaultPerm.permissionId -eq $anonymousPerm.permissionId) {
                            $permissionObj = @{
                                productId = $defaultPerm.productId
                                permissionId = $defaultPerm.permissionId
                                disabled = $defaultPerm.disabled
                            }
                            $commonPermissions += $permissionObj
                            break
                        }
                    }
                }
                
                Write-Host "Общих разрешений найдено: $($commonPermissions.Count)" -ForegroundColor Cyan
                
                if ($DryRun) {
                    Write-Host "ТЕСТОВЫЙ РЕЖИМ: Общие разрешения будут применены к обеим ролям" -ForegroundColor Magenta
                    
                    # DryRun для первой роли
                    $result1 = [PSCustomObject]@{
                        Success = $true
                        RoleName = "Пользователь"
                        RoleId = "default"
                        Message = "DryRun - общие разрешения"
                        PermissionsCount = $commonPermissions.Count
                        EnabledCount = ($commonPermissions | Where-Object { $_.disabled -eq $false }).Count
                        DisabledCount = ($commonPermissions | Where-Object { $_.disabled -eq $true }).Count
                        Permissions = $commonPermissions
                        Status = "DryRun"
                    }
                    
                    # DryRun для второй роли
                    $result2 = [PSCustomObject]@{
                        Success = $true
                        RoleName = "Анонимный пользователь"
                        RoleId = "defaultAnonymousUser"
                        Message = "DryRun - общие разрешения"
                        PermissionsCount = $commonPermissions.Count
                        EnabledCount = ($commonPermissions | Where-Object { $_.disabled -eq $false }).Count
                        DisabledCount = ($commonPermissions | Where-Object { $_.disabled -eq $true }).Count
                        Permissions = $commonPermissions
                        Status = "DryRun"
                    }
                    
                    if ($null -ne $result1) { $results += $result1 }
                    if ($null -ne $result2) { $results += $result2 }
                } else {
                    # Преобразуем для API
                    $apiPermissions = @()
                    foreach ($perm in $commonPermissions) {
                        $apiPerm = @{
                            productId = $perm.productId
                            permissionId = $perm.permissionId
                        }
                        if ($perm.disabled -eq $true) {
                            $apiPerm.disabled = $true
                        }
                        $apiPermissions += $apiPerm
                    }
                    
                    # Применяем общие разрешения к обеим ролям
                    $result1 = Set-KTalk-DefaultRole -AuthToken $AuthToken -Permissions $apiPermissions -RoleId "default"
                    $result2 = Set-KTalk-DefaultRole -AuthToken $AuthToken -Permissions $apiPermissions -RoleId "defaultAnonymousUser"
                    
                    if ($null -ne $result1) { $results += $result1 }
                    if ($null -ne $result2) { $results += $result2 }
                }
            } else {
                # Обновляем обе роли независимо
                $result1 = Invoke-RoleChangesProcessing -RoleId "default" -RoleName "Пользователь" -DryRunMode:$DryRun
                $result2 = Invoke-RoleChangesProcessing -RoleId "defaultAnonymousUser" -RoleName "Анонимный пользователь" -DryRunMode:$DryRun
                
                if ($null -ne $result1) { $results += $result1 }
                if ($null -ne $result2) { $results += $result2 }
            }
        }
    }
    
    # Выводим сводку по результатам
    Write-Host "`n=== Сводка операции ===" -ForegroundColor Cyan
    
    if ($DryRun) {
        Write-Host "РЕЖИМ ПРОСМОТРА (DryRun)" -ForegroundColor Magenta
        Write-Host "Никакие изменения НЕ были применены к API" -ForegroundColor Magenta
    }
    
    $successCount = ($results | Where-Object { $_.Success -eq $true }).Count
    $dryRunCount = ($results | Where-Object { $_.Status -eq "DryRun" }).Count
    
    Write-Host "Обработано ролей: $($results.Count)" -ForegroundColor Gray
    
    if ($DryRun) {
        Write-Host "Режим DryRun: $dryRunCount ролей" -ForegroundColor Magenta
        
        # Показываем детали по каждой роли в DryRun
        foreach ($result in $results) {
            Write-Host "`nРоль: $($result.RoleName) ($($result.RoleId))" -ForegroundColor Yellow
            Write-Host "Всего разрешений: $($result.PermissionsCount)" -ForegroundColor White
            Write-Host "Включено: $($result.EnabledCount)" -ForegroundColor Green
            Write-Host "Отключено: $($result.DisabledCount)" -ForegroundColor Gray
            
            if ($result.AddedCount -gt 0) { Write-Host "Будет добавлено: $($result.AddedCount)" -ForegroundColor Green }
            if ($result.RemovedCount -gt 0) { Write-Host "Будет удалено: $($result.RemovedCount)" -ForegroundColor Yellow }
            if ($result.EnabledPermissionsCount -gt 0) { Write-Host "Будет включено: $($result.EnabledPermissionsCount)" -ForegroundColor Green }
            if ($result.DisabledPermissionsCount -gt 0) { Write-Host "Будет отключено: $($result.DisabledPermissionsCount)" -ForegroundColor Yellow }
        }
    } else {
        Write-Host "Успешно обновлено: $successCount ролей" -ForegroundColor Green
    }
    
    Write-Host "`nДля применения изменений запустите команду без параметра -DryRun" -ForegroundColor Cyan
    
    return $results
}
