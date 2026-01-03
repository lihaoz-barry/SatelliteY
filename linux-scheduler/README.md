# Linux 每日签到定时服务

## 📁 文件说明

| 文件 | 用途 |
|------|------|
| `config.sh` | 配置文件（任务列表、IP、API Key） |
| `daily_tasks.sh` | 生产脚本（每天定时执行） |
| `interval_checkin.sh` | 测试脚本（循环执行） |
| `deploy.sh` | **部署脚本**（一键更新，自动备份） |
| `rollback.sh` | **回滚脚本**（恢复到之前的配置） |
| `daily-checkin.timer` | systemd 定时器（每天 02:00） |
| `daily-checkin.service` | systemd 服务配置 |

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

## 📊 查看日志

```bash
# systemd 日志
sudo journalctl -u daily-checkin.service -f

# 脚本日志
tail -f ~/logs/daily_checkin/*.log
```
