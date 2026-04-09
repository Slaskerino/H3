Import-Module ActiveDirectory

$OU = "OU=dmeem,DC=dmeem,DC=local"
$rootPath = "\\fil01\Homefolders"

$users = Get-ADUser -SearchBase $OU -Filter *

foreach ($user in $users) {
    $username = $user.SamAccountName
    $homePath = Join-Path $rootPath $username

    # Create folder if it doesn't exist
    if (!(Test-Path $homePath)) {
        New-Item -ItemType Directory -Path $homePath | Out-Null
        Write-Host "Created folder: $homePath"
    }

    # Get ACL
    $acl = Get-Acl $homePath

    # Disable inheritance and remove inherited permissions
    $acl.SetAccessRuleProtection($true, $false)

    # Remove existing explicit rules
    $acl.Access | ForEach-Object {
        $acl.RemoveAccessRule($_)
    }

    # Define access rules

    # User: Modify (instead of FullControl)
    $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $username,
        "Modify",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )

    # Administrators: Full Control
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators",
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )

    # SYSTEM: Full Control
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "SYSTEM",
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )

    # Apply rules
    $acl.AddAccessRule($userRule)
    $acl.AddAccessRule($adminRule)
    $acl.AddAccessRule($systemRule)

    # Set ACL
    Set-Acl -Path $homePath -AclObject $acl

    # Set AD attributes
    Set-ADUser -Identity $user `
        -HomeDirectory $homePath `
        -HomeDrive "H:"

    Write-Host "Configured $username"
}