# Windows 自动登录配置指南

> 📅 创建日期：2026-01-01  
> 📌 适用系统：Windows 10 / Windows 11

---

## 目录

1. [什么是自动登录](#什么是自动登录)
2. [方法一：通过 netplwiz 配置（推荐）](#方法一通过-netplwiz-配置推荐)
3. [方法二：通过注册表配置](#方法二通过注册表配置)
4. [方法三：使用 Sysinternals Autologon 工具](#方法三使用-sysinternals-autologon-工具)
5. [如何恢复（关闭自动登录）](#如何恢复关闭自动登录)
6. [安全注意事项](#安全注意事项)

---

## 什么是自动登录

启用自动登录后：
- ✅ 电脑启动后自动进入桌面，无需输入密码
- ✅ 从睡眠/休眠唤醒后自动解锁
- ✅ 远程设备可以在重启后自动恢复工作状态

> [!WARNING]
> 自动登录会将密码以加密形式存储在注册表中。仅在**物理安全**的环境下使用（如家用个人电脑）。

---

## 方法一：通过 netplwiz 配置（推荐）

### ⚠️ 前置步骤（必须先执行！）

由于你使用的是 **Microsoft 账户**（如 lihaoz0214@gmail.com），Windows 默认隐藏了自动登录选项。需要先执行以下步骤：

**Step 1: 以管理员身份打开 PowerShell**
- 右键点击「开始」按钮
- 选择 **"Windows Terminal (Admin)"** 或 **"PowerShell (Admin)"**

**Step 2: 运行以下命令**
```powershell
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device" /v DevicePasswordLessBuildVersion /t REG_DWORD /d 0 /f
```

成功后会显示：`The operation completed successfully.`

**Step 3: 关闭并重新打开 netplwiz**

---

### 开启自动登录

1. 按 `Win + R` 打开运行对话框
2. 输入 `netplwiz` 并按回车
3. 现在你应该能看到复选框了：
   - **English**: ☐ "Users must enter a user name and password to use this computer"
   - **中文**: ☐ "要使用本计算机，用户必须输入用户名和密码"
4. **取消勾选** 这个复选框
5. 点击「Apply」或「应用」
6. 在弹出的对话框中输入你的 **Microsoft 账户密码**（两次确认）
7. 点击「OK」
8. **重启电脑**测试

> [!TIP]
> 如果使用 Microsoft 账户，密码是你的 **Microsoft 账户密码**，不是 PIN 码！


---

## 方法二：通过注册表配置

### 开启自动登录

以**管理员身份**运行 PowerShell，执行以下命令：

```powershell
# 设置自动登录（替换 YOUR_USERNAME 和 YOUR_PASSWORD）
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "1"
Set-ItemProperty -Path $RegPath -Name "DefaultUserName" -Value "lihaoz0214@gmail.com"
Set-ItemProperty -Path $RegPath -Name "DefaultPassword" -Value "Aa!717398"

# 可选：指定域名（本地账户通常是计算机名或空）
Set-ItemProperty -Path $RegPath -Name "DefaultDomainName" -Value ""

Write-Host "✅ 自动登录已配置，请重启电脑测试"
```

### 一键脚本（交互式）

创建脚本 `enable_autologin.ps1`：

```powershell
# enable_autologin.ps1 - 交互式启用自动登录

$username = Read-Host "请输入用户名"
$password = Read-Host "请输入密码" -AsSecureString
$plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
)

$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "1"
Set-ItemProperty -Path $RegPath -Name "DefaultUserName" -Value $username
Set-ItemProperty -Path $RegPath -Name "DefaultPassword" -Value $plainPassword
Set-ItemProperty -Path $RegPath -Name "DefaultDomainName" -Value ""

Write-Host "`n✅ 自动登录已启用！" -ForegroundColor Green
Write-Host "   用户: $username"
Write-Host "   请重启电脑测试"
```

---

## 方法三：使用 Sysinternals Autologon 工具

微软官方提供的安全工具，密码会加密存储：

1. 下载：https://docs.microsoft.com/en-us/sysinternals/downloads/autologon
2. 以管理员身份运行 `Autologon.exe`
3. 填入用户名和密码
4. 点击「Enable」

---

## 如何恢复（关闭自动登录）

### 方法 A：通过 netplwiz

1. `Win + R` → `netplwiz`
2. **勾选** ☑ "要使用本计算机，用户必须输入用户名和密码"
3. 点击「应用」→「确定」

### 方法 B：通过注册表

```powershell
# 以管理员身份运行 PowerShell
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

# 禁用自动登录
Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "0"

# 删除存储的密码（安全起见）
Remove-ItemProperty -Path $RegPath -Name "DefaultPassword" -ErrorAction SilentlyContinue

Write-Host "✅ 自动登录已禁用"
```

### 一键脚本

创建脚本 `disable_autologin.ps1`：

```powershell
# disable_autologin.ps1 - 禁用自动登录

$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "0"
Remove-ItemProperty -Path $RegPath -Name "DefaultPassword" -ErrorAction SilentlyContinue

Write-Host "✅ 自动登录已禁用！" -ForegroundColor Yellow
Write-Host "   下次启动将需要输入密码"
```

---

## 安全注意事项

| 风险 | 说明 | 缓解措施 |
|------|------|----------|
| 物理访问 | 任何人开机即可访问你的账户 | 仅在家用/安全环境使用 |
| 密码存储 | 密码存储在注册表（加密） | 定期更换密码，使用 Sysinternals 工具 |
| 远程桌面 | 自动登录不影响 RDP 安全 | RDP 仍需密码 |

### 推荐设置

对于你的个人电脑场景（物理安全，需要自动化）：

```
✅ 启用自动登录（本文档方法一或二）
✅ 保持 Windows 防火墙开启
✅ 保持 Windows Defender 开启
⚠️ 如有重要数据，使用 BitLocker 加密磁盘
```

---

## 快速命令参考

```powershell
# 检查当前自动登录状态
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" | Select-Object AutoAdminLogon, DefaultUserName

# 快速启用（替换用户名和密码）
$P = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty $P -Name AutoAdminLogon -Value 1
Set-ItemProperty $P -Name DefaultUserName -Value "Barry"
Set-ItemProperty $P -Name DefaultPassword -Value "YOUR_PASSWORD"

# 快速禁用
Set-ItemProperty $P -Name AutoAdminLogon -Value 0
Remove-ItemProperty $P -Name DefaultPassword -EA 0
```

---

*文档结束*
