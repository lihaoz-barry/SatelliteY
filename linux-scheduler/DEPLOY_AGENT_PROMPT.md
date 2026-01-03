# SatelliteY 部署任务 - Coding Agent Prompt

## 📋 任务快速版 (直接复制)

```
请帮我更新 SatelliteY 的 Linux 定时服务。执行以下步骤:

1. 进入 ~/SatelliteY 目录,运行 git pull 拉取最新代码
2. 对比 linux-scheduler/ 和 /opt/satellite-y/ 的配置差异
3. 复制所有 .sh 文件到 /opt/satellite-y/
4. 复制 .timer 和 .service 文件到 /etc/systemd/system/
5. 运行 systemctl daemon-reload
6. 运行 systemctl restart daily-checkin.timer
7. 验证 timer 状态并显示下次执行时间

每一步都显示执行结果,最后总结部署是否成功。
```

---

## 🚀 完整版 Prompt (带详细验证)

```
我需要你帮我在 Raspberry Pi 上更新 SatelliteY 定时任务服务。

## 背景
- 代码仓库: ~/SatelliteY
- 源文件目录: ~/SatelliteY/linux-scheduler/
- 部署目录: /opt/satellite-y/
- Systemd 配置目录: /etc/systemd/system/
- 服务名称: daily-checkin.timer 和 daily-checkin.service

## 执行步骤

### Step 1: 拉取最新代码
cd ~/SatelliteY
git fetch origin
git pull
显示当前分支和最新 commit hash

### Step 2: 对比配置 (部署前)
对比以下文件的差异:
- config.sh (任务配置)
- daily_tasks.sh (主脚本)
特别关注 TASKS 数组中的任务列表有无变化

### Step 3: 复制文件
sudo cp ~/SatelliteY/linux-scheduler/*.sh /opt/satellite-y/
sudo cp ~/SatelliteY/linux-scheduler/*.timer /etc/systemd/system/
sudo cp ~/SatelliteY/linux-scheduler/*.service /etc/systemd/system/
sudo chmod +x /opt/satellite-y/*.sh

### Step 4: 重载并重启服务
sudo systemctl daemon-reload
sudo systemctl restart daily-checkin.timer

### Step 5: 验证部署
1. 运行: systemctl status daily-checkin.timer
2. 运行: systemctl list-timers | grep daily
3. 显示 /opt/satellite-y/config.sh 中的 TASKS 数组
4. 确认 timer 状态为 active

### 输出要求
- 每一步显示执行命令和结果
- 如果有文件差异,显示 diff 输出
- 最后给出总结:
  ✓ 部署成功 / ✗ 部署失败
  ✓ 定时器状态: active/inactive
  ✓ 下次执行时间: [时间]
  ✓ 已配置的任务数量: [数量]
```

---

## 🔧 使用现成脚本版

如果已经部署了 deploy.sh 脚本,直接告诉 agent:

```
运行 SatelliteY 部署脚本:

cd ~/SatelliteY
git pull
sudo ./linux-scheduler/deploy.sh

查看输出并确认部署成功。
```

或者先预览不实际部署:

```
cd ~/SatelliteY
git pull
./linux-scheduler/deploy.sh --dry-run
```

---

## 📌 参数说明

| 场景 | 命令 |
|------|------|
| 完整部署 | `sudo ./deploy.sh` |
| 只预览不部署 | `./deploy.sh --dry-run` |
| 跳过 git pull | `sudo ./deploy.sh --skip-pull` |
| 手动测试 | `sudo systemctl start daily-checkin.service` |
| 查看日志 | `sudo journalctl -u daily-checkin.service -f` |

---

## ⚠️ 注意事项

1. **需要 sudo 权限** - 复制到 /opt 和 /etc 需要 root
2. **不会中断现有任务** - 如果任务正在执行,会等待完成
3. **立即生效** - 下次定时触发将使用新配置
4. **回滚方法** - `git checkout HEAD~1` 然后重新部署
