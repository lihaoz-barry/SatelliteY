# Linux 每日签到定时服务

## 📁 文件说明

| 文件 | 用途 |
|------|------|
| `config.sh` | 配置文件（任务列表、IP、API Key） |
| `daily_tasks.sh` | 生产脚本（每天定时执行） |
| `interval_checkin.sh` | 测试脚本（循环执行） |
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

### 验证部署

```bash
# 查看定时器状态
sudo systemctl status daily-checkin.timer

# 手动测试（不等待定时器）
sudo systemctl start daily-checkin.service
sudo journalctl -u daily-checkin.service -f
```

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
