function Get-KTalk-Roles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AuthToken,
        
        [string]$Url = "https://7n1uf25w.ktalk.ru/api/roles"
    )
    
    $headers = @{"X-Auth-Token" = $AuthToken}
    
    try {
        Write-Host "Requesting all roles from API..." -ForegroundColor Cyan
        $response = Invoke-RestMethod -Uri $Url -Headers $headers -Method Get
        
        Write-Host "Successfully retrieved $($response.Count) roles" -ForegroundColor Green
        
        # Преобразуем ответ для удобства, если нужно
        $processedRoles = @()
        foreach ($role in $response) {
            $roleObj = New-Object PSObject -Property @{
                RoleId = $role.roleId
                Title = $role.title
                Description = $role.description
                Editable = $role.editable
                PermissionsCount = if ($role.permissions) { $role.permissions.Count } else { 0 }
                # Можно добавить и сами разрешения, если они приходят в ответе:
                # Permissions = $role.permissions
            }
            $processedRoles += $roleObj
        }
        
        return $processedRoles
        
    } catch {
        Write-Error "Error retrieving roles: $_"
        
        # Обработка ошибки 404, если эндпоинт не найден
        if ($_.Exception.Response.StatusCode.Value__ -eq 404) {
            Write-Warning "Endpoint $Url not found (404). The API might not support listing all roles."
            Write-Host "Trying to check available endpoints from API documentation..." -ForegroundColor Yellow
        }
        return $null
    }
}
