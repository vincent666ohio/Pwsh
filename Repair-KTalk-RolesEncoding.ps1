function Repair-KTalk-RolesEncoding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AuthToken,
        
        [string[]]$RoleIds,
        
        [string]$TemplatePath,
        
        [switch]$FixAll,
        
        [switch]$DryRun
    )
    
    Write-Host "Начинаю исправление кодировки ролей..." -ForegroundColor Cyan
    
    # 1. Получаем все роли
    $allRoles = Get-KTalk-Roles -AuthToken $AuthToken
    if ($null -eq $allRoles) {
        Write-Error "Не удалось получить список ролей"
        return @()
    }
    
    # 2. Фильтруем роли для исправления
    $rolesToFix = @()
    
    if ($FixAll) {
        $rolesToFix = $allRoles | Where-Object { 
            $_.Editable -eq $true -and $_.RoleId -notin @("default", "defaultAnonymousUser")
        }
        Write-Host "Будут исправлены ВСЕ изменяемые пользовательские роли ($($rolesToFix.Count) ролей)" -ForegroundColor Yellow
    }
    elseif ($RoleIds.Count -gt 0) {
        foreach ($roleId in $RoleIds) {
            $role = $allRoles | Where-Object { $_.RoleId -eq $roleId }
            if ($role) {
                $rolesToFix += $role
            } else {
                Write-Warning "Роль с ID '$roleId' не найдена"
            }
        }
    }
    else {
        # Ищем роли с некорректной кодировкой (содержат знаки вопроса)
        $rolesToFix = $allRoles | Where-Object { 
            $_.Title -match '\?' -or 
            $_.Description -match '\?' -or
            ($_.Title -match '^[?]+$')  # Только знаки вопроса
        }
        
        if ($rolesToFix.Count -eq 0) {
            Write-Host "Не найдено ролей с проблемами кодировки" -ForegroundColor Green
            return @()
        }
        
        Write-Host "Найдено $($rolesToFix.Count) ролей с возможными проблемами кодировки" -ForegroundColor Yellow
    }
    
    # 3. Загружаем шаблон если указан
    $template = $null
    if (-not [string]::IsNullOrEmpty($TemplatePath)) {
        $template = Import-KTalk-RoleTemplate -Path $TemplatePath
        if ($null -eq $template) {
            Write-Warning "Не удалось загрузить шаблон, буду использовать текущие данные роли"
        }
    }
    
    # 4. Исправляем каждую роль
    $results = @()
    
    foreach ($role in $rolesToFix) {
        Write-Host "`n--- Обработка: $($role.RoleId) ---" -ForegroundColor Cyan
        Write-Host "Текущее название: $($role.Title)" -ForegroundColor Gray
        Write-Host "Текущее описание: $($role.Description)" -ForegroundColor Gray
        
        # Определяем новое название и описание
        $newTitle = $role.Title -replace '\?+', ''  # Убираем знаки вопроса
        
        if ($template -and $template.Title -notin @("ROLE_TITLE", "НАЗВАНИЕ_РОЛИ")) {
            # Используем название из шаблона БЕЗ добавления RoleId
            $newTitle = $template.Title
        }
        elseif ([string]::IsNullOrWhiteSpace($newTitle) -or $newTitle -match '^[?]+$') {
            # Если после очистки название пустое
            $newTitle = "Роль_$($role.RoleId)"
        }
        
        $newDescription = $role.Description -replace '\?+', ''
        
        # Добавляем идентификатор роли в описание
        $idInfo = "Идентификатор роли: $($role.RoleId)"
        
        if ($template -and $template.Description -notin @("ROLE_DESCRIPTION", "ОПИСАНИЕ_РОЛИ")) {
            # Добавляем идентификатор к описанию из шаблона
            $newDescription = "$($template.Description). $idInfo"
        }
        elseif ([string]::IsNullOrWhiteSpace($newDescription) -or $newDescription -match '^[?]+$') {
            # Если описание пустое или содержит только знаки вопроса
            $newDescription = $idInfo
        }
        else {
            # Добавляем идентификатор к существующему описанию
            $newDescription = "$newDescription. $idInfo"
        }
        
        Write-Host "Новое название: $newTitle" -ForegroundColor Yellow
        Write-Host "Новое описание: $newDescription" -ForegroundColor Yellow
        
        if ($DryRun) {
            Write-Host "ТЕСТОВЫЙ РЕЖИМ - Будет обновлена роль $($role.RoleId)" -ForegroundColor Magenta
            $results += [PSCustomObject]@{
                RoleId = $role.RoleId
                OldTitle = $role.Title
                OldDescription = $role.Description
                NewTitle = $newTitle
                NewDescription = $newDescription
                Status = "DryRun"
            }
        } else {
            # Создаем временный шаблон для обновления
            $tempTemplate = @{
                roleInfo = @{
                    title = $newTitle
                    description = $newDescription
                }
                permissions = if ($template) { $template.Permissions } else { @() }
            }
            
            $tempTemplatePath = "$env:TEMP\temp_role_$($role.RoleId).json"
            $tempTemplate | ConvertTo-Json -Depth 3 | Out-File $tempTemplatePath -Encoding UTF8
            
            # Обновляем роль
            $result = Set-KTalk-Role `
                -AuthToken $AuthToken `
                -RoleId $role.RoleId `
                -TemplatePath $tempTemplatePath `
                -NewTitle $newTitle `
                -NewDescription $newDescription
            
            # Удаляем временный файл
            Remove-Item $tempTemplatePath -ErrorAction SilentlyContinue
            
            if ($result -and $result.Success) {
                Write-Host "✓ Успешно исправлена роль $($role.RoleId)" -ForegroundColor Green
                $results += [PSCustomObject]@{
                    RoleId = $role.RoleId
                    OldTitle = $role.Title
                    OldDescription = $role.Description
                    NewTitle = $newTitle
                    NewDescription = $newDescription
                    Status = "Success"
                    Method = $result.Method
                }
            } else {
                Write-Warning "Не удалось исправить роль $($role.RoleId)"
                $results += [PSCustomObject]@{
                    RoleId = $role.RoleId
                    OldTitle = $role.Title
                    OldDescription = $role.Description
                    NewTitle = $newTitle
                    NewDescription = $newDescription
                    Status = "Failed"
                }
            }
        }
    }
    
    # 5. Выводим сводку
    Write-Host "`n=== Сводка исправлений ===" -ForegroundColor Cyan
    $successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
    $failedCount = ($results | Where-Object { $_.Status -eq "Failed" }).Count
    $dryRunCount = ($results | Where-Object { $_.Status -eq "DryRun" }).Count
    
    if ($DryRun) {
        Write-Host "Тестовый режим: Будет исправлено $dryRunCount ролей" -ForegroundColor Magenta
    } else {
        Write-Host "Успешно исправлено: $successCount ролей" -ForegroundColor Green
        if ($failedCount -gt 0) {
            Write-Host "Не удалось исправить: $failedCount ролей" -ForegroundColor Red
        }
    }
    
    # 6. Показываем детальную информацию об изменениях
    if ($results.Count -gt 0) {
        Write-Host "`nДетали изменений:" -ForegroundColor Cyan
        foreach ($result in $results) {
            Write-Host "`nРоль: $($result.RoleId)" -ForegroundColor Yellow
            Write-Host "  Было название: $($result.OldTitle)" -ForegroundColor Gray
            Write-Host "  Стало название: $($result.NewTitle)" -ForegroundColor Green
            if ($result.OldDescription -ne $result.NewDescription) {
                Write-Host "  Было описание: $($result.OldDescription)" -ForegroundColor Gray
                Write-Host "  Стало описание: $($result.NewDescription)" -ForegroundColor Green
            }
            Write-Host "  Статус: $($result.Status)" -ForegroundColor $(if ($result.Status -eq "Success") {"Green"} elseif ($result.Status -eq "Failed") {"Red"} else {"Magenta"})
        }
    }
    
    return $results
}
