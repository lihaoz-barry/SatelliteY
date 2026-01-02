# Linux 每日签到定时服务部署指南

## 兼容性

| 系统 | 状态 | 备注 |
|------|------|------|
| **DietPi (Raspberry Pi)** | ✅ 完全兼容 | 主要目标平台 |
| **macOS** | ✅ 脚本兼容 | 可用于调试 |
| **其他 Linux** | ✅ 兼容 | Ubuntu, Debian, etc. |

---

## 🚀 两种运行模式

### 测试模式（立即测试）

```bash
# 方法 1：直接运行脚本（PC 已开机时推荐）
./daily_checkin.sh --test

# 方法 2：使用测试用定时器（1分钟后触发）
sudo cp daily-checkin-test.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start daily-checkin-test.timer

# 监控执行结果
sudo journalctl -u daily-checkin.service -f
```

### 生产模式（每天定时执行）

```bash
# 使用生产定时器（默认每天 02:00）
sudo cp daily-checkin.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable daily-checkin.timer
sudo systemctl start daily-checkin.timer
```

---

## 快速部署 (DietPi)

### 1. 复制文件到 Raspberry Pi

```bash
# 通过 SSH 复制
scp -r linux-scheduler/* dietpi@YOUR_PI_IP:/tmp/
```

### 2. 安装脚本

```bash
ssh dietpi@YOUR_PI_IP

# 创建目录并复制脚本
sudo mkdir -p /opt/satellite-y
sudo cp /tmp/daily_checkin.sh /opt/satellite-y/
sudo chmod +x /opt/satellite-y/daily_checkin.sh

# 复制 systemd 配置
sudo cp /tmp/daily-checkin.service /etc/systemd/system/
sudo cp /tmp/daily-checkin.timer /etc/systemd/system/

# 可选：复制测试用定时器
sudo cp /tmp/daily-checkin-test.timer /etc/systemd/system/
```

### 3. 启用定时器

```bash
sudo systemctl daemon-reload

# 生产模式
sudo systemctl enable daily-checkin.timer
sudo systemctl start daily-checkin.timer

# 验证状态
systemctl list-timers | grep daily
```

---

## macOS 快速测试

```bash
# 进入目录
cd linux-scheduler

# 赋予执行权限
chmod +x daily_checkin.sh

# 测试模式（PC 已开机）
./daily_checkin.sh --test

# 或跳过唤醒直接签到
./daily_checkin.sh --skip-wake

# 完整流程（会唤醒 PC）
./daily_checkin.sh
```

---

## 命令行参数

| 参数 | 说明 |
|------|------|
| `--test`, `-t` | 测试模式：跳过唤醒，缩短等待时间 |
| `--skip-wake`, `-s` | 跳过唤醒步骤（PC 已开机时使用） |
| `--help`, `-h` | 显示帮助信息 |

---

## 修改定时时间

编辑 `/etc/systemd/system/daily-checkin.timer`：

```ini
# 常用时间格式示例
OnCalendar=*-*-* 02:00:00        # 每天凌晨 2:00
OnCalendar=*-*-* 08:00:00        # 每天早上 8:00
OnCalendar=Mon,Fri 02:00:00      # 每周一、五 凌晨 2:00
```

修改后重新加载：
```bash
sudo systemctl daemon-reload
sudo systemctl restart daily-checkin.timer
```

---

## 查看日志

```bash
# systemd 日志
sudo journalctl -u daily-checkin.service -f

# 脚本日志文件
tail -f ~/daily_checkin.log
```
