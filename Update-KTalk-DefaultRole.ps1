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
                }
                $basePermissions += $permissionObj
            }
            Write-Host "Текущих разрешений: $($basePermissions.Count)" -ForegroundColor Gray
            
            # Показываем текущие разрешения если их немного
            if ($currentPerms.Count -le 10) {
                Write-Host "Текущие разрешения:" -ForegroundColor DarkGray
                foreach ($perm in $currentPerms) {
                    Write-Host "  - $($perm.productId)/$($perm.permissionId): $($perm.permissionTitle)" -ForegroundColor Gray
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
                Write-Host "  + $($perm.productId)/$($perm.permissionId)" -ForegroundColor Green
                $basePermissions += $perm
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
                        Write-Host "  - $($perm.productId)/$($perm.permissionId)" -ForegroundColor Yellow
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
        
        # Показываем итоговый список разрешений
        Write-Host "`nИтоговые разрешения ($($basePermissions.Count)):" -ForegroundColor Cyan
        if ($basePermissions.Count -eq 0) {
            Write-Warning "Список разрешений пуст. Все разрешения будут отозваны у роли." -ForegroundColor Red
        } else {
            foreach ($perm in $basePermissions) {
                Write-Host "  • $($perm.productId)/$($perm.permissionId)" -ForegroundColor Gray
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
                Permissions = $basePermissions
                Status = "DryRun"
                AddedCount = if ($AddPermissions) { $AddPermissions.Count } else { 0 }
                RemovedCount = $removedCount
            }
            
            return $result
        } else {
            # Применяем изменения
            return Set-KTalk-DefaultRole -AuthToken $AuthToken -Permissions $basePermissions -RoleId $RoleId
        }
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
                            $permissionObj = New-Object PSObject -Property @{
                                productId = $defaultPerm.productId
                                permissionId = $defaultPerm.permissionId
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
                        Permissions = $commonPermissions
                        Status = "DryRun"
                    }
                    
                    if ($null -ne $result1) { $results += $result1 }
                    if ($null -ne $result2) { $results += $result2 }
                } else {
                    # Применяем общие разрешения к обеим ролям
                    $result1 = Set-KTalk-DefaultRole -AuthToken $AuthToken -Permissions $commonPermissions -RoleId "default"
                    $result2 = Set-KTalk-DefaultRole -AuthToken $AuthToken -Permissions $commonPermissions -RoleId "defaultAnonymousUser"
                    
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
            Write-Host "Будет установлено разрешений: $($result.PermissionsCount)" -ForegroundColor Gray
            if ($result.PermissionsCount -gt 0) {
                Write-Host "Разрешения:" -ForegroundColor DarkGray
                foreach ($perm in $result.Permissions) {
                    Write-Host "  - $($perm.productId)/$($perm.permissionId)" -ForegroundColor Gray
                }
            }
        }
    } else {
        Write-Host "Успешно обновлено: $successCount ролей" -ForegroundColor Green
    }
    
    Write-Host "`nДля применения изменений запустите команду без параметра -DryRun" -ForegroundColor Cyan
    
    return $results
}
