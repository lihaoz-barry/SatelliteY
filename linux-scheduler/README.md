# Linux Scheduled Services

## 📁 File Overview

| File | Purpose |
|------|---------|
| `config.sh` | Configuration (task list, IP, API Key) |
| `daily_tasks.sh` | Daily check-in script (scheduled execution) |
| `wake-antigravity.sh` | Wake PC and ensure Antigravity app is running |
| `interval_checkin.sh` | Test script (loop execution) |
| `deploy.sh` | **Deploy script** (one-click update, auto-backup) |
| `rollback.sh` | **Rollback script** (restore previous config) |
| `daily-checkin.timer` | systemd timer (daily at 02:00) |
| `daily-checkin.service` | systemd service for daily check-in |
| `wake-antigravity.timer` | systemd timer (daily at 08:50) |
| `wake-antigravity.service` | systemd service for Antigravity app |

---

## 🚀 生产部署 (DietPi)

### 一键部署命令

SSH 登录到 Pi 后，运行以下命令：

```bash
# 1. 拉取最新代码
cd ~/SatelliteY
git fetch origin
git checkout feature/apply-to-prod
git pull

# 2. 创建部署目录并复制文件
sudo mkdir -p /opt/satellite-y
sudo cp linux-scheduler/*.sh /opt/satellite-y/
sudo cp linux-scheduler/*.timer linux-scheduler/*.service /etc/systemd/system/

# 3. 启用并启动定时器
sudo systemctl daemon-reload
sudo systemctl enable daily-checkin.timer
sudo systemctl start daily-checkin.timer

# 4. 验证
systemctl list-timers | grep daily
```

### 🔄 更新已部署的服务 (推荐)

使用 `deploy.sh` 脚本自动完成更新:

```bash
cd ~/SatelliteY
git pull
sudo ./linux-scheduler/deploy.sh
```

脚本功能:
- ✅ 自动拉取代码
- ✅ 显示配置对比 (before/after diff)
- ✅ 复制文件到部署目录
- ✅ 重启 systemd 服务
- ✅ 验证部署状态

**先预览不部署:**
```bash
./linux-scheduler/deploy.sh --dry-run
```

### 验证部署

```bash
# 查看定时器状态
sudo systemctl status daily-checkin.timer

# 手动测试（不等待定时器）
sudo systemctl start daily-checkin.service
sudo journalctl -u daily-checkin.service -f
```

---

## 🔙 回滚到上一版本

如果部署后发现问题,可以回滚到之前的备份:

```bash
# 查看可用备份
./linux-scheduler/rollback.sh --list

# 回滚到最近的备份
sudo ./linux-scheduler/rollback.sh

# 回滚到指定备份
sudo ./linux-scheduler/rollback.sh 20240103_021500

# 先预览不实际回滚
./linux-scheduler/rollback.sh --dry-run
```

📦 备份存储在: `/opt/satellite-y/backups/` (自动保留最近 5 个)

---

## ⚙️ 配置

编辑 `/opt/satellite-y/config.sh`：

```bash
# 添加/修改任务
TASKS=(
    "/execute/ai|/1mu3|1688 签到"
    "/execute/ai|/iyf|IYF 任务"
)

# 修改 API Key
COMET_API_KEY="your-key"
```

---

## 📅 修改执行时间

编辑 `/etc/systemd/system/daily-checkin.timer`：

```ini
OnCalendar=*-*-* 02:00:00   # 每天 02:00
OnCalendar=*-*-* 08:00:00   # 每天 08:00
```

修改后重载：
```bash
sudo systemctl daemon-reload
sudo systemctl restart daily-checkin.timer
```

---

## 📊 View Logs

```bash
# systemd logs
sudo journalctl -u daily-checkin.service -f
sudo journalctl -u wake-antigravity.service -f

# Script logs
tail -f ~/logs/daily_checkin/*.log
tail -f ~/logs/wake_antigravity/*.log
```

---

## 🛠️ Setting Up Timer Services on Linux

This section explains how to set up systemd timer services on any Linux system with systemd.

### Understanding systemd Timers

systemd timers consist of two files:
- **`.timer`** - Defines when the service runs (schedule)
- **`.service`** - Defines what runs (the actual command/script)

### Step-by-Step Setup

#### 1. Copy Files to System Directories

```bash
# Copy scripts to deployment directory
sudo mkdir -p /opt/satellite-y
sudo cp linux-scheduler/*.sh /opt/satellite-y/
sudo chmod +x /opt/satellite-y/*.sh

# Copy systemd unit files
sudo cp linux-scheduler/*.service /etc/systemd/system/
sudo cp linux-scheduler/*.timer /etc/systemd/system/
```

#### 2. Reload systemd Configuration

```bash
sudo systemctl daemon-reload
```

#### 3. Enable and Start Timers

```bash
# Enable timers to start on boot
sudo systemctl enable daily-checkin.timer
sudo systemctl enable wake-antigravity.timer

# Start timers immediately
sudo systemctl start daily-checkin.timer
sudo systemctl start wake-antigravity.timer
```

#### 4. Verify Timer Status

```bash
# List all active timers
systemctl list-timers --all

# Check specific timer status
sudo systemctl status wake-antigravity.timer
sudo systemctl status daily-checkin.timer
```

### Modifying Timer Schedule

Edit the timer file to change the schedule:

```bash
sudo nano /etc/systemd/system/wake-antigravity.timer
```

Common `OnCalendar` examples:
```ini
OnCalendar=*-*-* 08:50:00        # Every day at 8:50 AM
OnCalendar=Mon-Fri 08:50:00      # Weekdays only at 8:50 AM
OnCalendar=*-*-* 09:00,12:00:00  # Every day at 9:00 AM and 12:00 PM
OnCalendar=hourly                # Every hour
```

After editing, reload and restart:
```bash
sudo systemctl daemon-reload
sudo systemctl restart wake-antigravity.timer
```

### Manual Testing

```bash
# Trigger service immediately (without waiting for timer)
sudo systemctl start wake-antigravity.service

# Watch logs in real-time
sudo journalctl -u wake-antigravity.service -f

# Test with dry-run (no actual execution)
/opt/satellite-y/wake-antigravity.sh --dry-run
```

### Troubleshooting

```bash
# Check if timer is active
systemctl is-active wake-antigravity.timer

# View timer details
systemctl show wake-antigravity.timer

# Check service logs for errors
sudo journalctl -u wake-antigravity.service --since "1 hour ago"

# Reset failed state
sudo systemctl reset-failed wake-antigravity.service
```

### Disabling a Timer

```bash
# Stop and disable timer
sudo systemctl stop wake-antigravity.timer
sudo systemctl disable wake-antigravity.timer
```
